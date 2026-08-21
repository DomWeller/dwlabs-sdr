#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env

manual_public_guard
log "Rollback local preparado, sem acao remota automatica."
log "Ordem sugerida: despublicar workflows -> remover binding do agente -> aplicar database/migrations/001_init.down.sql -> restaurar backup externo."
