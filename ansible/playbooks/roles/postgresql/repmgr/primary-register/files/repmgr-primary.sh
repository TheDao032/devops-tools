#!/usr/bin/env bash

set -e
PSQL_REPMGR_CONFIG_PATH=$1

if ! command -v repmgr &> /dev/null
then
    echo "repmgr is not installed."
    exit 1
fi

touch /var/lib/postgresql/15/repmgr.log && chown postgres /var/lib/postgresql/15/repmgr.log
/usr/bin/su -c "repmgr -f ${PSQL_REPMGR_CONFIG_PATH} primary register --force" postgres
/usr/bin/su -c "repmgrd -f ${PSQL_REPMGR_CONFIG_PATH}" postgres

exit 0
