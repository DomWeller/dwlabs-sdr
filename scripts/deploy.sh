#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env

manual_public_guard
log "Deploy remoto nao sera executado automaticamente nesta etapa."
log "Fluxo previsto:"
log "1. backup pre-release"
log "2. npm run build"
log "3. scripts/import-workflows.sh"
log "4. scripts/migrate.sh"
log "5. scripts/seed.sh"
log "6. instalar plugin OpenClaw e criar agente comercial owner-only"
log "7. scripts/healthcheck.sh"
