#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime

manual_public_guard
require_cmd npm

test -f "${ROOT_DIR}/openclaw-agent/comercial.agent.config.json"
test -f "${ROOT_DIR}/workflows/public-tools/sdr.buscar_servicos.json"
test -f "${ROOT_DIR}/database/migrations/001_init.up.sql"

docker_exec "${N8N_CONTAINER}" n8n export:workflow --all --pretty >/dev/null
docker_exec "${OPENCLAW_CONTAINER}" openclaw agents list >/dev/null
docker_exec "${OPENCLAW_CONTAINER}" openclaw plugins inspect dwlabs-sdr-tools >/dev/null

npm run validate >/dev/null
log "Healthcheck local/remoto concluido."
