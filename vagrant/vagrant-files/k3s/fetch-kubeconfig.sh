#!/usr/bin/env bash
# Pull the cluster kubeconfig from k3s-server-1 and rewrite it to point at the
# HAProxy VIP, so kubectl on the host talks to the load-balanced API.
set -euo pipefail
cd "$(dirname "$0")"

LB_IP="${1:-192.168.105.10}"

echo "Fetching kubeconfig from k3s-server-1..."
vagrant ssh k3s-server-1 -c "sudo cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null \
  | sed "s#https://127.0.0.1:6443#https://${LB_IP}:6443#g" \
  > kubeconfig
chmod 600 kubeconfig

echo "Wrote ./kubeconfig (API server: https://${LB_IP}:6443)"
echo
echo "  export KUBECONFIG=$(pwd)/kubeconfig"
echo "  kubectl get nodes -o wide"
