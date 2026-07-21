#!/usr/bin/env bash
# Wrapper for tenant-aware Packer builds.
#
# ═══ CLI ══════════════════════════════════════════════════════════════════
#
# amd64 (default arch — layered pkrvars composition):
#   ./scripts/build.sh <tenant> <guest> <provider> [image_version]
#
#     tenant   = renesas | bosch | nthedao (arm64-only)
#     guest    = ubuntu2204 | ubuntu2404 | rhel9
#     provider = virtualbox | qemu | vmware | all
#
# arm64 (two-stage flow — unchanged, uses guest-less CLI):
#   ARCH=arm64 [STAGE=base|hardened|all] ./scripts/build.sh <tenant> <provider> [image_version]
#
#     tenant   = bosch (22.04) | nthedao (24.04) | archlinux (ALARM rolling)
#                (renesas arm64 not supported)
#     provider = virtualbox | qemu | all
#     org folder selects the template: templates/<org>/ + variables/<org>/
#     archlinux stage 1 is a tarball bootstrap script (no ISO); see
#     scripts/rootfs-bootstrap/ + docs/archlinux-arm64-runbook.md.
#
# ═══ pkrvars composition (amd64) ══════════════════════════════════════════
#
# Every build stacks four var-files in this order:
#
#   variables/common.pkrvars.hcl               — sizing, timeouts, output_base_dir
#   variables/local.pkrvars.hcl                — MACHINE-LOCAL (iso_cache_prefix, gitignored)
#   variables/guest/<guest>-amd64.pkrvars.hcl  — iso_filename, iso_checksum, guest_slug
#   variables/tenants/<tenant>.pkrvars.hcl     — compliance_profile, banner, image_name_prefix
#
# Guest → template mapping:
#   ubuntu*  →  templates/_base/ubuntu-amd64.pkr.hcl   (subiquity autoinstall)
#   rhel*    →  templates/_base/rhel-amd64.pkr.hcl     (anaconda kickstart)
#
# ═══ Environment variables ════════════════════════════════════════════════
#
#   ARCH                          = amd64 (default) | arm64
#   STAGE                         = base | hardened | all (default; arm64 only)
#   BASE_VERSION                  = base image version   (arm64 STAGE=base or all)
#   BASE_IMAGE_PATH               = override base qcow2  (arm64 STAGE=hardened)
#   BASE_OVA_PATH                 = override base .ova   (arm64 STAGE=hardened)
#   RHEL_USERNAME / RHEL_PASSWORD = required for renesas (subscription-manager)
#
# ═══ Examples ═════════════════════════════════════════════════════════════
#
#   # amd64
#   ./scripts/build.sh bosch ubuntu2204 virtualbox
#   ./scripts/build.sh bosch ubuntu2404 virtualbox 2026-07-08.1
#   ./scripts/build.sh renesas rhel9 qemu
#
#   # arm64 (unchanged)
#   ARCH=arm64 ./scripts/build.sh bosch qemu
#   ARCH=arm64 STAGE=hardened ./scripts/build.sh bosch virtualbox
#   ARCH=arm64 STAGE=hardened BASE_IMAGE_PATH=output/base/ubuntu2204-arm64/2026-05-03/ubuntu2204-arm64-base-2026-05-03.qcow2 \
#     ./scripts/build.sh bosch qemu
#
# ═══ Two-stage build (arm64, org-folder templates) ════════════════════════
#
#   stage 1 = "base"     — clean Ubuntu 22.04 ARM64 OS install, no ansible
#   stage 2 = "hardened" — boots stage 1's image, runs the compliance role
#   stage   = "all"      — both serially (default)
#   provider dispatch:
#     qemu       → qcow2 only            (Proxmox prod fleet)
#     virtualbox → .ova + .box           (Apple Silicon vagrant)
#     all        → both, parallel under one packer build
#
# amd64 arm64 refactor pending — arm64 stays on old CLI for now.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARCH="${ARCH:-amd64}"
STAGE="${STAGE:-all}"
BASE_VERSION="${BASE_VERSION:-$(date +%F)}"

