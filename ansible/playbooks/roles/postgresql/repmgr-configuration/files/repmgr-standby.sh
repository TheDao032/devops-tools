#!/usr/bin/env bash

set -e
PSQL_VERSION=$1
MASTER_IP=$2
PSQL_REPMGR_CONFIG_PATH=$3
PSQL_DATA_DIRECTORY=$4

sudo systemctl stop postgresql
sudo su -c "rm -rf ${PSQL_DATA_DIRECTORY}/*" postgres
sudo su -c "repmgr -h ${MASTER_IP} -U repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby clone --force" postgres
sudo systemctl restart postgresql

repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby register --force
sudo su -c "repmgrd -f ${PSQL_REPMGR_CONFIG_PATH}" postgres

exit 0
