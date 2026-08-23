#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env SDR_OWNER_ALLOWLIST

[[ "${CONFIRM_PILOT_OWNER_ONLY:-}" == "YES" ]] || { echo "Defina CONFIRM_PILOT_OWNER_ONLY=YES para iniciar o piloto." >&2; exit 1; }
[[ "${SDR_PUBLIC_FLAG:-false}" == "false" ]] || { echo "O piloto exige SDR_PUBLIC_FLAG=false." >&2; exit 1; }
[[ "${SDR_OWNER_ALLOWLIST}" != *,* ]] || { echo "O piloto aceita exatamente um numero na allowlist." >&2; exit 1; }

bash "${ROOT_DIR}/scripts/backup.sh"
bash "${ROOT_DIR}/scripts/healthcheck.sh"
channel_config="$(docker_exec "${OPENCLAW_CONTAINER}" openclaw config get channels.whatsapp --json)"
docker_exec_i "${OPENCLAW_CONTAINER}" node -e '
let raw="";process.stdin.on("data",c=>raw+=c);process.stdin.on("end",()=>{const c=JSON.parse(raw);if(c.dmPolicy!=="allowlist"||c.groupPolicy!=="disabled"||!Array.isArray(c.allowFrom)||c.allowFrom.length!==1)process.exit(1);});
' <<<"${channel_config}" || { echo "Politica WhatsApp nao esta owner-only." >&2; exit 1; }

docker_exec "${OPENCLAW_CONTAINER}" openclaw agents bind --agent comercial --bind whatsapp:default >/dev/null
postgres_query "${POSTGRES_DB}" "UPDATE ops.runtime_flags SET enabled=TRUE,updated_at=NOW() WHERE flag_name IN ('followup_enabled','dispatcher_enabled'); UPDATE ops.runtime_flags SET enabled=FALSE,updated_at=NOW() WHERE flag_name='automation_paused';" >/dev/null
log "Piloto owner-only iniciado. Execute scripts/pilot-stop.sh para rollback imediato."

