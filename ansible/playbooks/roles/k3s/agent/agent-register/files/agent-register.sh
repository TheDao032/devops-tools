#!/usr/bin/env bash

set -e
SERVER_URL=$1
SERVER_TOKEN=$2

# https://192.168.10.11:6445
curl -sfL https://get.k3s.io | sh -s - agent \
    --server ${SERVER_URL} \
    --token ${SERVER_TOKEN}

exit 0