# ═══ CLI parsing — form differs by ARCH ═══════════════════════════════════
TENANT="${1:-}"
if [[ "${ARCH}" == "arm64" ]]; then
  # OLD form: <tenant> <provider> [image_version]
  GUEST=""                       # unused on arm64 (org folder picks the template: bosch=22.04, nthedao=24.04)
  PROVIDER="${2:-}"
  IMAGE_VERSION="${3:-$(date +%F).1}"
else
  # NEW form (amd64): <tenant> <guest> <provider> [image_version]
  GUEST="${2:-}"
  PROVIDER="${3:-}"
  IMAGE_VERSION="${4:-$(date +%F).1}"
fi

usage() {
  cat <<EOF
Usage:

  amd64 (default):   $0 <tenant> <guest> <provider> [image_version]
  arm64:             ARCH=arm64 $0 <tenant> <provider> [image_version]

  tenant   = renesas | bosch | nthedao | archlinux   (nthedao/archlinux arm64-only)
  guest    = ubuntu2204 | ubuntu2404 | rhel9   (amd64 only)
  provider = virtualbox | qemu | vmware | all
  image_version (optional) — defaults to YYYY-MM-DD.1

Env vars consumed:
  ARCH                          = amd64 (default) | arm64
  STAGE                         = base | hardened | all (default; arm64 only)
  BASE_VERSION                  = base image version   (default: \$(date +%F))
  BASE_IMAGE_PATH               = override base qcow2  (arm64 STAGE=hardened)
  BASE_OVA_PATH                 = override base .ova   (arm64 STAGE=hardened)
  RHEL_USERNAME / RHEL_PASSWORD = required for renesas (subscription-manager)

Examples:
  $0 bosch ubuntu2204 virtualbox
  $0 bosch ubuntu2404 virtualbox 2026-07-08.1
  $0 renesas rhel9 qemu
  ARCH=arm64 $0 bosch qemu
EOF
  exit 2
}

[[ -z "${TENANT}" || -z "${PROVIDER}" ]] && usage
if [[ "${ARCH}" == "amd64" && -z "${GUEST}" ]]; then usage; fi

case "${TENANT}" in
  renesas|bosch) ;;
  nthedao) ;;     # arm64-only personal lab line (24.04); amd64 has no tenants/nthedao.pkrvars.hcl
  archlinux) ;;   # arm64-only Arch Linux ARM line; stage 1 = tarball bootstrap script, not packer
  *) echo "ERROR: unknown tenant '${TENANT}'"; usage ;;
esac

case "${PROVIDER}" in
  virtualbox|qemu|vmware|all) ;;
  *) echo "ERROR: unknown provider '${PROVIDER}'"; usage ;;
esac

case "${ARCH}" in
  amd64|arm64) ;;
  *) echo "ERROR: unknown ARCH '${ARCH}' (expected amd64 or arm64)"; exit 2 ;;
esac

case "${STAGE}" in
  base|hardened|all) ;;
  *) echo "ERROR: unknown STAGE '${STAGE}' (expected base, hardened, or all)"; exit 2 ;;
esac

# Two-stage is arm64-only. STAGE is silently ignored on amd64.
if [[ "${ARCH}" == "amd64" && "${STAGE}" != "all" ]]; then
  echo "WARN: STAGE=${STAGE} ignored — two-stage build is arm64-only."
fi

