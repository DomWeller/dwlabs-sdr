#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_DB
require_env N8N_SDR_SHARED_TOKEN

manual_public_guard

test -f "${ROOT_DIR}/openclaw-agent/comercial.agent.config.json"
test -f "${ROOT_DIR}/openclaw-agent/workspace/comercial/AGENTS.md"
test -f "${ROOT_DIR}/openclaw-agent/workspace/comercial/SOUL.md"
test -f "${ROOT_DIR}/openclaw-agent/workspace/comercial/IDENTITY.md"
test -f "${ROOT_DIR}/openclaw-agent/workspace/comercial/TOOLS.md"
test -f "${ROOT_DIR}/workflows/public-tools/sdr.buscar_servicos.json"
test -f "${ROOT_DIR}/database/migrations/001_init.up.sql"

wait_for_container_health "${N8N_POSTGRES_CONTAINER}" 120
wait_for_container_health "${N8N_CONTAINER}" 120
wait_for_container_health "${OPENCLAW_CONTAINER}" 120
wait_for_n8n_ready 120

services_count="$(postgres_query "${POSTGRES_DB}" "SELECT count(*) FROM core.services;")"
if [[ "${services_count}" != "13" ]]; then
  echo "Esperados 13 servicos no seed; obtidos ${services_count}" >&2
  exit 1
fi

workflow_expected="$(workflow_json_files | wc -l | tr -d ' ')"
workflow_export="$(docker_exec "${N8N_CONTAINER}" n8n export:workflow --all --pretty)"
workflow_present="$(printf '%s' "${workflow_export}" | grep -c '"name": "sdr\.' || true)"
workflow_active="$(printf '%s' "${workflow_export}" | grep -c '"active": true' || true)"

if [[ "${workflow_present}" != "${workflow_expected}" ]]; then
  echo "Quantidade de workflows SDR diverge: esperado ${workflow_expected}, obtido ${workflow_present}" >&2
  exit 1
fi

if [[ "${workflow_active}" != "${workflow_expected}" ]]; then
  echo "Nem todos os workflows SDR estao ativos/publicados: ${workflow_active}/${workflow_expected}" >&2
  exit 1
fi

while IFS= read -r workflow_file; do
  workflow_id="$(json_string_from_file "${workflow_file}" "id")"
  if ! printf '%s' "${workflow_export}" | grep -q "\"id\": \"${workflow_id}\""; then
    echo "Workflow nao encontrado no n8n: ${workflow_file}" >&2
    exit 1
  fi
done < <(workflow_json_files)

docker_exec "${OPENCLAW_CONTAINER}" openclaw health --json >/dev/null
docker_exec "${OPENCLAW_CONTAINER}" openclaw plugins inspect dwlabs-sdr-tools --runtime >/dev/null
docker_exec "${OPENCLAW_CONTAINER}" openclaw config validate >/dev/null
docker_exec "${OPENCLAW_CONTAINER}" openclaw agents list | grep -q "${SDR_AGENT_ID}"

negative_status="$(
  docker_exec "${N8N_CONTAINER}" node -e "
    const url = process.argv[1];
    fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        request_id: 'health-negative',
        idempotency_key: 'health-negative',
        channel: 'test',
        actor: {},
        context: {},
        payload: { active_only: true }
      })
    }).then((response) => response.status === 401 ? process.stdout.write('401') : process.exit(1)).catch(() => process.exit(1));
  " "${N8N_BASE_URL%/}/webhook/dwlabs-sdr/buscar-servicos"
)"

if [[ "${negative_status}" != "401" ]]; then
  echo "Webhook sem auth nao retornou 401." >&2
  exit 1
fi

docker_exec "${N8N_CONTAINER}" node -e "
  const url = process.argv[1];
  const token = process.argv[2];
  fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer ' + token
    },
    body: JSON.stringify({
      request_id: 'health-positive',
      idempotency_key: 'health-positive',
      channel: 'test',
      actor: { contact_name: 'Healthcheck' },
      context: { conversation_id: 'healthcheck' },
      payload: { active_only: true }
    })
  }).then(async (response) => {
    if (!response.ok) {
      process.exit(1);
    }
    const body = await response.json();
    if (!body || typeof body !== 'object') {
      process.exit(1);
    }
  }).catch(() => process.exit(1));
" "${N8N_BASE_URL%/}/webhook/dwlabs-sdr/buscar-servicos" "${N8N_SDR_SHARED_TOKEN}" >/dev/null

log "Healthcheck local/remoto concluido."
