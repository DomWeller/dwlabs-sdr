#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime

docker_exec "${OPENCLAW_CONTAINER}" openclaw agents list --bindings --json
docker_exec "${OPENCLAW_CONTAINER}" openclaw channels status --json
postgres_query "${POSTGRES_DB}" "SELECT flag_name || '=' || enabled FROM ops.runtime_flags WHERE flag_name IN ('automation_paused','followup_enabled','dispatcher_enabled') ORDER BY flag_name;"
postgres_query "${POSTGRES_DB}" "SELECT status || '=' || count(*) FROM ops.delivery_outbox GROUP BY status ORDER BY status;"

