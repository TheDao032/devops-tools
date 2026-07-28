#!/usr/bin/env bash
# Pull the cluster kubeconfig from the bootstrap k3s server and rewrite it to
# point at the HAProxy VIP, so kubectl on the host talks to the load-balanced API.
#
# Requires the lab to be up (./up.sh, or deployments/vagrant/k3s/up.sh).
# Runs from anywhere when VAGRANT_CWD is set (see .envrc); otherwise it cd's into
# its own dir so `vagrant ssh` finds the scenario.
#
# Usage: ./fetch-kubeconfig.sh [LB_IP]        (default LB_IP: 192.168.105.10)
set -euo pipefail
cd "$(dirname "$0")"

LB_IP="${1:-192.168.105.10}"
NODE="${K3S_KUBECONFIG_NODE:-k3s-server-1}"   # bootstrap control-plane node
OUT="kubeconfig"

# Fail early with a clear message if the control-plane VM isn't running — this is
# the #1 reason a fetch "does nothing": the old script hid the SSH error with
# 2>/dev/null and wrote an empty file while still claiming success.
if ! vagrant status "$NODE" 2>/dev/null | grep -qE "^${NODE}[[:space:]]+running"; then
  echo "ERROR: '${NODE}' is not running — bring the lab up first:" >&2
  echo "         ./up.sh            (or deployments/vagrant/k3s/up.sh)" >&2
  echo "       current status:" >&2
  vagrant status "$NODE" 2>&1 | sed 's/^/         /' >&2 || true
  exit 1
fi

echo "Fetching kubeconfig from ${NODE}..."
raw="$(mktemp)"; err="$(mktemp)"
trap 'rm -f "$raw" "$err"' EXIT

# Keep stderr (not /dev/null) so a real failure is diagnosable. `vagrant ssh -c`
# prints "Connection to ... closed." to stderr on success — that's benign; we
# gate on the exit code and on validating the payload below, not on stderr.
if ! vagrant ssh "$NODE" -c "sudo cat /etc/rancher/k3s/k3s.yaml" >"$raw" 2>"$err"; then
  echo "ERROR: could not read /etc/rancher/k3s/k3s.yaml from ${NODE}:" >&2
  sed 's/^/  /' "$err" >&2
  exit 1
fi

# Validate we actually got a kubeconfig (not an empty file, an error, or a k3s
# that hasn't finished coming up).
if ! grep -q '^clusters:' "$raw" || ! grep -q 'server:' "$raw"; then
  echo "ERROR: fetched content is not a valid kubeconfig — is k3s up on ${NODE}?" >&2
  echo "  received (first 5 lines):" >&2
  head -5 "$raw" | sed 's/^/    /' >&2
  [ -s "$err" ] && { echo "  ssh stderr:" >&2; sed 's/^/    /' "$err" >&2; }
  exit 1
fi

# k3s.yaml comes back over a PTY, so it's polluted with CR line-endings AND the
# OSC-3008 "session" escape markers that recent systemd emits around the sudo PAM
# session (the Arch box ships systemd 261; Ubuntu 24.04's older systemd didn't emit
# them — which is why this only broke after the lab moved to Arch). Left in, they trip
# kubectl / the direnv KUBECONFIG guard with "yaml: control characters are not allowed".
# Strip the OSC/CSI escapes + CR, THEN rewrite the API server URL to the HAProxy VIP.
perl -0pe 's/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)//g; s/\x1b\[[0-9;?]*[ -\/]*[@-~]//g; s/\r//g' "$raw" \
  | sed "s#https://127.0.0.1:6443#https://${LB_IP}:6443#g" > "$OUT"
chmod 600 "$OUT"

echo "Wrote $(pwd)/${OUT} (API server: https://${LB_IP}:6443)"
echo
echo "  export KUBECONFIG=$(pwd)/${OUT}"
echo "  kubectl get nodes -o wide"
