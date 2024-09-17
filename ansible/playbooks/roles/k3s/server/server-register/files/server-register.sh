#!/bin/bash

set -e
PSQL_URL=$1
SERVER_URL=$2
SERVER_TOKEN_FILE=$3

if [[ -f "${SERVER_TOKEN_FILE}" ]];
then
  curl -sfL https://get.k3s.io | sh -s - server --server "${SERVER_URL}" --write-kubeconfig-mode "0644" --datastore-endpoint="${PSQL_URL}" --token-file ${SERVER_TOKEN_FILE}
else
  curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode "0644" --datastore-endpoint="${PSQL_URL}"
fi

exit 0
