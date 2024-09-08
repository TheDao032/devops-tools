#!/usr/bin/env bash

set -e
PSQL_K3S_PASSWORD=$1
PSQL_K3S_SQL_PATH=$2

su -c "psql -v k3spass='${PSQL_K3S_PASSWORD}' -f ${PSQL_K3S_SQL_PATH}" postgres

exit 0
