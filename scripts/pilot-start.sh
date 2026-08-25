#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env SDR_OWNER_ALLOWLIST

pilot_binding="${SDR_WHATSAPP_BINDING:-whatsapp:default}"
pilot_started=false

rollback_partial_start() {
  if [[ "${pilot_started}" != "true" ]]; then
    postgres_query "${POSTGRES_DB}" "UPDATE ops.runtime_flags SET enabled=FALSE,updated_at=NOW() WHERE flag_name IN ('followup_enabled','dispatcher_enabled'); UPDATE ops.runtime_flags SET enabled=TRUE,updated_at=NOW() WHERE flag_name='automation_paused'; UPDATE ops.delivery_outbox SET status='cancelled',updated_at=NOW() WHERE status IN ('queued','retry','claimed');" >/dev/null 2>&1 || true
    docker_exec "${OPENCLAW_CONTAINER}" openclaw agents unbind --agent "${SDR_AGENT_ID}" --bind "${pilot_binding}" >/dev/null 2>&1 || true
  fi
}

[[ "${CONFIRM_PILOT_OWNER_ONLY:-}" == "YES" ]] || { echo "Defina CONFIRM_PILOT_OWNER_ONLY=YES para iniciar o piloto." >&2; exit 1; }
[[ "${SDR_PUBLIC_FLAG:-false}" == "false" ]] || { echo "O piloto exige SDR_PUBLIC_FLAG=false." >&2; exit 1; }
[[ "${SDR_OWNER_ALLOWLIST}" != *,* ]] || { echo "O piloto aceita exatamente um numero na allowlist." >&2; exit 1; }

bash "${ROOT_DIR}/scripts/backup.sh"
bash "${ROOT_DIR}/scripts/healthcheck.sh"
channel_config="$(docker_exec "${OPENCLAW_CONTAINER}" openclaw config get channels.whatsapp --json)"
docker_exec_i "${OPENCLAW_CONTAINER}" node -e '
let raw="";process.stdin.on("data",c=>raw+=c);process.stdin.on("end",()=>{const c=JSON.parse(raw);if(c.dmPolicy!=="allowlist"||c.groupPolicy!=="disabled"||!Array.isArray(c.allowFrom)||c.allowFrom.length!==1)process.exit(1);});
' <<<"${channel_config}" || { echo "Politica WhatsApp nao esta owner-only." >&2; exit 1; }

trap rollback_partial_start EXIT
docker_exec "${OPENCLAW_CONTAINER}" openclaw agents bind --agent "${SDR_AGENT_ID}" --bind "${pilot_binding}" --json >/dev/null
sleep 2
binding_state="$(docker_exec "${OPENCLAW_CONTAINER}" openclaw agents list --bindings --json)"
docker_exec_i "${OPENCLAW_CONTAINER}" node -e '
let raw="";process.stdin.on("data",c=>raw+=c);process.stdin.on("end",()=>{const [agentId,binding]=process.argv.slice(1);const [channel,accountId="default"]=binding.split(":");const agents=JSON.parse(raw);const agent=agents.find(item=>item.id===agentId);const expected=`${channel} accountId=${accountId}`;if(!agent||agent.bindings<1||!Array.isArray(agent.bindingDetails)||!agent.bindingDetails.includes(expected))process.exit(1);});
' "${SDR_AGENT_ID}" "${pilot_binding}" <<<"${binding_state}" || { echo "Binding comercial nao permaneceu aplicado; rollback executado." >&2; exit 1; }

postgres_query "${POSTGRES_DB}" "UPDATE ops.runtime_flags SET enabled=TRUE,updated_at=NOW() WHERE flag_name IN ('followup_enabled','dispatcher_enabled'); UPDATE ops.runtime_flags SET enabled=FALSE,updated_at=NOW() WHERE flag_name='automation_paused';" >/dev/null
flags_state="$(postgres_query "${POSTGRES_DB}" "SELECT flag_name || '=' || enabled FROM ops.runtime_flags WHERE flag_name IN ('automation_paused','followup_enabled','dispatcher_enabled') ORDER BY flag_name;")"
[[ "${flags_state}" == $'automation_paused=false\ndispatcher_enabled=true\nfollowup_enabled=true' ]] || { echo "Flags do piloto divergentes; rollback executado." >&2; exit 1; }

pilot_started=true
trap - EXIT
log "Piloto owner-only iniciado. Execute scripts/pilot-stop.sh para rollback imediato."