# ═══ amd64 dispatch — new pkrvars composition ═════════════════════════════
if [[ "${ARCH}" == "amd64" ]]; then

  # renesas amd64 is supported; only rhel* guests are valid for it.
  # bosch amd64 is supported; only ubuntu* guests are valid for it.
  # (This is a soft convention — tenant + guest pair is not enforced at
  # script level. The compliance role is what actually differs by tenant;
  # you *could* bake bosch/rhel9 if you really wanted to.)

  case "${GUEST}" in
    ubuntu2204|ubuntu2404)
      TEMPLATE="templates/_base/ubuntu-amd64.pkr.hcl"
      SRC_LEAF="ubuntu"
      BUILD_NAME="ubuntu-amd64"
      ;;
    rhel9)
      TEMPLATE="templates/_base/rhel-amd64.pkr.hcl"
      SRC_LEAF="rhel"
      BUILD_NAME="rhel-amd64"
      ;;
    *)
      echo "ERROR: unknown guest '${GUEST}' (expected ubuntu2204, ubuntu2404, or rhel9)"
      usage
      ;;
  esac

  GUEST_VAR_FILE="variables/guest/${GUEST}-amd64.pkrvars.hcl"
  TENANT_VAR_FILE="variables/tenants/${TENANT}.pkrvars.hcl"
  LOCAL_VAR_FILE="variables/local.pkrvars.hcl"

  # -only filter selects the provider source.
  SRC_VBOX="${BUILD_NAME}.virtualbox-iso.${SRC_LEAF}"
  SRC_QEMU="${BUILD_NAME}.qemu.${SRC_LEAF}"
  SRC_VMW="${BUILD_NAME}.vmware-iso.${SRC_LEAF}"
  case "${PROVIDER}" in
    virtualbox) ONLY_FILTER="${SRC_VBOX}" ;;
    qemu)       ONLY_FILTER="${SRC_QEMU}" ;;
    vmware)     ONLY_FILTER="${SRC_VMW}"  ;;
    all)        ONLY_FILTER="${SRC_VBOX},${SRC_QEMU},${SRC_VMW}" ;;
  esac

  # Verify referenced var-files exist so we fail early with a useful message.
  for f in "${TEMPLATE}" "${GUEST_VAR_FILE}" "${TENANT_VAR_FILE}"; do
    if [[ ! -f "${PACKER_DIR}/${f}" ]]; then
      echo "ERROR: expected file not found: ${f}" >&2
      exit 8
    fi
  done
  if [[ ! -f "${PACKER_DIR}/${LOCAL_VAR_FILE}" ]]; then
    cat <<EOF >&2
ERROR: ${LOCAL_VAR_FILE} not found.

This file is machine-local (gitignored) and holds your ISO cache path.
Create it once per machine, e.g.:

    cat > ${PACKER_DIR}/${LOCAL_VAR_FILE} <<'EOF2'
    iso_cache_prefix = "file://${HOME}/iso-cache"
    EOF2

Then re-run.
EOF
    exit 8
  fi

# ═══ arm64 dispatch — old CLI, unchanged (see below) ══════════════════════
else
  # Legacy tenant-arch mapping for arm64.
  case "${TENANT}-${ARCH}" in
    renesas-arm64)
      cat <<EOF >&2
ERROR: renesas-arm64 is not supported.
RHEL FIPS 140-3 validation is x86_64-only. Bake renesas images on x86 hosts only.
See ADR 2026-05-02-multi-arch-image-baking for the rationale and follow-ups.
EOF
      exit 4
      ;;
    bosch-arm64)
      TEMPLATE_BASE="templates/_base/ubuntu2204-arm64-base.pkr.hcl"
      TEMPLATE_HARDENED="templates/bosch/ubuntu2204-arm64-hardened.pkr.hcl"
      VAR_FILE_BASE="variables/_base/ubuntu2204-arm64-base.pkrvars.hcl"
      VAR_FILE_HARDENED="variables/bosch/arm64.pkrvars.hcl"
      BASE_SLUG="ubuntu2204-arm64"                       # base source label + output/base/<slug> dir + qcow2 name prefix
      HARDENED_SRC_LABEL="bosch-ubuntu2204-arm64"        # stage-2 source name in the hardened template
      BUILD_NAME_BASE="ubuntu2204-arm64-base"
      BUILD_NAME_HARDENED="bosch-ubuntu2204-arm64-hardened"
      ;;
    nthedao-arm64)
      TEMPLATE_BASE="templates/_base/ubuntu2404-arm64-base.pkr.hcl"
      TEMPLATE_HARDENED="templates/nthedao/ubuntu2404-arm64-hardened.pkr.hcl"
      VAR_FILE_BASE="variables/_base/ubuntu2404-arm64-base.pkrvars.hcl"
      VAR_FILE_HARDENED="variables/nthedao/arm64.pkrvars.hcl"
      BASE_SLUG="ubuntu2404-arm64"
      HARDENED_SRC_LABEL="nthedao-ubuntu2404-arm64"
      BUILD_NAME_BASE="ubuntu2404-arm64-base"
      BUILD_NAME_HARDENED="nthedao-ubuntu2404-arm64-hardened"
      ;;
    archlinux-arm64)
      # Arch aarch64 has no installer ISO, so STAGE 1 is a tarball bootstrap SCRIPT
      # (not a packer template). BOOTSTRAP_SCRIPT signals the STAGE=base branch to
      # run it instead of run_packer_build; the script produces the same base
      # qcow2 (+ .ova) paths the stage-2 resolver below expects. STAGE 2 is packer.
      BOOTSTRAP_SCRIPT="scripts/rootfs-bootstrap/bootstrap-base.sh"
      TEMPLATE_BASE=""                                            # n/a — bootstrap is a script
      VAR_FILE_BASE=""                                            # n/a — config in scripts/rootfs-bootstrap/base.env
      TEMPLATE_HARDENED="templates/nthedao/archlinux-arm64.pkr.hcl"
      VAR_FILE_HARDENED="variables/nthedao/archlinux-arm64.pkrvars.hcl"
      BASE_SLUG="archlinux-arm64"
      HARDENED_SRC_LABEL="archlinux-arm64"
      BUILD_NAME_BASE="archlinux-arm64-base"
      BUILD_NAME_HARDENED="archlinux-arm64"
      ;;
    *)
      cat <<EOF >&2
