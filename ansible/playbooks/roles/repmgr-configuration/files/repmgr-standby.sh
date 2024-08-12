#!/usr/bin/env bash
PSQL_VERSION=$1
MASTER_IP=$2
PSQL_REPMGR_CONFIG_PATH=$3
PSQL_DATA_DIRECTORY=$4

sudo rm -rf ${PSQL_DATA_DIRECTORY}/*

repmgr -h ${MASTER_IP} -U repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby clone
repmgr -h ${MASTER_IP} -U repmgr -f ${PSQL_REPMGR_CONFIG_PATH} standby register
