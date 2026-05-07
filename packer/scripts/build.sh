#!/usr/bin/env bash
# Wrapper for tenant-aware Packer builds.
#
# Usage:
#   ./scripts/build.sh <tenant> <provider> [image_version]
#
# Environment variables:
#   ARCH             = amd64 (default) | arm64
#   STAGE            = base | hardened | all (default: all) — arm64 only for now
#   BASE_VERSION     = version of the base image (arm64 STAGE=base or =all)
#                       defaults to $(date +%F). Goes into output/base/.../<BASE_VERSION>/
#   BASE_IMAGE_PATH  = override path to base qcow2 (used by qemu source)
#                       defaults to output/base/ubuntu2204-arm64/${BASE_VERSION}/
#                                    ubuntu2204-arm64-base-${BASE_VERSION}.qcow2
#   BASE_OVA_PATH    = override path to base .ova   (used by virtualbox source)
#                       defaults to output/base/ubuntu2204-arm64-vbox/${BASE_VERSION}/
#                                    ubuntu2204-arm64-base-${BASE_VERSION}.ova
#   RHEL_USERNAME    = required for renesas (subscription-manager)
#   RHEL_PASSWORD    = required for renesas (subscription-manager)
#
# Examples:
#   ./scripts/build.sh renesas qemu                                # x86 monolith
#   ARCH=arm64 ./scripts/build.sh bosch qemu                       # arm64 qemu, both stages
#   ARCH=arm64 ./scripts/build.sh bosch virtualbox                 # arm64 vbox, both stages
#   ARCH=arm64 ./scripts/build.sh bosch all                        # arm64 BOTH providers
#   ARCH=arm64 STAGE=base     ./scripts/build.sh bosch qemu        # just bake qemu base
#   ARCH=arm64 STAGE=hardened ./scripts/build.sh bosch virtualbox  # just harden vbox
#
#   # Iterate ansible against an existing qcow2 (no re-install):
#   ARCH=arm64 STAGE=hardened \
#     BASE_IMAGE_PATH=output/base/ubuntu2204-arm64/2026-05-03/ubuntu2204-arm64-base-2026-05-03.qcow2 \
#     ./scripts/build.sh bosch qemu
#
# Tenants:   renesas | bosch
# Providers: virtualbox | qemu | vmware | all
# Arches:    amd64 (default) | arm64
#
# Two-stage build (arm64 + bosch):
#   stage 1 = "base"     — clean Ubuntu 22.04 ARM64 OS install, no ansible
#   stage 2 = "hardened" — boots stage 1's image, runs the compliance role
#   stage   = "all"      — both serially (default)
#   provider dispatch (Path D):
#     qemu       → qcow2 only (Proxmox prod fleet deliverable)
#     virtualbox → ova + .box (Apple Silicon vagrant deliverable)
#     all        → both, parallel under one packer build
#
# x86 (renesas, bosch-amd64) still uses the legacy monolith template — STAGE
# is ignored there. Migration to two-stage is tracked separately.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TENANT="${1:-}"
PROVIDER="${2:-}"
IMAGE_VERSION="${3:-$(date +%F).1}"
ARCH="${ARCH:-amd64}"
STAGE="${STAGE:-all}"
BASE_VERSION="${BASE_VERSION:-$(date +%F)}"

usage() {
  cat <<EOF
Usage: $0 <tenant> <provider> [image_version]

  tenant   = renesas | bosch
  provider = virtualbox | qemu | vmware | all
  image_version (optional) — defaults to YYYY-MM-DD.1

Env vars consumed:
  ARCH                          = amd64 (default) | arm64
  STAGE                         = base | hardened | all (default; arm64 only)
  BASE_VERSION                  = base image version (default: \$(date +%F))
  BASE_IMAGE_PATH               = override base qcow2 path (qemu source, STAGE=hardened)
  BASE_OVA_PATH                 = override base .ova path  (vbox source,  STAGE=hardened)
  RHEL_USERNAME / RHEL_PASSWORD = required for renesas (subscription-manager)
EOF
  exit 2
}

[[ -z "${TENANT}" || -z "${PROVIDER}" ]] && usage

case "${TENANT}" in
  renesas|bosch) ;;
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

# Two-stage is arm64-only for now. STAGE is silently ignored on amd64.
if [[ "${ARCH}" == "amd64" && "${STAGE}" != "all" ]]; then
  echo "WARN: STAGE=${STAGE} ignored — two-stage build is arm64-only currently. Proceeding with monolith bake."
fi

