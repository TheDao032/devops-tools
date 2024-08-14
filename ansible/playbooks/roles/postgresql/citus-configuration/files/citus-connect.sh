#!/usr/bin/env bash

set -e
MASTER_IP=$1
PSQL_DBNAME=$2

shift 2
SLAVE_IPS=("$@")

sudo -i -u postgres psql -d ${PSQL_DBNAME} -c \
  "SELECT citus_set_coordinator_host('${MASTER_IP}', 5432);"

for ip in "${SLAVE_IPS[@]}"; do
  sudo -i -u postgres psql -d ${PSQL_DBNAME} -c "SELECT * from citus_add_node('${ip}', 5432);"
done
