#!/usr/bin/env bash
# Join a k3s agent (worker) to the cluster via the HAProxy VIP.
# Pin the version by exporting INSTALL_K3S_VERSION before calling.
set -e

SERVER_URL=$1     # https://<vip>:6443
TOKEN=$2          # shared cluster token
NODE_IP=$3        # this node's cluster IP
FLANNEL_IFACE=$4  # cluster NIC for flannel VXLAN (e.g. k3scl0)
shift 4
EXTRA_ARGS="$@"

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" sh -s - \
    --server="${SERVER_URL}" \
    --token="${TOKEN}" \
    --node-ip="${NODE_IP}" \
    --flannel-iface="${FLANNEL_IFACE}" \
    ${EXTRA_ARGS}

exit 0
