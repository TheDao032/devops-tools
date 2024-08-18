#!/usr/bin/env bash

set -e
MASTER_IP=$1
PSQL_DBNAME=$2

shift 2
SLAVE_IPS=("$@")

su -c "psql -d ${PSQL_DBNAME} -c \"SELECT citus_set_coordinator_host('${MASTER_IP}', 5432);\"" postgres

for ip in "${SLAVE_IPS[@]}"; do
  su -c "psql -d ${PSQL_DBNAME} -c \"SELECT * from citus_add_node('${ip}', 5432);\"" postgres
done
