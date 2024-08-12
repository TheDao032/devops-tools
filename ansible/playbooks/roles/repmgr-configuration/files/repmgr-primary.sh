#!/usr/bin/env bash

set -e
PSQL_REPMGR_CONFIG_PATH=$1
NODE_ID=$2

if ! command -v repmgr &> /dev/null
then
    echo "repmgr is not installed."
    exit 1
fi

# Check the cluster status
output=$(repmgr -f ${PSQL_REPMGR_CONFIG_PATH} cluster show)

# Check if the current node is listed as primary
if echo "$output" | grep -q '1'
then
    echo "This node is registered as the primary."
else
    echo "This node is NOT registered as the primary."
    repmgr -f ${PSQL_REPMGR_CONFIG_PATH} primary register
    exit 0
fi
