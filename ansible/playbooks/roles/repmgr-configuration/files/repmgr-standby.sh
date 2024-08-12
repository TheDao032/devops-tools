#!/usr/bin/env bash

set -e
PSQL_VERSION=$1
MASTER_IP=$2
PSQL_REPMGR_CONFIG_PATH=$3
PSQL_DATA_DIRECTORY=$4
NODE_ID=$5

output=$(repmgr -f ${PSQL_REPMGR_CONFIG_PATH} cluster show)
if echo "$output" | grep -q ${NODE_ID}
then
    echo "This node is registered as the standby."
else
    echo "This node is NOT registered as the primary."
    sudo su -c "rm -rf ${PSQL_DATA_DIRECTORY}/*" postgres
    sudo su -c "repmgr -h ${MASTER_IP} -U repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby clone" postgres
    sudo su -c "repmgr -h ${MASTER_IP} -U repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby register" postgres
    exit 0
fi
