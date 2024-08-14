#!/usr/bin/env bash

set -e
PSQL_REPMGR_CONFIG_PATH=$1

if ! command -v repmgr &> /dev/null
then
    echo "repmgr is not installed."
    exit 1
fi

repmgr -f ${PSQL_REPMGR_CONFIG_PATH} primary register --force
sudo su -c "repmgrd -f ${PSQL_REPMGR_CONFIG_PATH}" postgres

exit 0
