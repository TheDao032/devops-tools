#!/usr/bin/env bash

set -e
PSQL_K3S_PASSWORD=$1
PSQL_K3S_SQL_PATH=$2

su -c "psql -v pass='${PSQL_K3S_PASSWORD}' -f ${PSQL_K3S_SQL_PATH}" postgres
# su -c "psql -c \"ALTER USER k3s WITH PASSWORD '$PSQL_K3S_PASSWORD';\"" postgres

# su -c "psql -c \"ALTER USER k3s WITH PASSWORD '\'$PSQL_K3S_PASSWORD\'';\"" postgres
# su -c "psql -c \"ALTER USER k3s WITH PASSWORD '${PSQL_K3S_PASSWORD}';\"" postgres

exit 0
