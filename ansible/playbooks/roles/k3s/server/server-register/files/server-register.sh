#!/bin/bash

set -e
PSQL_URL=$1
KEEPALIVED_VIRTUAL_IP=$2
SERVER_IP=$3

# --datastore-endpoint "${PSQL_URL}"
# --node-ip ${SERVER_IP} \
curl -sfL https://get.k3s.io | sh -s - server \
    --cluster-init \
    --tls-san ${KEEPALIVED_VIRTUAL_IP} \
    --write-kubeconfig-mode "0644"

exit 0
