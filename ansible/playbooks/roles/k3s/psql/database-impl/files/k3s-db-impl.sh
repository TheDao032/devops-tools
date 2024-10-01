#!/usr/bin/env bash

set -e
PSQL_K3S_PASSWORD=$1
PSQL_K3S_SQL_PATH=$2
PSQL_VERSION=$3

/usr/pgsql-${PSQL_VERSION}/bin/postgresql-${PSQL_VERSION}-setup initdb
systemctl enable postgresql-${PSQL_VERSION}
systemctl start postgresql-${PSQL_VERSION}

su -c "psql -v pass='${PSQL_K3S_PASSWORD}' -f ${PSQL_K3S_SQL_PATH}" postgres

exit 0
