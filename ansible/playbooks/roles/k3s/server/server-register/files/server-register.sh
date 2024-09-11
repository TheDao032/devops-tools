#!/usr/bin/env bash

set -e
PSQL_URL=$1
SERVER_TOKEN=$2

if [[ -n ${SERVER_TOKEN} ]]; then
  curl -sfL https://get.k3s.io | sh -s - server \
      --write-kubeconfig-mode "0644" \
      --node-taint CriticalAddonsOnly=true:NoExecute \
      --datastore-endpoint="${PSQL_URL}" \
      --token ${SERVER_TOKEN}
else
  curl -sfL https://get.k3s.io | sh -s - server \
      --write-kubeconfig-mode "0644" \
      --node-taint CriticalAddonsOnly=true:NoExecute \
      --datastore-endpoint="${PSQL_URL}"
fi

exit 0
