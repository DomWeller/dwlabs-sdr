#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_OWNER_USER
require_env POSTGRES_DB

sql_file="${ROOT_DIR}/database/seeds/001_seed_catalog.sql"
superuser="$(detect_postgres_superuser)"
postgres_query_file_as_owner "${POSTGRES_DB}" "${POSTGRES_OWNER_USER}" "${sql_file}" "${superuser}"
apply_database_grants "${superuser}"
log "Seed aplicado em ${POSTGRES_DB}"
