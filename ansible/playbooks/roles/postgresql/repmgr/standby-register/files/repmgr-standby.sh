#!/usr/bin/env bash

set -e
PSQL_VERSION=$1
MASTER_IP=$2
PSQL_REPMGR_CONFIG_PATH=$3
PSQL_DATA_DIRECTORY=$4
COORDINATOR_PSQL_PORT=$5

touch /var/lib/postgresql/15/repmgr.log && chown postgres /var/lib/postgresql/15/repmgr.log
systemctl stop postgresql
su -c "rm -rf ${PSQL_DATA_DIRECTORY}/*" postgres
su -c "repmgr -h ${MASTER_IP} -U repmgr -p ${COORDINATOR_PSQL_PORT} -f ${PSQL_REPMGR_CONFIG_PATH} standby clone --force" postgres
systemctl restart postgresql

su -c "repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby register --force" postgres
su -c "repmgrd -f ${PSQL_REPMGR_CONFIG_PATH}" postgres

exit 0
