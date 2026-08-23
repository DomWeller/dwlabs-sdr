#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime

postgres_query "${POSTGRES_DB}" "UPDATE ops.runtime_flags SET enabled=FALSE,updated_at=NOW() WHERE flag_name IN ('followup_enabled','dispatcher_enabled'); UPDATE ops.runtime_flags SET enabled=TRUE,updated_at=NOW() WHERE flag_name='automation_paused'; UPDATE ops.delivery_outbox SET status='cancelled',updated_at=NOW() WHERE status IN ('queued','retry','claimed');" >/dev/null
docker_exec "${OPENCLAW_CONTAINER}" openclaw agents unbind --agent comercial --bind whatsapp:default >/dev/null 2>&1 || true
log "Piloto parado; filas pendentes canceladas e o agente main voltou a ser o destino default."

