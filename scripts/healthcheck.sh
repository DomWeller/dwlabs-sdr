#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env

manual_public_guard
require_cmd node

log "Healthcheck local do projeto"
node -e "console.log('node_ok', process.version)"
test -f "${ROOT_DIR}/openclaw-agent/comercial.agent.config.json"
test -f "${ROOT_DIR}/database/migrations/001_init.up.sql"
test -f "${ROOT_DIR}/workflows/public-tools/sdr.buscar_servicos.json"
log "Artefatos locais essenciais presentes."
