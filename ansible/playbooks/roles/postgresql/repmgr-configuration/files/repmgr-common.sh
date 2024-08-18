#!/usr/bin/env bash

set -e
PSQL_VERSION=$1
PSQL_IP=$2
PSQL_REPMGR_SQL_PATH=$3
PSQL_NETWORK=$(echo $PSQL_IP | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.%s", $1, $2, $3, 0) }')
PSQL_CONFIG_PATH=/etc/postgresql/${PSQL_VERSION}/main/postgresql.conf
PSQL_HBA_CONFIG_PATH=/etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf

declare -A psql_conf=(
 [#listen_addresses]="listen_addresses = '*'"
 [#max_wal_senders]='max_wal_senders = 10'
 [#max_replication_slots]='max_replication_slots = 10'
 [#hot_standby]='hot_standby = on'
 [#wal_log_hints]='wal_log_hints = on'
 [#archive_mode]='archive_mode = on'
 [#wal_level]='wal_level = hot_standby'
 [#log_statement]="log_statement = 'all'"
 [#archive_command]="archive_command = '/bin/true'"
 [#shared_preload_libraries]="shared_preload_libraries = 'repmgr'"
)

for key in "${!psql_conf[@]}"; do
  key="${key}"
  value="${psql_conf[${key}]}"
  sed -i "/${key}/c\\${value}" ${PSQL_CONFIG_PATH}
done

su -c "psql -f ${PSQL_REPMGR_SQL_PATH}" postgres

exit 0
