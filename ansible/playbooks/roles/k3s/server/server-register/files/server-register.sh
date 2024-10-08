#!/bin/bash

set -e
# PSQL_URL=$1
KEEPALIVED_VIRTUAL_IP=$1
SERVER_IP=$2

    # --node-taint CriticalAddonsOnly=true:NoExecute \
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --cluster-init \
    --flannel-external-ip \
    --flannel-backend wireguard-native \
    --write-kubeconfig-mode "0644" \
    --node-ip ${SERVER_IP} \
    --node-external-ip ${SERVER_IP} \
    --tls-san ${KEEPALIVED_VIRTUAL_IP}

exit 0
