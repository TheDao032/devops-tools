#!/usr/bin/env bash
# Publish a tenant's vagrant boxes (virtualbox + qemu providers) to the
# HashiCorp Vagrant Cloud registry (app.vagrantup.com).
#
# Implements the granular CLI flow from packer/docs/vagrant-cloud-publish.md §5.2.
# Idempotent: box / version / provider creation steps probe-then-create so the
# script is safe to re-run after a partial failure.
#
# DEFAULT BEHAVIOR IS NON-RELEASING. Uploads always happen; the version is
# left in `unreleased` state until you re-invoke with `--release`. This is a
# deliberate human-in-the-loop gate — see docs/vagrant-cloud-publish.md §8.
#
# Usage:
#   ./scripts/publish.sh <tenant> [image_version] [flags...]
#
# Examples:
#   # Upload bosch arm64 boxes (both providers if both .box files exist).
#   # Latest local version is auto-detected; nothing is released yet.
#   VAGRANT_CLOUD_TOKEN=atlasv1.xxx ./scripts/publish.sh bosch
#
#   # Upload AND release a specific version. Use this only after smoke test.
#   VAGRANT_CLOUD_TOKEN=atlasv1.xxx \
#     ./scripts/publish.sh bosch 2026-05-05.1 --release
#
#   # See exactly what API calls would happen without executing them.
#   ./scripts/publish.sh bosch 2026-05-05.1 --dry-run
#
#   # Override box name / org (e.g. publishing under a personal account).
#   VAGRANT_CLOUD_ORG=mydev BOX_NAME=ubuntu2204-cisl1-arm64-test \
#     ./scripts/publish.sh bosch 2026-05-05.1
#
# Required env:
#   VAGRANT_CLOUD_TOKEN   API token from app.vagrantup.com (Account → Security
#                         → API tokens). Required unless you already ran
#                         `vagrant cloud auth login`.
#
# Optional env:
#   VAGRANT_CLOUD_ORG     Vagrant Cloud org/user the box lives under.
#                         Default: <tenant>. The full box tag is <ORG>/<BOX_NAME>.
#   BOX_NAME              Box name (the part after the slash in the tag).
#                         Default: ubuntu2204-cisl1-arm64
#   IMAGE_NAME_PREFIX     Local artifact filename prefix.
#                         Default: <tenant>-<BOX_NAME>
#   ARCH                  Box architecture string. Default: arm64.
#                         Currently only arm64 is wired (x86 path TBD).
#   BOX_DESCRIPTION_FILE  Path to markdown for the box's long description.
#                         Default: docs/box-description.md (silently ignored
#                         if missing — short description still gets sent).
#   RELEASE               "true" to release after upload. Equivalent to --release.
#   DRY_RUN               "true" to skip all API writes (probes still run).
#                         Equivalent to --dry-run.
#
# Exit codes:
#   0   success (uploads complete; release skipped or done per flag)
#   2   usage error (missing args, unknown tenant)
#   3   missing artifacts (no .box files found for this version)
#   4   missing auth (no VAGRANT_CLOUD_TOKEN and no cached token)
#   5   vagrant cloud CLI not available
#   1   propagated failure from a `vagrant cloud …` subcommand

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------- args ----------

TENANT="${1:-}"
shift || true

# Second positional may be a version OR a flag. If it starts with `--`, treat
# as a flag and leave version unset (we'll auto-detect latest below).
IMAGE_VERSION=""
if [[ "${1:-}" && "${1:-}" != --* ]]; then
  IMAGE_VERSION="$1"
  shift
fi

RELEASE_FLAG="${RELEASE:-false}"
DRY_RUN="${DRY_RUN:-false}"
BOX_DESCRIPTION_FILE="${BOX_DESCRIPTION_FILE:-${PACKER_DIR}/docs/box-description.md}"
VERSION_DESCRIPTION=""