ERROR: arm64 two-stage builds are only wired for tenants: bosch, nthedao (got '${TENANT}').
To add an org: create templates/<org>/ + variables/<org>/ and add a case here.
EOF
      exit 4
      ;;
  esac
fi

# Renesas requires RHEL subscription credentials at build time.
if [[ "${TENANT}" == "renesas" ]]; then
  if [[ -z "${RHEL_USERNAME:-}" || -z "${RHEL_PASSWORD:-}" ]]; then
    echo "ERROR: RHEL_USERNAME and RHEL_PASSWORD must be exported for renesas builds"
    exit 3
  fi
fi

cd "${PACKER_DIR}"

# ----------------------------------------------------------------------------
# SSH keypair for the ansible provisioner's direct-connect mode (use_proxy=false).
#
# Generated once on first build, reused thereafter. Public half is injected into
# the VM via cloud-init user-data BEFORE ansible runs; private half is handed to
# ansible by packer. With both ends in place, the use_proxy=false direct SSH
# uses publickey auth (IdentitiesOnly=yes disables password fallback).
#
# Two-stage coupling: stage 1 bakes the pubkey into the base qcow2's
# authorized_keys; stage 2 SSHes in with the private key. If you regenerate the
# key, you must re-bake the base — the old base's authorized_keys won't accept
# new keys. (Fail-loud: the next stage 2 SSH attempt will hit "Permission
# denied (publickey)".)
# ----------------------------------------------------------------------------
KEYS_DIR="${PACKER_DIR}/keys"
SSH_KEY="${KEYS_DIR}/packer_ed25519"
if [[ ! -f "${SSH_KEY}" ]]; then
  echo "==> generating SSH keypair at ${SSH_KEY}"
  mkdir -p "${KEYS_DIR}"
  ssh-keygen -t ed25519 -C "packer-bake@$(hostname -s)" -f "${SSH_KEY}" -N '' -q
fi

# Render http/user-data from http/user-data.tmpl with the live SSH public key.
SSH_PUBKEY="$(cat "${SSH_KEY}.pub")"
awk -v key="${SSH_PUBKEY}" '{ gsub("@@SSH_PUBKEY@@", key); print }' \
  "${PACKER_DIR}/http/user-data.tmpl" > "${PACKER_DIR}/http/user-data"

mkdir -p "${PACKER_DIR}/output"

