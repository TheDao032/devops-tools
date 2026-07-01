#!/usr/bin/env bash
# Install a k3s server node backed by an EXTERNAL etcd datastore.
# Pin the version by exporting INSTALL_K3S_VERSION before calling (the ansible
# task sets it from k3s_version). Extra k3s args may follow the 5 positionals.
set -e

DATASTORE_ENDPOINT=$1   # http://<etcd-ip>:2379
TOKEN=$2                # shared cluster token
NODE_IP=$3             # this node's cluster IP
LB_IP=$4              # HAProxy VIP (added as a TLS SAN so agents/kubectl trust it)
FLANNEL_IFACE=$5      # cluster NIC for flannel VXLAN (e.g. k3scl0)
shift 5
EXTRA_ARGS="$@"

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - \
    --datastore-endpoint="${DATASTORE_ENDPOINT}" \
    --token="${TOKEN}" \
    --node-ip="${NODE_IP}" \
    --advertise-address="${NODE_IP}" \
    --flannel-iface="${FLANNEL_IFACE}" \
    --tls-san="${LB_IP}" \
    --tls-san="${NODE_IP}" \
    --write-kubeconfig-mode=0644 \
    ${EXTRA_ARGS}

exit 0
