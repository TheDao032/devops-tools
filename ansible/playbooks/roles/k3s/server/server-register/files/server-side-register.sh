#!/bin/bash

set -e
PSQL_URL=$1
SERVER_TOKEN_FILE=$2
KEEPALIVED_VIRTUAL_IP=$3
SERVER_IP=$4

if [[ -f "${SERVER_TOKEN_FILE}" ]];
then
  curl -sfL https://get.k3s.io | sh -s - server \
    --node-ip ${SERVER_IP} \
    --tls-san ${KEEPALIVED_VIRTUAL_IP} \
    --write-kubeconfig-mode "0644" \
    --datastore-endpoint "${PSQL_URL}" \
    --token-file ${SERVER_TOKEN_FILE}
  exit 0
fi

exit 1
