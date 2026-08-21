#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env

SQL_FILE="${ROOT_DIR}/database/migrations/001_init.up.sql"
log "Migration pronta para execucao: ${SQL_FILE}"

if command -v psql >/dev/null 2>&1; then
  log "Para aplicar manualmente:"
  echo "PGPASSWORD=\"\${POSTGRES_OWNER_PASSWORD}\" psql -v ON_ERROR_STOP=1 -h \"\${POSTGRES_HOST}\" -p \"\${POSTGRES_PORT}\" -U \"\${POSTGRES_OWNER_USER}\" -d \"\${POSTGRES_DB}\" -f \"${SQL_FILE}\""
else
  log "psql nao encontrado localmente; nenhuma migration foi aplicada automaticamente."
fi
