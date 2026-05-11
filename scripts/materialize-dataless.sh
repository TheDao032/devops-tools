#!/usr/bin/env bash
# Force-materialize iCloud-evicted ("dataless") files in this repo.
#
# WHY: macOS' "Optimize Mac Storage" can evict file *contents* while keeping
# the metadata. `ls -lO <file>` shows "dataless". Reading the file triggers
# an on-demand cloud download — fine for `cat`, but breaks tools that read
# many small files quickly (Vagrant's net-ssh key loader, Ansible playbook
# loader) because the download blocks for seconds and may time out under
# Errno::ECANCELED.
#
# This script reads every dataless file in the relevant subtrees in parallel,
# forcing materialization. Re-run any time before a vagrant up / packer build /
# ansible deploy if files have been re-evicted.
#
# Usage:
#   ./scripts/materialize-dataless.sh [-j N]    # N = parallel readers, default 16
#
# Permanent fix is to disable iCloud sync for this directory — see the README.

set -euo pipefail

PARALLEL="${PARALLEL:-16}"
while getopts ":j:" opt; do
  case $opt in
    j) PARALLEL="$OPTARG" ;;
    *) echo "usage: $0 [-j N]" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SUBTREES=(
  ansible vagrant packer/keys packer/scripts packer/templates
  packer/http packer/playbooks packer/variables
  deployments scripts services dockerfiles docker-composes kubernetes-templates
)

list_dataless() {
  find "${SUBTREES[@]}" \
       -type f \
       -not -path '*/__pycache__/*' \
       -not -name '*.pyc' \
       -not -path '*/output/*' \
       -not -path '*/.vagrant/*' \
       2>/dev/null \
    | xargs ls -lO 2>/dev/null \
    | awk '/dataless/ {for(i=10;i<=NF;i++) printf "%s%s", (i>10?" ":""), $i; print ""}'
}

dataless=$(list_dataless)
count=$(printf '%s\n' "$dataless" | grep -c . || true)
if [[ "$count" -eq 0 ]]; then
  echo "no dataless files in repo subtrees — nothing to do."
  exit 0
fi

echo "found $count dataless files; materializing $PARALLEL in parallel ..."
printf '%s\0' "$dataless" \
  | xargs -0 -P "$PARALLEL" -I {} sh -c 'cat "$1" > /dev/null 2>&1' _ {}

remaining=$(list_dataless | grep -c . || true)
echo "done. remaining dataless: $remaining"
exit 0
