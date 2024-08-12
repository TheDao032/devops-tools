#!/usr/bin/env bash

set -e
PSQL_VERSION=$1
PSQL_IP=$2
PSQL_NETWORK=$(echo $PSQL_IP | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.%s", $1, $2, $3, 0) }')
PSQL_CONFIG_PATH=/etc/postgresql/${PSQL_VERSION}/main/postgresql.conf
PSQL_HBA_CONFIG_PATH=/etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf
PSQL_REPMGR_SQL_PATH=/usr/bin/setup_repmgr.sql

declare -A psql_conf=(
 [#max_wal_senders]='max_wal_senders = 10'
 [#max_replication_slots]='max_replication_slots = 10'
 [#wal_level]='wal_level = replica'
 [#hot_standby]='hot_standby = on'
 [#wal_log_hints]='wal_log_hints = on'
 [#archive_command]="archive_command = 'bin/true'"
 [#listen_addresses]="listen_addresses = '*'"
 [#shared_preload_libraries]="shared_preload_libraries = 'repmgr'"
)

for key in "${!psql_conf[@]}"; do
  key="${key}"
  value="${psql_conf[${key}]}"
  sudo su -c "sed -i \"/${key}/c\\${value}\" ${PSQL_CONFIG_PATH}" postgres
done

declare -A hba_entries=(
  [entry1]="host    replication     repmgr          ${PSQL_NETWORK}/24         trust"
  [entry2]="host    repmgr          repmgr          127.0.0.1/32               trust"
  [entry3]="host    repmgr          repmgr          ${PSQL_NETWORK}/24         trust"
  [entry4]="local   repmgr          repmgr                                     trust"
)

# Loop through each entry and append it to the pg_hba.conf file
for key in ${!hba_entries[@]}; do
  entry="${hba_entries[${key}]}"
  if ! sudo grep -Fxq "$entry" "$PSQL_HBA_CONFIG_PATH"; then
    sudo su -c "echo \"$entry\" >> $PSQL_HBA_CONFIG_PATH" postgres
  else
    echo "Entry '$entry' already exists in $PSQL_HBA_CONFIG_PATH"
  fi
done

sudo -u postgres psql -f ${PSQL_REPMGR_SQL_PATH}