# --providers comma-list filters which provider artifacts to publish in this
# run. Default (empty) = whatever .box files exist on disk for this version.
# Supports "virtualbox", "qemu", or both ("virtualbox,qemu" — same as default).
# Use this to stage providers one at a time, e.g. publish qemu, smoke-test,
# then publish virtualbox on the SAME version (the script is idempotent on
# box+version, it'll just add the new provider entry).
PROVIDERS_FILTER="${PROVIDERS:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)             RELEASE_FLAG=true ;;
    --dry-run)             DRY_RUN=true ;;
    --description-file)    BOX_DESCRIPTION_FILE="$2"; shift ;;
    --version-description) VERSION_DESCRIPTION="$2"; shift ;;
    --providers)           PROVIDERS_FILTER="$2"; shift ;;
    --providers=*)         PROVIDERS_FILTER="${1#*=}" ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \?//; /^set/d'
      exit 0
      ;;
    *) echo "ERROR: unknown flag '$1'" >&2; exit 2 ;;
  esac
  shift
done

usage() {
  cat <<EOF
Usage: $0 <tenant> [image_version] [--release] [--dry-run] \\
                                  [--providers virtualbox|qemu|virtualbox,qemu] \\
                                  [--description-file PATH] \\
                                  [--version-description STR]

  tenant         = bosch (only tenant currently wired for arm64 vagrant boxes)
  image_version  = optional; auto-detected from latest local artifact if omitted

See: packer/docs/vagrant-cloud-publish.md
EOF
  exit 2
}

[[ -z "${TENANT}" ]] && usage

case "${TENANT}" in
  bosch) ;;
  renesas)
    echo "ERROR: renesas publish path not wired (renesas is x86-only and ships qcow2-only)." >&2
    exit 2
    ;;
  *) echo "ERROR: unknown tenant '${TENANT}'" >&2; usage ;;
esac

ARCH="${ARCH:-arm64}"
case "${ARCH}" in
  arm64) ;;
  *)
    echo "ERROR: ARCH=${ARCH} not supported by publish.sh yet (only arm64 wired)." >&2
    exit 2
    ;;
esac

# ---------- defaults derived from tenant ----------

VAGRANT_CLOUD_ORG="${VAGRANT_CLOUD_ORG:-${TENANT}}"
BOX_NAME="${BOX_NAME:-ubuntu2204-cisl1-arm64}"
IMAGE_NAME_PREFIX="${IMAGE_NAME_PREFIX:-${TENANT}-${BOX_NAME}}"
BOX_TAG="${VAGRANT_CLOUD_ORG}/${BOX_NAME}"

# ---------- preflight ----------

if ! command -v vagrant >/dev/null 2>&1; then
  echo "ERROR: 'vagrant' not on PATH. Install Vagrant 2.4.3+ (multi-arch + HCP service-principal env-var support)." >&2
  exit 5
fi

# Confirm vagrant supports the cloud subcommand.
if ! vagrant cloud --help >/dev/null 2>&1; then
  echo "ERROR: this Vagrant build doesn't have 'cloud' subcommand. Need 2.4.3+." >&2
  exit 5
fi

# Auth: any one of these three paths satisfies the preflight.
#
#   1. HCP service principal env vars (modern, post-HCP-migration):
#        HCP_CLIENT_ID + HCP_CLIENT_SECRET
#      Vagrant ≥ 2.4.3 auto-exchanges these for an access token on each
#      `vagrant cloud …` call. See https://developer.hashicorp.com/vagrant/
#      vagrant-cloud/hcp-vagrant/post-migration-guide
#
#   2. Pre-exchanged access token via VAGRANT_CLOUD_TOKEN:
#        - Modern: VAGRANT_CLOUD_TOKEN="$(hcp auth print-access-token)"
#        - Composite (mixed migration): "<atlasv1>;<hcp_token>"  (buggy — GH #13529)
#        - Legacy (unmigrated): "atlasv1.…"
#
#   3. Cached login from a prior `vagrant cloud auth login` (legacy interactive).
#
# In --dry-run mode we skip this check (no API calls happen anyway).
if [[ "${DRY_RUN}" != "true" ]]; then
  TOKEN_CACHE="${HOME}/.vagrant.d/data/vagrant_login_token"
  if [[ -n "${HCP_CLIENT_ID:-}" && -n "${HCP_CLIENT_SECRET:-}" ]]; then
    echo "==> auth: HCP service principal (HCP_CLIENT_ID + HCP_CLIENT_SECRET)"
  elif [[ -n "${VAGRANT_CLOUD_TOKEN:-}" ]]; then
    echo "==> auth: VAGRANT_CLOUD_TOKEN (env)"
  elif [[ -s "${TOKEN_CACHE}" ]]; then
    echo "==> auth: cached vagrant cloud login (${TOKEN_CACHE})"
  else
    cat >&2 <<EOF
