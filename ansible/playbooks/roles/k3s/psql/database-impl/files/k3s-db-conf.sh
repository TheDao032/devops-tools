#!/usr/bin/env bash

set -e
PSQL_CONFIG_PATH=$1

# PSQL_VERSION=$1
# PSQL_CONFIG_PATH=/var/lib/pgsql/${PSQL_VERSION}/data/postgresql.conf

declare -A psql_conf=(
  [#listen_addresses]="listen_addresses = '*'"
)

for key in "${!psql_conf[@]}"; do
  key="${key}"
  value="${psql_conf[${key}]}"
  su -c "sed -i \"/${key}/c\\${value}\" ${PSQL_CONFIG_PATH}" postgres
done
