#!/usr/bin/env bash

set -e
SERVER_URL=$1
SERVER_TOKEN_FILE=$2
AGENT_IP=$3

# https://192.168.10.11:6445
if [[ -f "${SERVER_TOKEN_FILE}" ]];
then
  # curl -sfL https://get.k3s.io | sh -s - agent \
  #     --server ${SERVER_URL} \
  #     --token-file ${SERVER_TOKEN_FILE}

  curl -sfL https://get.k3s.io | K3S_URL=${SERVER_URL} sh -s - agent --node-ip ${AGENT_IP} --server ${SERVER_URL} --token $(cat ${SERVER_TOKEN_FILE})
  exit 0
fi

exit 1
