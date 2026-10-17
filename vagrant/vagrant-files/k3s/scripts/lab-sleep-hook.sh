#!/usr/bin/env bash
# lab-sleep-hook.sh — IN-33 safety net: flush the lab VMs right before macOS sleeps.
#
# WHY A SEPARATE THING FROM lab-guard.sh
#   lab-guard.sh holds idle-sleep off while the lab runs. It only helps if it is RUNNING.
#   If the VMs were started some other way (plain `vagrant up`, a reboot, an editor task),
#   nothing holds sleep off and the lab freezes mid-flight. This hook is the backstop for
#   that case, and for the sleeps caffeinate deliberately does NOT block: a lid close or an
#   explicit Apple-menu Sleep.
#
# 🔴 WHY THIS DOES NOT RUN `vagrant halt`
#   A sleep hook runs on a BUDGET — macOS allows roughly 30 seconds before it sleeps
#   regardless. A graceful halt of five VMs does not reliably finish in that window, and a
#   halt that is cut off MID-WRITE is precisely the unclean stop that destroyed etcd in
#   IN-31. A hook that tried to be thorough would cause the exact failure it exists to
#   prevent.
#
#   So this hook does the bounded, safe thing instead: `sync` on every node, flushing dirty
#   filesystem pages to disk so a frozen VM resumes from a consistent state. Measured on
#   2026-10-17: ssh round trip 246ms, `sync` 63ms per node. Five nodes finish in well under
#   a second, with a hard timeout per node on top.
#
#   It is a damage-limiter, not a replacement for lab-guard.sh. Keeping the lab AWAKE is
#   still the primary fix.
#
# INSTALL (see install-sleep-hook.sh):
#   brew install sleepwatcher && ln -s .../lab-sleep-hook.sh ~/.sleep

set -uo pipefail   # NOT -e: one unreachable node must not abort the others

LOG="${HOME}/Library/Logs/k3s-lab-sleep-hook.log"
LAB_DIR="${LAB_DIR:-$HOME/Projects/Infrastrutures/devops-tools/vagrant/vagrant-files/k3s}"
KEY="${LAB_SSH_KEY:-$HOME/Projects/Infrastrutures/devops-tools/packer/keys/packer_ed25519}"
SSH_USER="${LAB_SSH_USER:-packer}"
PER_NODE_TIMEOUT="${LAB_SYNC_TIMEOUT:-5}"

# Ports are read from a static map rather than `vagrant ssh-config`, which spawns Ruby and
# can take seconds — unaffordable inside a sleep budget. Verified 2026-10-17.
NODE_PORTS="k3s-lb:50010 k3s-server-1:50011 k3s-agent-1:50021 k3s-agent-2:50022 k3s-agent-3:50023"

log() { printf "%s  %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$*" >> "$LOG" 2>/dev/null || true; }

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Nothing running? Say so and leave immediately — no cost on a normal sleep.
if ! pgrep -f "qemu-system" >/dev/null 2>&1; then
  log "sleep: no qemu VMs running, nothing to flush"
  exit 0
fi

# If lab-guard.sh is holding sleep off, this sleep is a deliberate one (lid close / menu),
# which is worth recording: it tells you later why the lab froze despite the guard.
if [ -f "${TMPDIR:-/tmp}/k3s-lab-guard.pid" ]; then
  log "sleep: lab-guard is running, so this is a DELIBERATE sleep (lid/menu), not idle"
else
  log "sleep: lab-guard NOT running — this is the unguarded case this hook exists for"
fi

START=$(date +%s)
OK=0; FAIL=0

for entry in $NODE_PORTS; do
  name="${entry%%:*}"
  port="${entry##*:}"
  # -n stops ssh consuming stdin; BatchMode never prompts; ConnectTimeout bounds a dead node.
  if ssh -n -i "$KEY" \
         -o StrictHostKeyChecking=no \
         -o UserKnownHostsFile=/dev/null \
         -o LogLevel=ERROR \
         -o BatchMode=yes \
         -o ConnectTimeout="$PER_NODE_TIMEOUT" \
         -p "$port" "${SSH_USER}@127.0.0.1" "sync" >/dev/null 2>&1; then
    OK=$((OK+1))
  else
    FAIL=$((FAIL+1))
    log "sleep:   $name (port $port) did not flush — unreachable or already down"
  fi
done

log "sleep: flushed $OK/$((OK+FAIL)) nodes in $(( $(date +%s) - START ))s"
exit 0
