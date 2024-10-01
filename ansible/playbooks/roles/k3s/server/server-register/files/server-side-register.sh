#!/bin/bash

set -e
PSQL_URL=$1
SERVER_TOKEN_FILE=$2
KEEPALIVED_VIRTUAL_IP=$3
SERVER_IP=$4
SERVER_URL=$5

if [[ -f "${SERVER_TOKEN_FILE}" ]];
then
  curl -sfL https://get.k3s.io | K3S_URL=${SERVER_URL} sh -s - server \
    --flannel-backend wireguard-native \
    --datastore-endpoint "${PSQL_URL}" \
    --server ${SERVER_URL} \
    --node-external-ip ${SERVER_IP} \
    --tls-san ${KEEPALIVED_VIRTUAL_IP} \
    --write-kubeconfig-mode "0644" \
    --token-file ${SERVER_TOKEN_FILE}
  exit 0
fi

exit 1
