#!/bin/bash

set -e
PSQL_URL=$1
KEEPALIVED_VIRTUAL_IP=$2
SERVER_IP=$3

curl -sfL https://get.k3s.io | sh -s - server \
    --node-ip ${SERVER_IP} \
    --tls-san ${KEEPALIVED_VIRTUAL_IP} \
    --write-kubeconfig-mode "0644" \
    --datastore-endpoint "${PSQL_URL}"

exit 0