# Tenant + arch → template + var-file + build name + source labels.
case "${TENANT}-${ARCH}" in
  renesas-amd64)
    TEMPLATE="templates/renesas-rhel9-hardened.pkr.hcl"
    VAR_FILE="variables/renesas.pkrvars.hcl"
    BUILD_NAME="renesas-rhel9-hardened"
    SRC_LEAF="renesas-rhel9"
    ;;
  renesas-arm64)
    cat <<EOF >&2
ERROR: renesas-arm64 is not supported.
RHEL FIPS 140-3 validation is x86_64-only. Bake renesas images on x86 hosts only.
See ADR 2026-05-02-multi-arch-image-baking for the rationale and follow-ups.
EOF
    exit 4
    ;;
  bosch-amd64)
    TEMPLATE="templates/bosch-ubuntu2204-hardened.pkr.hcl"
    VAR_FILE="variables/bosch.pkrvars.hcl"
    BUILD_NAME="bosch-ubuntu2204-hardened"
    SRC_LEAF="bosch-ubuntu2204"
    ;;
  bosch-arm64)
    # Two-stage with provider dispatch (Path D). Per-provider source labels are
    # computed below in the arm64 dispatch block.
    TEMPLATE_BASE="templates/ubuntu2204-arm64-base.pkr.hcl"
    TEMPLATE_HARDENED="templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl"
    VAR_FILE_BASE="variables/ubuntu-arm64-base.pkrvars.hcl"
    VAR_FILE_HARDENED="variables/bosch-arm64.pkrvars.hcl"
    BUILD_NAME_BASE="ubuntu2204-arm64-base"
    BUILD_NAME_HARDENED="bosch-ubuntu2204-arm64-hardened"
    ;;
esac

