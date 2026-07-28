#!/bin/sh
# Citus node entrypoint (Alpine). Idempotent first-boot init, then exec postgres.
# Runs as ROOT so it can chown the mounted PGDATA volume, then drops to `postgres`
# via su-exec for every postgres operation. Env (all have lab defaults):
#   PGDATA            data dir (set in the image)
#   POSTGRES_DB       app database created + owned by POSTGRES_USER   (default: app)
#   POSTGRES_USER     app login role                                  (default: app)
#   POSTGRES_PASSWORD app role password (scram for external clients)  (default: app)
#   TRUST_CIDR        CIDR trusted WITHOUT a password — the docker compose subnet so
#                     the coordinator<->worker Citus mesh authenticates by trust.
#                     Everything else on 0.0.0.0/0 needs the password (scram).
set -eu

: "${PGDATA:=/var/lib/postgresql/data}"
: "${POSTGRES_DB:=app}"
: "${POSTGRES_USER:=app}"
: "${POSTGRES_PASSWORD:=app}"
: "${TRUST_CIDR:=127.0.0.1/32}"

mkdir -p "$PGDATA" /run/postgresql
chown -R postgres:postgres "$PGDATA" /run/postgresql
chmod 700 "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[entrypoint] initializing new cluster in $PGDATA"
  su-exec postgres initdb -D "$PGDATA" \
    --encoding=UTF8 --locale=C \
    --auth-local=trust --auth-host=scram-sha-256

  # Cluster-wide config: listen everywhere + preload citus (required before
  # CREATE EXTENSION citus can succeed).
  cat >> "$PGDATA/postgresql.conf" <<-CONF
	# --- citus-docker managed ---
	listen_addresses = '*'
	shared_preload_libraries = 'citus'
	CONF

  # HBA: unix + loopback trust; the compose subnet trusts (intra-cluster mesh);
  # every other TCP client must present the password (scram). Lab-scoped — the
  # coordinator/pgbouncer ports are the only ones published off-host.
  cat > "$PGDATA/pg_hba.conf" <<-HBA
	local   all             all                                     trust
	host    all             all             127.0.0.1/32            trust
	host    all             all             ::1/128                 trust
	host    all             all             ${TRUST_CIDR}           trust
	host    all             all             0.0.0.0/0               scram-sha-256
	HBA

  # Temp local-only server to seed the role, db and extension.
  su-exec postgres pg_ctl -D "$PGDATA" -o "-c listen_addresses='localhost'" -w start

  su-exec postgres psql -v ON_ERROR_STOP=1 --username postgres --dbname postgres <<-SQL
	DO \$do\$ BEGIN
	  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
	    CREATE ROLE "${POSTGRES_USER}" LOGIN PASSWORD '${POSTGRES_PASSWORD}';
	  END IF;
	END \$do\$;
	SELECT 'CREATE DATABASE "${POSTGRES_DB}" OWNER "${POSTGRES_USER}"'
	  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${POSTGRES_DB}')\gexec
	SQL

  # Citus extension must exist in EVERY node's working db (coordinator + workers).
  su-exec postgres psql -v ON_ERROR_STOP=1 --username postgres --dbname "${POSTGRES_DB}" \
    -c "CREATE EXTENSION IF NOT EXISTS citus;"

  su-exec postgres pg_ctl -D "$PGDATA" -m fast -w stop
  echo "[entrypoint] init complete"
fi

echo "[entrypoint] starting: $*"
exec su-exec postgres "$@"
