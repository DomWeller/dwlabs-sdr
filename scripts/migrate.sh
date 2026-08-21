#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_OWNER_USER
require_env POSTGRES_DB

sql_file="${ROOT_DIR}/database/migrations/001_init.up.sql"
docker_exec_i "${N8N_POSTGRES_CONTAINER}" psql -v ON_ERROR_STOP=1 -U "${POSTGRES_OWNER_USER}" -d "${POSTGRES_DB}" < "${sql_file}" >/dev/null
log "Migration aplicada em ${POSTGRES_DB}"
