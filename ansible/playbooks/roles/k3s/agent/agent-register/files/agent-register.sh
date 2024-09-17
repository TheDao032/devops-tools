#!/usr/bin/env bash

set -e
SERVER_URL=$1
SERVER_TOKEN_FILE=$2

# https://192.168.10.11:6445
if [[ -f "${SERVER_TOKEN_FILE}" ]];
then
  curl -sfL https://get.k3s.io | sh -s - agent \
      --server ${SERVER_URL} \
      --token-file ${SERVER_TOKEN_FILE}

  exit 0
fi

exit 1
