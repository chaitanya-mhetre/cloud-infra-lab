#!/usr/bin/env bash
# Create production-fastapi's least-privilege Postgres roles (idempotent).
#   slotwise         owner: runs migrations (the master/POSTGRES_USER)
#   slotwise_app     API role: row-level security ENFORCED
#   slotwise_worker  relay + Celery: BYPASSRLS (processes queues across tenants)
#
# Used two ways:
#   * dev host: mounted into postgres' /docker-entrypoint-initdb.d (runs on first init)
#   * RDS:      PGHOST=... PGUSER=slotwise PGPASSWORD=<master> APP_DB_PASSWORD=... WORKER_DB_PASSWORD=... ./db-roles.sh
set -euo pipefail
: "${APP_DB_PASSWORD:?APP_DB_PASSWORD required}"
: "${WORKER_DB_PASSWORD:?WORKER_DB_PASSWORD required}"
DB="${POSTGRES_DB:-${PGDATABASE:-slotwise}}"

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-${PGUSER:-slotwise}}" --dbname "$DB" \
  -v app_pw="$APP_DB_PASSWORD" -v worker_pw="$WORKER_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE slotwise_app LOGIN PASSWORD %L NOBYPASSRLS', :'app_pw')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'slotwise_app') \gexec
SELECT format('CREATE ROLE slotwise_worker LOGIN PASSWORD %L BYPASSRLS', :'worker_pw')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'slotwise_worker') \gexec
-- Rotate passwords on every run so SSM stays the source of truth.
SELECT format('ALTER ROLE slotwise_app PASSWORD %L', :'app_pw') \gexec
SELECT format('ALTER ROLE slotwise_worker PASSWORD %L', :'worker_pw') \gexec
SQL
echo "roles ok"
