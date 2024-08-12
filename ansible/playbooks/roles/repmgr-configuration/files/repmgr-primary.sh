#!/usr/bin/env bash

set -e
PSQL_REPMGR_CONFIG_PATH=$1
# NODE_ID=$2

if ! command -v repmgr &> /dev/null
then
    echo "repmgr is not installed."
    exit 1
fi

repmgr -f ${PSQL_REPMGR_CONFIG_PATH} primary register --force
sudo su -c "repmgrd -f ${PSQL_REPMGR_CONFIG_PATH}" postgres
exit 0


# Check the cluster status
# output=$(cd /var/lib/postgresql && sudo su -c "psql -tAc \"SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'repmgr';\"" postgres)
#
# # Check if the current node is listed as primary
# if echo "$output" | grep -q 'repmgr'
# then
#     echo "This node is registered as the primary."
#     exit 0
# else
#     echo "This node is NOT registered as the primary."
#     repmgr -f ${PSQL_REPMGR_CONFIG_PATH} primary register
#     exit 0
# fi
