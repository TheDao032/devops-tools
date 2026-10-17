#!/usr/bin/env bash
# lab-guard.sh — IN-33: stop unattended macOS sleep from freezing the k3s lab.
#
# WHY THIS EXISTS
#   Host sleep is the single most expensive failure mode of this lab. Measured on
#   2026-10-17: the Mac slept three times on battery (20:14 for 998s, 20:30 for 760s,
#   20:43 for 784s) while the VMs were running. Earlier incidents from the same cause:
#     - a 250-minute hole in Prometheus scrape coverage (zero SAMPLES, not zero values)
#     - ~53 containers restarting simultaneously across every namespace
#     - Vault re-sealing, which stops ExternalSecrets syncing
#     - IN-31: an unclean stop corrupted etcd irreparably
#
#   THE DIAGNOSTIC TELL: every pod's restart count incrementing together while the nodes
#   stay Ready for days means THE HOST SLEPT. It is not a Kubernetes fault and no amount
#   of in-cluster investigation will explain it. Check `pmset -g log` FIRST.
#
# WHY caffeinate AND NOT pmset
#   `pmset` changes are persistent and punish every other use of the machine. caffeinate
#   is scoped to the lifetime of THIS process: kill it, close the terminal, or let the VMs
#   stop, and macOS returns to normal sleep behaviour with nothing left behind. The same
#   pattern already runs on this Mac for two long-lived crypto-bot processes.
#
#   AC power is already `sleep 0`; every measured sleep was ON BATTERY. This guard is
#   therefore mainly a battery-session protection — which is exactly the unattended case.
#
# USAGE
#   ./scripts/lab-guard.sh            # run in the foreground, Ctrl-C to release
#   ./scripts/lab-guard.sh --daemon   # detach; it exits on its own when the VMs stop
#   ./scripts/lab-guard.sh --status   # is a guard currently holding sleep off?
#   ./scripts/lab-guard.sh --stop     # release the guard now
#
# It does NOT start or stop the VMs. It only holds sleep off while they are already up.

set -euo pipefail

PIDFILE="${TMPDIR:-/tmp}/k3s-lab-guard.pid"
POLL_SECONDS="${LAB_GUARD_POLL:-60}"

# A running lab = at least one qemu process belonging to the vagrant VMs.
# Counted with pgrep rather than `vagrant status`, which is slow and needs the right cwd.
vms_running() {
  pgrep -f "qemu-system" >/dev/null 2>&1
}

guard_pid() {
  [ -f "$PIDFILE" ] || return 1
  local pid; pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  printf "%s" "$pid"
}

case "${1:-}" in
  --status)
    if pid="$(guard_pid)"; then
      echo "lab-guard: HOLDING sleep off (pid $pid)"
      pgrep -lf "caffeinate -i -w $pid" 2>/dev/null || true
    else
      echo "lab-guard: not running"
    fi
    vms_running && echo "VMs: running" || echo "VMs: not running"
    exit 0
    ;;
  --stop)
    if pid="$(guard_pid)"; then
      kill "$pid" 2>/dev/null || true
      # 🔴 VERIFY THE KILL, do not assume it. The first version removed the PID file
      # immediately and printed "released" — but the signal raced the guard's own EXIT
      # trap, so the process survived WITHOUT its pid file: --status then reported
      # "not running" while caffeinate was still holding sleep off. A false green on
      # precisely the guarantee this script exists to make. Measured 2026-10-17.
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.3
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
        sleep 0.3
      fi
      if kill -0 "$pid" 2>/dev/null; then
        echo "lab-guard: FAILED to stop pid $pid — sleep may still be held off" >&2
        echo "lab-guard: check with: pmset -g assertions | grep caffeinate" >&2
        exit 1
      fi
      # Only now is the pid file stale; the trap could not run under SIGKILL.
      rm -f "$PIDFILE"
      echo "lab-guard: released (pid $pid stopped)"
    else
      echo "lab-guard: not running"
    fi
    exit 0
    ;;
esac

if pid="$(guard_pid)"; then
  echo "lab-guard: already running (pid $pid) — nothing to do"
  exit 0
fi

if ! vms_running; then
  echo "lab-guard: no qemu VMs running. Start the lab first (vagrant up), then run this." >&2
  exit 1
fi

run_guard() {
  echo $$ > "$PIDFILE"
  # Release the PID file however we exit, including on Ctrl-C.
  trap 'rm -f "$PIDFILE"' EXIT INT TERM

  # -i prevents IDLE sleep only. A deliberate lid-close or Apple-menu Sleep still works,
  # so this cannot strand the machine awake in a bag. -w ties caffeinate to THIS pid, so
  # it dies with us and leaves no orphan holding sleep off.
  caffeinate -i -w $$ &
  local caf=$!

  echo "lab-guard: holding idle sleep off while the lab runs (guard pid $$, caffeinate pid $caf)"
  echo "lab-guard: polling every ${POLL_SECONDS}s; exits automatically when the VMs stop"

  # The sleep runs in the BACKGROUND and is waited on, so a TERM/INT reaches this shell
  # immediately instead of being absorbed by a foreground `sleep`. Without this, --stop
  # had to wait a full poll interval (or escalate to SIGKILL) before the guard noticed.
  STOPPING=0
  trap 'STOPPING=1' INT TERM
  while [ "$STOPPING" -eq 0 ] && vms_running; do
    sleep "$POLL_SECONDS" &
    wait $! 2>/dev/null || true
  done

  echo "lab-guard: VMs are gone — releasing sleep guard"
  kill "$caf" 2>/dev/null || true
}

if [ "${1:-}" = "--daemon" ]; then
  # nohup so it survives the terminal closing; the VM poll still ends it cleanly.
  nohup "$0" >/dev/null 2>&1 &
  sleep 1
  if pid="$(guard_pid)"; then
    echo "lab-guard: started in the background (pid $pid). Stop with: $0 --stop"
  else
    echo "lab-guard: failed to start in the background" >&2; exit 1
  fi
  exit 0
fi

run_guard
