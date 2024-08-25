#!/usr/bin/env bash

set -e
AUTH_USER=$1
DB_HOST=$2
DB_NAME=$3
DB_PORT=$4
PGBOUNCER_CONFIG_PATH=/etc/pgbouncer/pgbouncer.ini

declare -A psql_conf=(
 ["\[databases\]"]="${DB_NAME} = host=${DB_HOST} dbname=${DB_NAME} port=${DB_PORT} auth_user=${AUTH_USER}"
 [";pool_mode"]="pool_mode = session"
 [";max_client_conn"]="max_client_conn = 5000"
)

for key in "${!psql_conf[@]}"; do
  key="${key}"
  value="${psql_conf[${key}]}"
  sed -i "/^${key}/a\\${value}" ${PGBOUNCER_CONFIG_PATH}
done

exit 0
