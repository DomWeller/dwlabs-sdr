#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_DB
require_env POSTGRES_USER
require_env POSTGRES_OWNER_USER
require_env POSTGRES_PASSWORD
require_env POSTGRES_ADMIN_PASSWORD
require_env POSTGRES_DISPATCHER_PASSWORD

superuser="$(detect_postgres_superuser)"
db_name_escaped="$(escape_sql_literal "${POSTGRES_DB}")"
owner_name_escaped="$(escape_sql_literal "${POSTGRES_OWNER_USER}")"
app_name_escaped="$(escape_sql_literal "${POSTGRES_USER}")"
app_password_escaped="$(escape_sql_literal "${POSTGRES_PASSWORD}")"
admin_name_escaped="$(escape_sql_literal "${POSTGRES_ADMIN_USER}")"
admin_password_escaped="$(escape_sql_literal "${POSTGRES_ADMIN_PASSWORD}")"
dispatcher_name_escaped="$(escape_sql_literal "${POSTGRES_DISPATCHER_USER}")"
dispatcher_password_escaped="$(escape_sql_literal "${POSTGRES_DISPATCHER_PASSWORD}")"

cluster_sql=$(cat <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${owner_name_escaped}') THEN
    EXECUTE format('CREATE ROLE %I NOLOGIN', '${POSTGRES_OWNER_USER}');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${app_name_escaped}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${POSTGRES_USER}', '${POSTGRES_PASSWORD}');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '${POSTGRES_USER}', '${POSTGRES_PASSWORD}');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${admin_name_escaped}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${POSTGRES_ADMIN_USER}', '${POSTGRES_ADMIN_PASSWORD}');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '${POSTGRES_ADMIN_USER}', '${POSTGRES_ADMIN_PASSWORD}');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${dispatcher_name_escaped}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${POSTGRES_DISPATCHER_USER}', '${POSTGRES_DISPATCHER_PASSWORD}');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '${POSTGRES_DISPATCHER_USER}', '${POSTGRES_DISPATCHER_PASSWORD}');
  END IF;
END
\$\$;
SQL
)

docker_exec "${N8N_POSTGRES_CONTAINER}" \
  psql -v ON_ERROR_STOP=1 -U "${superuser}" -d postgres -Atqc "${cluster_sql}" >/dev/null

if ! postgres_db_exists "${POSTGRES_DB}" "${superuser}"; then
  docker_exec "${N8N_POSTGRES_CONTAINER}" \
    psql -v ON_ERROR_STOP=1 -U "${superuser}" -d postgres -Atqc \
    "CREATE DATABASE \"${POSTGRES_DB}\" OWNER \"${POSTGRES_OWNER_USER}\";" >/dev/null
fi

apply_database_grants "${superuser}"

log "Bootstrap do banco ${POSTGRES_DB} concluido com roles minimas e grants idempotentes."
