#!/bin/bash

set -e
# PSQL_URL=$1
SERVER_TOKEN_FILE=$1
KEEPALIVED_VIRTUAL_IP=$2
API_ENDPOINT=$3
API_PORT=$4
SERVER_SIDE_IP=$5

API_URL=https://${API_ENDPOINT}:${API_PORT}

if [[ -f "${SERVER_TOKEN_FILE}" ]];
then
      # --node-taint CriticalAddonsOnly=true:NoExecute \
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --flannel-external-ip \
      --resolv-conf /etc/resolv.conf \
      --flannel-backend wireguard-native \
      --disable coredns \
      --server ${API_URL} \
      --write-kubeconfig-mode "0644" \
      --node-ip ${SERVER_SIDE_IP} \
      --node-external-ip ${SERVER_SIDE_IP} \
      --tls-san ${KEEPALIVED_VIRTUAL_IP} \
      --token-file ${SERVER_TOKEN_FILE}

  exit 0
fi

exit 1
