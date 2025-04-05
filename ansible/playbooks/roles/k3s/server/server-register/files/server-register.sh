#!/bin/bash

set -e
# PSQL_URL=$1
KEEPALIVED_VIRTUAL_IP=$1
LOAD_BALANCER_PORT=$2
SERVER_IP=$3

    # --node-taint CriticalAddonsOnly=true:NoExecute \
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --cluster-init \
    --flannel-external-ip \
    --resolv-conf /etc/resolv.conf \
    --disable coredns \
    --flannel-backend wireguard-native \
    --write-kubeconfig-mode "0644" \
    --node-ip ${SERVER_IP} \
    --node-external-ip ${SERVER_IP} \
    --tls-san ${KEEPALIVED_VIRTUAL_IP} \
    --advertise-address ${KEEPALIVED_VIRTUAL_IP} \
    --advertise-port ${LOAD_BALANCER_PORT}

exit 0