# x86 monolith path: -only filter selects provider source.
if [[ "${ARCH}" == "amd64" ]]; then
  SRC_VBOX="${BUILD_NAME}.virtualbox-iso.${SRC_LEAF}"
  SRC_QEMU="${BUILD_NAME}.qemu.${SRC_LEAF}"
  SRC_VMW="${BUILD_NAME}.vmware-iso.${SRC_LEAF}"
  case "${PROVIDER}" in
    virtualbox) ONLY_FILTER="${SRC_VBOX}" ;;
    qemu)       ONLY_FILTER="${SRC_QEMU}" ;;
    vmware)     ONLY_FILTER="${SRC_VMW}"  ;;
    all)        ONLY_FILTER="${SRC_VBOX},${SRC_QEMU},${SRC_VMW}" ;;
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
# Two-stage path (arm64 + bosch) with per-provider dispatch (Path D).
#
# PROVIDER=qemu       → qcow2 only            (Proxmox prod fleet)
# PROVIDER=virtualbox → .ova + .box           (Apple Silicon vagrant)
# PROVIDER=all        → both, parallel        (CI / full-rebuild)
# ----------------------------------------------------------------------------
if [[ "${ARCH}" == "arm64" && "${TENANT}" == "bosch" ]]; then
  case "${PROVIDER}" in
    qemu|virtualbox|all) ;;
    vmware)
      echo "ERROR: arm64 bosch + vmware is not wired (vmware-vmx stage-2 source not added)." >&2
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
      STAGE1_ONLY="${BUILD_NAME_BASE}.qemu.ubuntu2204-arm64"
      STAGE2_ONLY="${BUILD_NAME_HARDENED}.qemu.bosch-ubuntu2204-arm64"
      ;;
    virtualbox)
      STAGE1_ONLY="${BUILD_NAME_BASE}.virtualbox-iso.ubuntu2204-arm64"
      STAGE2_ONLY="${BUILD_NAME_HARDENED}.virtualbox-ovf.bosch-ubuntu2204-arm64"
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
    echo "# STAGE 1 — bake Ubuntu 22.04 ARM64 base   version=${BASE_VERSION}   provider=${PROVIDER}"
    echo "########################################################################"
    # Override IMAGE_VERSION just for the base bake so its output dir reflects
    # the BASE version (decoupled from the hardened-image's version).
    SAVED_IMAGE_VERSION="${IMAGE_VERSION}"
    IMAGE_VERSION="${BASE_VERSION}"
    run_packer_build "${TEMPLATE_BASE}" "${VAR_FILE_BASE}" "base-${PROVIDER}" "${STAGE1_ONLY}"
    IMAGE_VERSION="${SAVED_IMAGE_VERSION}"

    # Maintain `latest/` symlinks per provider tree so STAGE=hardened-only
    # invocations can resolve a recent base without explicit BASE_*_PATH.
    # Each provider gets its own subdir per the stage 1 template's locals
    # (qemu in ubuntu2204-arm64/, vbox in ubuntu2204-arm64-vbox/).
    if [[ "${PROVIDER}" == "qemu" || "${PROVIDER}" == "all" ]]; then
      QEMU_DIR="${PACKER_DIR}/output/base/ubuntu2204-arm64"
      rm -rf "${QEMU_DIR}/latest"
      ln -sfn "../${BASE_VERSION}" "${QEMU_DIR}/latest"
      ln -sfn "ubuntu2204-arm64-base-${BASE_VERSION}.qcow2" \
        "${QEMU_DIR}/${BASE_VERSION}/ubuntu2204-arm64-base-latest.qcow2"
    fi
    if [[ "${PROVIDER}" == "virtualbox" || "${PROVIDER}" == "all" ]]; then
      VBOX_DIR="${PACKER_DIR}/output/base/ubuntu2204-arm64-vbox"
      rm -rf "${VBOX_DIR}/latest"
      ln -sfn "../${BASE_VERSION}" "${VBOX_DIR}/latest"
      ln -sfn "ubuntu2204-arm64-base-${BASE_VERSION}.ova" \
        "${VBOX_DIR}/${BASE_VERSION}/ubuntu2204-arm64-base-latest.ova"
    fi
  fi

  # ---- STAGE 2: hardened ----
  if [[ "${STAGE}" == "hardened" || "${STAGE}" == "all" ]]; then
    # Resolve per-provider base image paths. We compute the path for each
    # provider that's IN SCOPE for this PROVIDER value; we leave the others
    # empty so the corresponding template var (which now defaults to "")
    # stays unset and the unused source isn't second-guessed.
    # We ALWAYS pass both -var flags (even for single-provider builds) because
    # packer validate runs against EVERY source in the template — not just the
    # ones -only would build. The unused source needs a non-empty source_path
    # / iso_url at validation time or validate fails. We pass a sentinel
    # placeholder for the unused provider; -only excludes that source at
    # build time so the placeholder never reaches a runtime file-existence
    # check. (The runtime file check below only runs for the ACTIVE provider.)
    RESOLVED_BASE_QCOW2="UNUSED-this-build-skipped-qemu-source-via--only"
    RESOLVED_BASE_OVA="UNUSED-this-build-skipped-vbox-source-via--only"

    if [[ "${PROVIDER}" == "qemu" || "${PROVIDER}" == "all" ]]; then
      if [[ -n "${BASE_IMAGE_PATH:-}" ]]; then
        RESOLVED_BASE_QCOW2="${BASE_IMAGE_PATH}"
      else
        RESOLVED_BASE_QCOW2="output/base/ubuntu2204-arm64/${BASE_VERSION}/ubuntu2204-arm64-base-${BASE_VERSION}.qcow2"
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
        RESOLVED_BASE_OVA="output/base/ubuntu2204-arm64-vbox/${BASE_VERSION}/ubuntu2204-arm64-base-${BASE_VERSION}.ova"
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
    echo "# STAGE 2 — harden bosch-ubuntu2204-arm64   version=${IMAGE_VERSION}   provider=${PROVIDER}"
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
# Legacy monolith path (x86, or any non-bosch-arm64 combo).
# ----------------------------------------------------------------------------
echo "==> packer init  ${TEMPLATE}"
packer init "${TEMPLATE}"

echo "==> packer validate  tenant=${TENANT} arch=${ARCH} provider=${PROVIDER} version=${IMAGE_VERSION}"
packer validate \
  -var-file=variables/common.pkrvars.hcl \
  -var-file="${VAR_FILE}" \
  -var "image_version=${IMAGE_VERSION}" \
  -var "ssh_private_key_file=${SSH_KEY}" \
  "${TEMPLATE}"

echo "==> packer build  only=${ONLY_FILTER}"
PACKER_LOG=1 PACKER_LOG_PATH="${PACKER_DIR}/output/${TENANT}-${ARCH}-${PROVIDER}-${IMAGE_VERSION}.log" \
  packer build \
    -on-error=ask \
    -only="${ONLY_FILTER}" \
    -var-file=variables/common.pkrvars.hcl \
    -var-file="${VAR_FILE}" \
    -var "image_version=${IMAGE_VERSION}" \
    -var "ssh_private_key_file=${SSH_KEY}" \
    "${TEMPLATE}"

echo "==> done. artifacts in: ${PACKER_DIR}/output/${TENANT}/<provider>/${IMAGE_VERSION}/"
