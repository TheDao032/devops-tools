#!/usr/bin/env bash

set -e
SERVER_URL=$1
SERVER_TOKEN_FILE=$2
AGENT_IP=$3

# https://192.168.10.11:6445
if [[ -f "${SERVER_TOKEN_FILE}" ]];
then
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" sh -s - \
      --server ${SERVER_URL} \
      --node-ip ${AGENT_IP} \
      --node-external-ip ${AGENT_IP} \
      --token-file ${SERVER_TOKEN_FILE}
  exit 0
fi

exit 1
