#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_OWNER_USER
require_env POSTGRES_DB

superuser="$(detect_postgres_superuser)"
while IFS= read -r sql_file; do
  postgres_query_file_as_owner "${POSTGRES_DB}" "${POSTGRES_OWNER_USER}" "${sql_file}" "${superuser}"
  log "Migration aplicada: $(basename "${sql_file}")"
done < <(find "${ROOT_DIR}/database/migrations" -maxdepth 1 -type f -name '*.up.sql' | sort)
apply_database_grants "${superuser}"
apply_specialized_database_grants "${superuser}"
log "Migrations aplicadas em ${POSTGRES_DB}"
