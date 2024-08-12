#!/usr/bin/env bash

set -e
PSQL_VERSION=$1
MASTER_IP=$2
PSQL_REPMGR_CONFIG_PATH=$3
PSQL_DATA_DIRECTORY=$4
# NODE_ID=$5

sudo systemctl stop postgresql
sudo su -c "rm -rf ${PSQL_DATA_DIRECTORY}/*" postgres
sudo su -c "repmgr -h ${MASTER_IP} -U repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby clone --force" postgres
sudo systemctl restart postgresql

repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby register --force
sudo su -c "repmgrd -f ${PSQL_REPMGR_CONFIG_PATH}" postgres
exit 0

# output=$(sudo su -c "psql -tAc \"SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'repmgr';\"" postgres)
# if echo "$output" | grep -q 'repmgr'
# then
#     echo "This node is registered as the standby."
#     exit 0
# else
#     echo "This node is NOT registered as the standby."
#     # sudo su -c "rm -rf ${PSQL_DATA_DIRECTORY}/*" postgres
#     sudo su -c "repmgr -h ${MASTER_IP} -U repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby clone --force" postgres
#     sudo systemctl restart postgresql
#
#     repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby register
#     exit 0
# fi