ERROR: no Vagrant Cloud / HCP Vagrant auth available.

Pick one of:

  # (modern) HCP service principal — Vagrant ≥ 2.4.3 auto-exchanges these:
  export HCP_CLIENT_ID="<from HCP IAM service principal key>"
  export HCP_CLIENT_SECRET="<from HCP IAM service principal key>"

  # OR a pre-exchanged token (still useful for older Vagrant):
  export VAGRANT_CLOUD_TOKEN="\$(hcp auth print-access-token)"

  # OR an interactive cached login (legacy):
  vagrant cloud auth login

Create a service principal at:
  https://portal.cloud.hashicorp.com/ → your org → Access control (IAM) → Service principals
EOF
    exit 4
  fi
fi

cd "${PACKER_DIR}"

# ---------- resolve version ----------

VBOX_DIR_BASE="output/${TENANT}/${ARCH}/virtualbox"
QEMU_DIR_BASE="output/${TENANT}/${ARCH}/qemu"

if [[ -z "${IMAGE_VERSION}" ]]; then
  # Pick the most recent version directory that contains at least one .box.
  candidates=()
  for base in "${VBOX_DIR_BASE}" "${QEMU_DIR_BASE}"; do
    [[ -d "${base}" ]] || continue
    for vdir in "${base}"/*/; do
      [[ -d "${vdir}" ]] || continue
      ver="$(basename "${vdir}")"
      if compgen -G "${vdir}*.box" >/dev/null; then
        candidates+=("${ver}")
      fi
    done
  done
  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "ERROR: no .box files found under ${VBOX_DIR_BASE}/* or ${QEMU_DIR_BASE}/*" >&2
    echo "       Run ./scripts/build.sh ${TENANT} all (or qemu/virtualbox) first." >&2
    exit 3
  fi
  # Sort descending, take the top.
  IMAGE_VERSION="$(printf '%s\n' "${candidates[@]}" | sort -ru | head -n1)"
  echo "==> auto-detected version: ${IMAGE_VERSION}"
fi

VBOX_BOX="${VBOX_DIR_BASE}/${IMAGE_VERSION}/${IMAGE_NAME_PREFIX}-${IMAGE_VERSION}.box"
QEMU_BOX="${QEMU_DIR_BASE}/${IMAGE_VERSION}/${IMAGE_NAME_PREFIX}-${IMAGE_VERSION}.box"

# Parse --providers filter (comma-separated list). Empty = no filter (all).
# Validate values up-front so a typo doesn't silently produce a no-op publish.
#
# macOS bash is forever 3.2.57 (no associative arrays — would need bash 4+),
# so we stash the allowed set as a delimited string and grep it.
PROVIDERS_ALLOWED_STR=""
if [[ -n "${PROVIDERS_FILTER}" ]]; then
  IFS=',' read -r -a _pf_split <<< "${PROVIDERS_FILTER}"
  for p in ${_pf_split[@]+"${_pf_split[@]}"}; do
    case "$p" in
      virtualbox|qemu) PROVIDERS_ALLOWED_STR="${PROVIDERS_ALLOWED_STR}|${p}|" ;;
      "") ;;  # tolerate trailing commas
      *) echo "ERROR: --providers unknown value '$p' (allowed: virtualbox, qemu)" >&2; exit 2 ;;
    esac
  done
fi

# Predicate: returns 0 if the named provider should be published this run.
want_provider() {
  # No filter set → publish whatever exists on disk.
  [[ -z "${PROVIDERS_ALLOWED_STR}" ]] && return 0
  [[ "${PROVIDERS_ALLOWED_STR}" == *"|${1}|"* ]]
}

# Build the provider-list of artifacts that actually exist on disk AND pass
# the --providers filter.
declare -a PROVIDERS=()
declare -a PROVIDER_FILES=()
if [[ -f "${VBOX_BOX}" ]] && want_provider virtualbox; then
  PROVIDERS+=("virtualbox")
  PROVIDER_FILES+=("${VBOX_BOX}")
fi
if [[ -f "${QEMU_BOX}" ]] && want_provider qemu; then
  PROVIDERS+=("qemu")
  PROVIDER_FILES+=("${QEMU_BOX}")
fi

if [[ ${#PROVIDERS[@]} -eq 0 ]]; then
  if [[ -n "${PROVIDERS_ALLOWED_STR}" ]]; then
    cat >&2 <<EOF
ERROR: --providers=${PROVIDERS_FILTER} requested but no matching .box files
       on disk for version ${IMAGE_VERSION}. Looked at:
   ${VBOX_BOX}
   ${QEMU_BOX}
EOF
  else
    cat >&2 <<EOF
ERROR: no .box files for version ${IMAGE_VERSION} at:
   ${VBOX_BOX}
   ${QEMU_BOX}

Run a build first:
   ARCH=arm64 STAGE=hardened ./scripts/build.sh ${TENANT} all
EOF
  fi
  exit 3
fi

# ---------- summary banner ----------

cat <<EOF

########################################################################
# Vagrant Cloud publish
#   box tag        : ${BOX_TAG}
#   version        : ${IMAGE_VERSION}
#   architecture   : ${ARCH}
#   providers      : ${PROVIDERS[*]}
#   release        : ${RELEASE_FLAG}
#   dry-run        : ${DRY_RUN}
########################################################################

EOF

# ---------- helpers ----------

# run: echo and execute a command, unless DRY_RUN=true (then echo only).
run() {
  echo "+ $*"
  if [[ "${DRY_RUN}" == "true" ]]; then
    return 0
  fi
  "$@"
}

# probe: silently check whether a `vagrant cloud … show` command succeeds.
# Under DRY_RUN we return non-zero unconditionally so the caller takes the
# "needs create" branch and the user sees every step that would happen.
#
# NOTE: As of Vagrant 2.4.x, only `vagrant cloud box show` exists. The legacy
# `version show` and `provider show` subcommands were removed (you can confirm
# via `vagrant cloud version --help` / `provider --help` — neither lists
# `show` in their subcommand table, and invoking `vagrant cloud version show …`
# silently prints help and exits 0, which would always false-positive a probe).
# For version/provider existence checks, use create_idempotent below.
probe() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    return 1
  fi
  vagrant cloud "$@" >/dev/null 2>&1
}

# create_idempotent: run a `vagrant cloud … create` command. If it fails with
# an already-exists / 422 error, treat as success (the desired state is the
# same either way). Any other failure propagates the original exit code.
#
# Replaces the legacy probe-then-create pattern for entities whose `show`
# subcommand no longer exists (version, provider).
create_idempotent() {
  echo "+ $*"
  if [[ "${DRY_RUN}" == "true" ]]; then
    return 0
  fi

  local logf rc
  logf="$(mktemp -t vagrant-cloud-publish.XXXXXX)"
  rc=0
  "$@" > "$logf" 2>&1 || rc=$?
  cat "$logf"

  if [[ $rc -eq 0 ]]; then
    rm -f "$logf"
    return 0
  fi
  # Tolerated error patterns — Vagrant Cloud / HCP Vagrant return one of these
  # when the box/version/provider already exists. Add more as observed.
  if grep -qiE 'already exists|has already been taken|registry already has|name has already|status code 422' "$logf"; then
    echo "    (already exists — tolerated)"
    rm -f "$logf"
    return 0
  fi
  rm -f "$logf"
  return $rc
}

# ---------- step 1: ensure box exists ----------

echo "==> [1/4] ensure box ${BOX_TAG}"
if probe box show "${BOX_TAG}"; then
  echo "    box already exists — skipping create"
else
  desc_args=()
  if [[ -f "${BOX_DESCRIPTION_FILE}" ]]; then
    desc_args+=(--description-from-file "${BOX_DESCRIPTION_FILE}")
  fi
  run vagrant cloud box create "${BOX_TAG}" \
    --short-description "Ubuntu 22.04 ${ARCH}, CIS Level 1 hardened, ${TENANT} tenant" \
    --private \
    ${desc_args[@]+"${desc_args[@]}"}
fi

# ---------- step 2: ensure version exists ----------

echo "==> [2/4] ensure version ${IMAGE_VERSION}"
ver_desc="${VERSION_DESCRIPTION:-Build ${IMAGE_VERSION}}"
create_idempotent vagrant cloud version create "${BOX_TAG}" "${IMAGE_VERSION}" \
  --description "${ver_desc}"

# ---------- step 3: per-provider create + upload ----------

# Expand `qemu` → `qemu` AND `libvirt` provider slots (same .box file).
#
# WHY: when a consumer runs `vagrant up --provider qemu`, the vagrant-qemu
# plugin internally asks the registry for a `libvirt`-tagged box (it reuses
# vagrant-libvirt's box format — see ppggff/vagrant-qemu README).
# If we upload only as provider=qemu, the consumer pull fails with:
#   "Box ... could not be found. Requested provider: libvirt"
# Uploading the SAME .box file under both slots keeps both consumer
# paths working: `vagrant box add --provider qemu` (rare) and the
# default `vagrant up --provider qemu` (what registry users actually do).
#
# Verified live 2026-05-20: nthedao2705/ubuntu2204-cisl1-arm64@2026-05-20.1
# initially uploaded as qemu only → 404 on consumer pull. Re-uploaded same
# file as libvirt → `vagrant up` reached "Machine booted and ready!".
#
# See memory: feedback_packer_vagrant_pp_no_qemu.md
EXPANDED_PROVIDERS=()
EXPANDED_FILES=()
for i in "${!PROVIDERS[@]}"; do
  prov="${PROVIDERS[$i]}"
  file="${PROVIDER_FILES[$i]}"
  case "$prov" in
    qemu)
      # Upload the same file under both slots.
      EXPANDED_PROVIDERS+=("qemu");    EXPANDED_FILES+=("$file")
      EXPANDED_PROVIDERS+=("libvirt"); EXPANDED_FILES+=("$file")
      ;;
    *)
      EXPANDED_PROVIDERS+=("$prov");   EXPANDED_FILES+=("$file")
      ;;
  esac
done

for i in "${!EXPANDED_PROVIDERS[@]}"; do
  provider="${EXPANDED_PROVIDERS[$i]}"
  file="${EXPANDED_FILES[$i]}"

  echo ""
  echo "==> [3/4] provider=${provider}  arch=${ARCH}  file=${file}"

  # Idempotent provider create. `vagrant cloud provider show` does not exist
  # as of Vagrant 2.4.x — we just attempt create and tolerate the
  # already-exists/422 response. `--architecture` IS still a valid option on
  # `provider create` (verified `vagrant cloud provider create --help`).
  create_idempotent vagrant cloud provider create "${BOX_TAG}" "${provider}" "${IMAGE_VERSION}" \
    --architecture "${ARCH}" \
    --no-default-architecture

  # Upload always runs; vagrant cloud overwrites existing file slots on the
  # same (provider, architecture, version). If the version is already
  # released, this fails — that's the point: cut a new version instead.
  #
  # CLI SIGNATURE CHANGE (Vagrant 2.4.x): `architecture` is now a POSITIONAL
  # argument (4th), not a `--architecture` flag. The full positional order is:
  #   vagrant cloud provider upload <org/box> <provider> <version> <arch> <box-file>
  echo "    uploading ${file} ($(du -h "${file}" | cut -f1))…"
  run vagrant cloud provider upload "${BOX_TAG}" "${provider}" "${IMAGE_VERSION}" "${ARCH}" "${file}"
done

# ---------- step 4: release (gated) ----------

echo ""
if [[ "${RELEASE_FLAG}" == "true" ]]; then
  echo "==> [4/4] releasing version ${IMAGE_VERSION}"
  # --force bypasses the interactive "release? [y/N]" prompt that otherwise
  # makes `vagrant cloud version release` unusable from non-TTY contexts
  # (CI, scripted pipelines, claude-driven workflows). Verified flag exists
  # via `vagrant cloud version release --help` on Vagrant 2.4.9.
  run vagrant cloud version release --force "${BOX_TAG}" "${IMAGE_VERSION}"
  cat <<EOF

==> Released. Consumers can now:
       vagrant init ${BOX_TAG}
       vagrant up --provider virtualbox    # or --provider qemu
EOF
else
  cat <<EOF
==> [4/4] release SKIPPED (default).
   The version is uploaded but invisible to \`vagrant up\`. To release:
     $0 ${TENANT} ${IMAGE_VERSION} --release

   First, smoke-test the box on a clean Apple Silicon Mac:
     vagrant init ${BOX_TAG}
     # Edit Vagrantfile to pin: config.vm.box_version = "${IMAGE_VERSION}"
     # (otherwise vagrant only sees released versions)
     # Use a direct .box add to test pre-release:
     vagrant box add --name ${BOX_TAG} ${PROVIDER_FILES[0]} --architecture ${ARCH}
EOF
fi

echo ""
echo "==> done."
