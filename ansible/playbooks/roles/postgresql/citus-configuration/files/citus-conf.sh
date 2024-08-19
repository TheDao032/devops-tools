#!/usr/bin/env bash

set -e
PSQL_VERSION=$1
PSQL_CITUS_TRIGGER_SQL_PATH=$2
PSQL_CONFIG_PATH=/etc/postgresql/${PSQL_VERSION}/main/postgresql.conf

declare -A psql_conf=(
  [#listen_addresses]="listen_addresses = '*'"
  [#shared_preload_libraries]="shared_preload_libraries = 'citus'"
)

for key in "${!psql_conf[@]}"; do
  key="${key}"
  value="${psql_conf[${key}]}"
  su -c "sed -i \"/${key}/c\\${value}\" ${PSQL_CONFIG_PATH}" postgres
done

su -c "psql -f ${PSQL_CITUS_TRIGGER_SQL_PATH}" postgres
