#!/usr/bin/env bash
# install-sleep-hook.sh — IN-33: wire lab-sleep-hook.sh to macOS sleep via sleepwatcher.
#
# WHY sleepwatcher AND NOT launchd
#   launchd has NO pre-sleep trigger. Verified against `man launchd.plist` on 2026-10-17:
#   its only sleep-related behaviour is coalescing MISSED interval firings on WAKE. There
#   is no "run this before sleeping" key, so the existing local.k3s.vmnet-route.plist
#   pattern cannot express this. sleepwatcher is the standard tool for the job.
#
# WHAT IT INSTALLS
#   ~/.sleep  -> a symlink to lab-sleep-hook.sh (sleepwatcher runs it before sleep)
#   and starts sleepwatcher as a brew user service.
#
# REVERSIBLE: ./install-sleep-hook.sh --uninstall removes the symlink and stops the
# service. Nothing persistent is changed in system power settings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/lab-sleep-hook.sh"
SLEEP_LINK="${HOME}/.sleep"

if [ "${1:-}" = "--uninstall" ]; then
  if [ -L "$SLEEP_LINK" ]; then rm -f "$SLEEP_LINK"; echo "removed $SLEEP_LINK"; else echo "no $SLEEP_LINK symlink"; fi
  brew services stop sleepwatcher 2>/dev/null || true
  echo "sleepwatcher stopped. Nothing else was changed."
  exit 0
fi

if [ "${1:-}" = "--status" ]; then
  if [ -L "$SLEEP_LINK" ]; then echo "hook: $SLEEP_LINK -> $(readlink "$SLEEP_LINK")"; else echo "hook: NOT installed"; fi
  brew services list 2>/dev/null | grep -i sleepwatcher || echo "sleepwatcher: not running"
  echo "recent hook activity:"
  tail -5 "${HOME}/Library/Logs/k3s-lab-sleep-hook.log" 2>/dev/null | sed "s/^/  /" || echo "  (no log yet)"
  exit 0
fi

[ -x "$HOOK" ] || { echo "hook not found or not executable: $HOOK" >&2; exit 1; }

# 🔴 REFUSE to clobber an existing ~/.sleep that is not ours. Overwriting someone else's
# sleep hook to install our own would be a silent, hard-to-find breakage.
if [ -e "$SLEEP_LINK" ] && [ "$(readlink "$SLEEP_LINK" 2>/dev/null)" != "$HOOK" ]; then
  echo "ERROR: $SLEEP_LINK already exists and does not point at our hook:" >&2
  ls -l "$SLEEP_LINK" >&2
  echo "Refusing to overwrite it. Merge the two by hand, or remove it first." >&2
  exit 1
fi

if ! command -v sleepwatcher >/dev/null 2>&1; then
  echo "sleepwatcher is not installed. Installing via brew..."
  brew install sleepwatcher
fi

ln -sfn "$HOOK" "$SLEEP_LINK"
echo "installed: $SLEEP_LINK -> $HOOK"

brew services restart sleepwatcher
echo
echo "Verify with:   $0 --status"
echo "Test without sleeping:   $HOOK && tail -3 ~/Library/Logs/k3s-lab-sleep-hook.log"
echo "Remove with:   $0 --uninstall"
