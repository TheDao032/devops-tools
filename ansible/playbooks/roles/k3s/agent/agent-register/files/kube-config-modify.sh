#!/usr/bin/env bash

set -e
KEEPALIVED_VIRTUAL_IP=$1
LOAD_BALANCER_PORT=$2
K3S_CONFIG_PATH=$3

declare -A k3s_conf=(
 [#server]="server: https://${KEEPALIVED_VIRTUAL_IP}:${LOAD_BALANCER_PORT}"
)

for key in "${!k3s_conf[@]}"; do
  key="${key}"
  value="${k3s_conf[${key}]}"
  sed -i "/${key}/c\\${value}" ${K3S_CONFIG_PATH}
done