# ----------------------------------------------------------------------------
# Helper: invoke a packer build with logging + on-error=ask.
# (Used by the arm64 two-stage flow. amd64 flow inlines packer directly.)
#
# Args:
#   $1 = template path
#   $2 = var-file (in addition to common.pkrvars.hcl)
#   $3 = log filename suffix (e.g. "base-qemu", "hardened-virtualbox")
#   $4 = -only filter (may be empty — no filter means all sources in the build)
#        NB: -only is build-only, NOT applied to packer validate. Validate
#        always covers every source so a malformed sibling source fails fast
#        before we burn 10+ minutes on an OS install.
#   $5..$N = extra packer args (e.g. -var "base_image_path=...")
# ----------------------------------------------------------------------------
run_packer_build() {
  local template="$1"
  local var_file="$2"
  local log_suffix="$3"
  local only_filter="$4"
  shift 4
  local extra_args=("$@")

  echo "==> packer init  ${template}"
  packer init "${template}"

  echo "==> packer validate  template=${template}"
  # NB: ${arr[@]+"${arr[@]}"} is the bash 3.2-safe form for expanding an
  #     array under `set -u`. macOS ships bash 3.2 which treats a bare
  #     "${arr[@]}" against an empty array as "unbound variable". The
  #     alternate-expansion guard expands to nothing when the array is
  #     empty/unset, and to its elements otherwise. Required because
  #     Stage 1 calls pass no extra_args, and PROVIDER=all leaves
  #     only_args empty.
  packer validate \
    -var-file=variables/common.pkrvars.hcl \
    -var-file="${var_file}" \
    -var "image_version=${IMAGE_VERSION}" \
    -var "ssh_private_key_file=${SSH_KEY}" \
    ${extra_args[@]+"${extra_args[@]}"} \
    "${template}"

  local only_args=()
  if [[ -n "${only_filter}" ]]; then
    only_args=(-only="${only_filter}")
  fi

  echo "==> packer build  template=${template} image_version=${IMAGE_VERSION}${only_filter:+ only=${only_filter}}"
  PACKER_LOG=1 PACKER_LOG_PATH="${PACKER_DIR}/output/${TENANT}-${ARCH}-${log_suffix}-${IMAGE_VERSION}.log" \
    packer build \
      -on-error=ask \
      ${only_args[@]+"${only_args[@]}"} \
      -var-file=variables/common.pkrvars.hcl \
      -var-file="${var_file}" \
      -var "image_version=${IMAGE_VERSION}" \
      -var "ssh_private_key_file=${SSH_KEY}" \
      ${extra_args[@]+"${extra_args[@]}"} \
      "${template}"
}

