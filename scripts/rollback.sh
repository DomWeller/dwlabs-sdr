#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_OWNER_USER
require_env POSTGRES_DB

manual_public_guard
docker_exec "${N8N_CONTAINER}" n8n unpublish:workflow --all >/dev/null || true
docker_exec_i "${N8N_POSTGRES_CONTAINER}" psql -v ON_ERROR_STOP=1 -U "${POSTGRES_OWNER_USER}" -d "${POSTGRES_DB}" < "${ROOT_DIR}/database/migrations/001_init.down.sql" >/dev/null
log "Rollback SQL concluido; restaure o dump mais recente em ${REMOTE_DEPLOY_ROOT}/backups se necessario."
