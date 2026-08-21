#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env N8N_PROJECT_ID

manual_public_guard
ensure_remote_layout

log "Rodando build local antes do deploy remoto"
npm ci
npm run build
npm run validate

bash "${ROOT_DIR}/scripts/backup.sh"
bash "${ROOT_DIR}/scripts/migrate.sh"
bash "${ROOT_DIR}/scripts/seed.sh"
bash "${ROOT_DIR}/scripts/import-workflows.sh"
bash "${ROOT_DIR}/scripts/healthcheck.sh"

log "Deploy preparado sem bind publico. Publique o canal apenas no gate final."