# ----------------------------------------------------------------------------
# Two-stage path (arm64 org-folder templates) with per-provider dispatch (Path D).
# Reached for any arm64 tenant whose case above set TEMPLATE_HARDENED (bosch, nthedao, …).
#
# PROVIDER=qemu       → qcow2 only            (Proxmox prod fleet)
# PROVIDER=virtualbox → .ova + .box           (Apple Silicon vagrant)
# PROVIDER=all        → both, parallel        (CI / full-rebuild)
# ----------------------------------------------------------------------------
if [[ "${ARCH}" == "arm64" && -n "${TEMPLATE_HARDENED:-}" ]]; then
  case "${PROVIDER}" in
    qemu|virtualbox|all) ;;
    vmware)
      echo "ERROR: arm64 ${TENANT} + vmware is not wired (vmware-vmx stage-2 source not added)." >&2
      echo "       Use PROVIDER=qemu, virtualbox, or all." >&2
      exit 5
      ;;
    *)
      echo "ERROR: unreachable — provider validation passed but dispatch missed: ${PROVIDER}" >&2
      exit 5
      ;;
  esac

  # ----- Per-provider source label dispatch -----
  # STAGE1_ONLY / STAGE2_ONLY are the -only filters Packer uses to pick which
  # source(s) to bake. Empty string = no filter = bake all sources in the
  # template (which is what PROVIDER=all wants).
  case "${PROVIDER}" in
    qemu)
      STAGE1_ONLY="${BUILD_NAME_BASE}.qemu.${BASE_SLUG}"
      STAGE2_ONLY="${BUILD_NAME_HARDENED}.qemu.${HARDENED_SRC_LABEL}"
      ;;
    virtualbox)
      STAGE1_ONLY="${BUILD_NAME_BASE}.virtualbox-iso.${BASE_SLUG}"
      STAGE2_ONLY="${BUILD_NAME_HARDENED}.virtualbox-ovf.${HARDENED_SRC_LABEL}"
      ;;
    all)
      STAGE1_ONLY=""
      STAGE2_ONLY=""
      ;;
  esac

  # ---- STAGE 1: base ----
  if [[ "${STAGE}" == "base" || "${STAGE}" == "all" ]]; then
    echo ""
    echo "########################################################################"
    echo "# STAGE 1 — bake ${BASE_SLUG} base   version=${BASE_VERSION}   provider=${PROVIDER}"
    echo "########################################################################"
    if [[ -n "${BOOTSTRAP_SCRIPT:-}" ]]; then
      # Arch line: stage 1 is the ALARM tarball bootstrap SCRIPT (no installer ISO
      # to drive with packer). It writes the base qcow2 (+ .ova when PROVIDER
      # includes virtualbox) to the same output/base/<slug>{,-vbox}/ paths the
      # stage-2 resolver expects, AND maintains its own latest/ symlinks.
      BASE_VERSION="${BASE_VERSION}" PROVIDER="${PROVIDER}" \
        "${PACKER_DIR}/${BOOTSTRAP_SCRIPT}" "${BASE_VERSION}"
    else
      # Override IMAGE_VERSION just for the base bake so its output dir reflects
      # the BASE version (decoupled from the hardened-image's version).
      SAVED_IMAGE_VERSION="${IMAGE_VERSION}"
      IMAGE_VERSION="${BASE_VERSION}"
      run_packer_build "${TEMPLATE_BASE}" "${VAR_FILE_BASE}" "base-${PROVIDER}" "${STAGE1_ONLY}"
      IMAGE_VERSION="${SAVED_IMAGE_VERSION}"

      # Maintain `latest/` symlinks per provider tree so STAGE=hardened-only
      # invocations can resolve a recent base without explicit BASE_*_PATH.
      if [[ "${PROVIDER}" == "qemu" || "${PROVIDER}" == "all" ]]; then
        QEMU_DIR="${PACKER_DIR}/output/base/${BASE_SLUG}"
        rm -rf "${QEMU_DIR}/latest"
        ln -sfn "../${BASE_VERSION}" "${QEMU_DIR}/latest"
        ln -sfn "${BASE_SLUG}-base-${BASE_VERSION}.qcow2" \
          "${QEMU_DIR}/${BASE_VERSION}/${BASE_SLUG}-base-latest.qcow2"
      fi
      if [[ "${PROVIDER}" == "virtualbox" || "${PROVIDER}" == "all" ]]; then
        VBOX_DIR="${PACKER_DIR}/output/base/${BASE_SLUG}-vbox"
        rm -rf "${VBOX_DIR}/latest"
        ln -sfn "../${BASE_VERSION}" "${VBOX_DIR}/latest"
        ln -sfn "${BASE_SLUG}-base-${BASE_VERSION}.ova" \
          "${VBOX_DIR}/${BASE_VERSION}/${BASE_SLUG}-base-latest.ova"
      fi
    fi
  fi

  # ---- STAGE 2: hardened ----
  if [[ "${STAGE}" == "hardened" || "${STAGE}" == "all" ]]; then
    RESOLVED_BASE_QCOW2="UNUSED-this-build-skipped-qemu-source-via--only"
    RESOLVED_BASE_OVA="UNUSED-this-build-skipped-vbox-source-via--only"

    if [[ "${PROVIDER}" == "qemu" || "${PROVIDER}" == "all" ]]; then
      if [[ -n "${BASE_IMAGE_PATH:-}" ]]; then
        RESOLVED_BASE_QCOW2="${BASE_IMAGE_PATH}"
      else
        RESOLVED_BASE_QCOW2="output/base/${BASE_SLUG}/${BASE_VERSION}/${BASE_SLUG}-base-${BASE_VERSION}.qcow2"
      fi
      if [[ ! -f "${PACKER_DIR}/${RESOLVED_BASE_QCOW2}" && ! -f "${RESOLVED_BASE_QCOW2}" ]]; then
        cat <<EOF >&2
ERROR: stage 2 (qemu source) needs a base qcow2 but none was found at:
  ${RESOLVED_BASE_QCOW2}

Either:
  - run STAGE=base PROVIDER=qemu (or PROVIDER=all) first to bake one, OR
  - set BASE_IMAGE_PATH=<path-to-existing-qcow2> to use a known-good qcow2
    (e.g. an existing half-baked image you want to iterate ansible against).
EOF
        exit 6
      fi
    fi

    if [[ "${PROVIDER}" == "virtualbox" || "${PROVIDER}" == "all" ]]; then
      if [[ -n "${BASE_OVA_PATH:-}" ]]; then
        RESOLVED_BASE_OVA="${BASE_OVA_PATH}"
      else
        RESOLVED_BASE_OVA="output/base/${BASE_SLUG}-vbox/${BASE_VERSION}/${BASE_SLUG}-base-${BASE_VERSION}.ova"
      fi
      if [[ ! -f "${PACKER_DIR}/${RESOLVED_BASE_OVA}" && ! -f "${RESOLVED_BASE_OVA}" ]]; then
        cat <<EOF >&2
