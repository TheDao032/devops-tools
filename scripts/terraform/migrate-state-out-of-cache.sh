#!/usr/bin/env bash
# scripts/terraform/migrate-state-out-of-cache.sh — move Terraform state out of .terragrunt-cache
# into a stable tree outside the repository (IN-12).
#
# WHY THIS EXISTS
#   State used to live at <unit>/.terragrunt-cache/<hash>/.../terraform.tfstate. That directory is a
#   CACHE: terragrunt regenerates it, tooling cleans it, and every instinct says it is safe to
#   delete. Deleting one does not lose the resources — it ORPHANS them. Vault policies, Keycloak
#   realms and clients, Postgres databases, and Cloudflare tunnels/DNS/Access apps that live outside
#   the cluster entirely. The next apply then tries to CREATE them again, which for a Cloudflare
#   tunnel or a Keycloak client is a duplicate or a hard failure, not a no-op.
#
# WHAT IT DOES
#   COPIES (never moves) each unit's newest cache-resident state to
#       $TF_STATE_ROOT/<unit path relative to repo root>/terraform.tfstate
#   which is exactly where root.hcl's generated backend block will look for it. Because the file is
#   already in place when terraform next inits, there is no migration prompt and no chance of a
#   half-moved state.
#
# SAFETY
#   * dry-run by default; --apply is required to write anything
#   * takes a timestamped tarball backup of every source state file before copying
#   * NEVER deletes a source file, and never overwrites an existing target
#   * reports units with several cache candidates instead of guessing silently
#
# Usage:
#   scripts/terraform/migrate-state-out-of-cache.sh [--repo <path>] [--apply]

set -euo pipefail

REPO="${HOME}/Projects/Infrastrutures/devops-terragrunt-environments"
APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,30p' "$0" >&2; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -d "${REPO}" ]] || { echo "repo not found: ${REPO}" >&2; exit 2; }
STATE_ROOT="${TF_STATE_ROOT:-${HOME}/.terragrunt-state/$(basename "${REPO}")}"

log()  { printf '  %s\n' "$*"; }
head_() { printf '\n=== %s ===\n' "$*"; }

head_ "Configuration"
log "repo        ${REPO}"
log "state root  ${STATE_ROOT}"
log "mode        $([[ ${APPLY} -eq 1 ]] && echo 'APPLY — will write' || echo 'DRY RUN — nothing will be written')"

# ── collect one source state per unit ──────────────────────────────────────────────────────────
# A unit is a directory containing terragrunt.hcl. Its state may sit several levels down inside
# .terragrunt-cache, under a path that mirrors the MODULE, not the unit — so resolve per unit
# rather than trying to parse the cache layout.
head_ "Scanning units"
# while-read, not `mapfile`: mapfile/readarray are bash 4+, and macOS ships bash 3.2 as /bin/bash.
# `env bash` happens to find Homebrew's bash 5 on this machine, but a script that edits STATE should
# not depend on PATH ordering — this form works on both.
UNITS=()
while IFS= read -r d; do UNITS+=("$d"); done < <(
  find "${REPO}" -name terragrunt.hcl -not -path "*/.terragrunt-cache/*" -print0 2>/dev/null \
    | xargs -0 -n1 dirname | sort -u)
log "${#UNITS[@]} units with a terragrunt.hcl"

TOTAL=0; WITH_STATE=0; MULTI=0; SKIPPED=0; COPIED=0
declare -a PLAN=()

for unit in "${UNITS[@]}"; do
  # `|| true` — grep/find finding nothing is a normal outcome, and under `set -o pipefail` an empty
  # result would otherwise abort the whole script silently.
  found=()
  while IFS= read -r f; do found+=("$f"); done < <(
    find "${unit}/.terragrunt-cache" -name terraform.tfstate -type f 2>/dev/null | sort || true)
  (( ${#found[@]} == 0 )) && continue   # nothing cached for this unit
  WITH_STATE=$((WITH_STATE + 1))

  # newest wins; report when there was a choice so a human can check rather than trust the heuristic
  src="$(ls -t ${found[@]+"${found[@]}"} 2>/dev/null | head -1)"
  if (( ${#found[@]} > 1 )); then
    MULTI=$((MULTI + 1))
    log "⚠ ${unit#"${REPO}"/}: ${#found[@]} cache candidates — taking the most recent"
  fi

  n=$(/usr/bin/python3 -c "import json;print(len(json.load(open('${src}')).get('resources',[])))" 2>/dev/null || echo 0)
  [[ "${n}" -eq 0 ]] && continue          # empty state carries nothing worth moving
  TOTAL=$((TOTAL + n))

  rel="${unit#"${REPO}"/}"
  dst="${STATE_ROOT}/${rel}/terraform.tfstate"
  if [[ -f "${dst}" ]]; then
    log "· ${rel}: target already exists — SKIPPED (never overwrite state)"
    SKIPPED=$((SKIPPED + 1)); continue
  fi
  PLAN+=("${src}|${dst}|${rel}|${n}")
done

head_ "Plan"
log "${WITH_STATE} units hold state · ${TOTAL} resources · ${#PLAN[@]} to copy · ${SKIPPED} skipped · ${MULTI} with multiple candidates"
for row in ${PLAN[@]+"${PLAN[@]}"}; do
  IFS='|' read -r _ _ rel n <<<"${row}"
  printf '  %4s resources  %s\n' "${n}" "${rel}"
done

if [[ ${APPLY} -eq 0 ]]; then
  head_ "Dry run"
  log "Nothing written. Re-run with --apply to perform the copy."
  exit 0
fi

# ── backup first, unconditionally ──────────────────────────────────────────────────────────────
head_ "Backing up every source state file"
BACKUP="${HOME}/tf-state-backup-$(/bin/date +%Y%m%d-%H%M%S).tar.gz"
tmp="$(mktemp -d)"
for row in ${PLAN[@]+"${PLAN[@]}"}; do
  IFS='|' read -r src _ rel _ <<<"${row}"
  mkdir -p "${tmp}/${rel}"
  cp "${src}" "${tmp}/${rel}/terraform.tfstate"
done
tar -czf "${BACKUP}" -C "${tmp}" . && rm -rf "${tmp}"
log "backup: ${BACKUP}"
log "⚠ this contains SECRETS — it is state. Keep it off shared storage and delete it once verified."

head_ "Copying"
for row in ${PLAN[@]+"${PLAN[@]}"}; do
  IFS='|' read -r src dst rel n <<<"${row}"
  mkdir -p "$(dirname "${dst}")"
  cp "${src}" "${dst}"
  chmod 600 "${dst}"
  COPIED=$((COPIED + 1))
  printf '  %4s resources  %s\n' "${n}" "${rel}"
done

head_ "Result"
log "copied ${COPIED} state files to ${STATE_ROOT}"
log "sources left in place — nothing was deleted"
cat >&2 <<'ENDNOTE'

  NEXT — verify BEFORE clearing any cache:

    cd <a unit>
    terragrunt init      # must NOT offer to migrate; the state is already at the backend path
    terragrunt plan      # must report NO CHANGES

  A plan proposing to CREATE everything means that unit's state did not come across. Do not apply
  it — that would duplicate live resources. Restore from the backup tarball and investigate.
ENDNOTE