ERROR: stage 2 (virtualbox-ovf source) needs a base .ova but none was found at:
  ${RESOLVED_BASE_OVA}

Either:
  - run STAGE=base PROVIDER=virtualbox (or PROVIDER=all) first to bake one, OR
  - set BASE_OVA_PATH=<path-to-existing-ova> to use a known-good .ova.
EOF
        exit 6
      fi
    fi

    BASE2_EXTRA_ARGS=(
      -var "base_image_path=${RESOLVED_BASE_QCOW2}"
      -var "base_image_ova_path=${RESOLVED_BASE_OVA}"
    )

    echo ""
    echo "########################################################################"
    echo "# STAGE 2 — harden ${HARDENED_SRC_LABEL}   version=${IMAGE_VERSION}   provider=${PROVIDER}"
    if [[ "${PROVIDER}" == "qemu" || "${PROVIDER}" == "all" ]]; then
      echo "#         base qcow2 = ${RESOLVED_BASE_QCOW2}"
    fi
    if [[ "${PROVIDER}" == "virtualbox" || "${PROVIDER}" == "all" ]]; then
      echo "#         base ova   = ${RESOLVED_BASE_OVA}"
    fi
    echo "########################################################################"
    run_packer_build "${TEMPLATE_HARDENED}" "${VAR_FILE_HARDENED}" \
      "hardened-${PROVIDER}" "${STAGE2_ONLY}" "${BASE2_EXTRA_ARGS[@]}"
  fi

  echo ""
  case "${PROVIDER}" in
    qemu)
      echo "==> done. qcow2 + box in: ${PACKER_DIR}/output/${TENANT}/arm64/qemu/${IMAGE_VERSION}/"
      ;;
    virtualbox)
      echo "==> done. ova + box in: ${PACKER_DIR}/output/${TENANT}/arm64/virtualbox/${IMAGE_VERSION}/"
      ;;
    all)
      echo "==> done. artifacts:"
      echo "      qemu       (qcow2 + box): ${PACKER_DIR}/output/${TENANT}/arm64/qemu/${IMAGE_VERSION}/"
      echo "      virtualbox (ova   + box): ${PACKER_DIR}/output/${TENANT}/arm64/virtualbox/${IMAGE_VERSION}/"
      ;;
  esac
  exit 0
fi

# ----------------------------------------------------------------------------
# amd64 flow — new pkrvars composition path.
# Var-files layer: common → local → guest → tenant (later files override earlier)
# ----------------------------------------------------------------------------
echo "==> packer init  ${TEMPLATE}"
packer init "${TEMPLATE}"

echo "==> packer validate  tenant=${TENANT} guest=${GUEST} provider=${PROVIDER} version=${IMAGE_VERSION}"
packer validate \
  -var-file=variables/common.pkrvars.hcl \
  -var-file="${LOCAL_VAR_FILE}" \
  -var-file="${GUEST_VAR_FILE}" \
  -var-file="${TENANT_VAR_FILE}" \
  -var "image_version=${IMAGE_VERSION}" \
  -var "ssh_private_key_file=${SSH_KEY}" \
  "${TEMPLATE}"

echo "==> packer build  only=${ONLY_FILTER}"
PACKER_LOG=1 PACKER_LOG_PATH="${PACKER_DIR}/output/${TENANT}-${GUEST}-${PROVIDER}-${IMAGE_VERSION}.log" \
  packer build \
    -on-error=ask \
    -only="${ONLY_FILTER}" \
    -var-file=variables/common.pkrvars.hcl \
    -var-file="${LOCAL_VAR_FILE}" \
    -var-file="${GUEST_VAR_FILE}" \
    -var-file="${TENANT_VAR_FILE}" \
    -var "image_version=${IMAGE_VERSION}" \
    -var "ssh_private_key_file=${SSH_KEY}" \
    "${TEMPLATE}"

echo "==> done. artifacts in: ${PACKER_DIR}/output/${TENANT}/${GUEST}/<provider>/${IMAGE_VERSION}/"
