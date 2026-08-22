#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env N8N_SDR_SHARED_TOKEN

tmp_dir="$(remote_tmp_dir)"
trap 'cleanup_dir "${tmp_dir}"' EXIT

build_plugin_bundle() {
  local bundle_path="${tmp_dir}/dwlabs-sdr-tools.tgz"

  docker run --rm \
    -v "${ROOT_DIR}:/src:ro" \
    -v "${tmp_dir}:/out" \
    -w /work \
    node:22-bookworm sh -lc '
      mkdir -p /work
      cp -R /src/package.json /src/package-lock.json /src/tsconfig.json /src/plugins /work/
      cd /work
      npm ci >/dev/null
      npm run build:plugin >/dev/null
      tar -C /work/plugins -czf /out/dwlabs-sdr-tools.tgz dwlabs-sdr-tools
    '

  printf '%s\n' "${bundle_path}"
}

patch_openclaw_env() {
  mkdir -p "${OPENCLAW_HOST_ROOT}"
  touch "${OPENCLAW_HOST_ENV_FILE}"
  chmod 600 "${OPENCLAW_HOST_ENV_FILE}"

  if grep -q '^SDR_N8N_TOKEN=' "${OPENCLAW_HOST_ENV_FILE}" 2>/dev/null; then
    perl -0pi -e "s#^SDR_N8N_TOKEN=.*\$#SDR_N8N_TOKEN=${N8N_SDR_SHARED_TOKEN}#m" "${OPENCLAW_HOST_ENV_FILE}"
  else
    printf 'SDR_N8N_TOKEN=%s\n' "${N8N_SDR_SHARED_TOKEN}" >> "${OPENCLAW_HOST_ENV_FILE}"
  fi

  chmod 600 "${OPENCLAW_HOST_ENV_FILE}"
}

sync_workspace() {
  mkdir -p "${OPENCLAW_PLUGIN_WORKSPACE_ROOT}"
  cp -R "${ROOT_DIR}/openclaw-agent/workspace/comercial/." "${OPENCLAW_PLUGIN_WORKSPACE_ROOT}/"
  restrict_permissions "${OPENCLAW_PLUGIN_WORKSPACE_ROOT}"
}

agent_exists() {
  docker_exec "${OPENCLAW_CONTAINER}" openclaw agents list | grep -q "${SDR_AGENT_ID}"
}

ensure_agent() {
  if agent_exists; then
    return 0
  fi

  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw agents add "${SDR_AGENT_ID}" \
    --non-interactive \
    --workspace /home/node/.openclaw/workspace-comercial \
    --model openai/gpt-5.4-mini >/dev/null
}

read_agent_index() {
  docker_exec "${OPENCLAW_CONTAINER}" node - "${SDR_AGENT_ID}" <<'NODE'
const fs = require("node:fs");

const agentId = process.argv[2];
const candidatePaths = [
  "/home/node/.openclaw/openclaw.json",
  "/home/node/.openclaw/config/openclaw.json",
  "/home/node/.openclaw/data/config/openclaw.json"
];

for (const configPath of candidatePaths) {
  if (!fs.existsSync(configPath)) {
    continue;
  }

  const raw = fs.readFileSync(configPath, "utf8");
  const config = JSON.parse(raw);
  const agents = Array.isArray(config?.agents?.list) ? config.agents.list : [];
  const index = agents.findIndex((agent) => agent && agent.id === agentId);
  if (index >= 0) {
    process.stdout.write(String(index));
    process.exit(0);
  }
}

process.exit(1);
NODE
}

configure_plugin() {
  local plugin_config_json="$1"
  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw config set plugins.entries.dwlabs-sdr-tools.config "${plugin_config_json}" --strict-json >/dev/null
}

configure_agent_tools() {
  local agent_index="$1"
  local allow_json="$2"
  local deny_json="$3"

  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw config set "agents.list[${agent_index}].tools.allow" "${allow_json}" --strict-json >/dev/null
  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw config set "agents.list[${agent_index}].tools.deny" "${deny_json}" --strict-json >/dev/null
}

set_agent_identity() {
  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw agents set-identity \
    --agent "${SDR_AGENT_ID}" \
    --identity-file /home/node/.openclaw/workspace-comercial/IDENTITY.md >/dev/null
}

sdr_tools_json='["buscar_servicos","buscar_servico","buscar_precos","buscar_portfolio","salvar_lead","atualizar_lead","buscar_lead","buscar_cliente","registrar_interacao","calcular_score","verificar_agenda","agendar_reuniao","reagendar_reuniao","cancelar_reuniao","criar_resumo","notificar_vendedor","agendar_followup","cancelar_followup","buscar_conhecimento","transcrever_audio","transferir_humano","sincronizar_sheets"]'
plugin_allowlist_json='["dwlabs-sdr/buscar-servicos","dwlabs-sdr/buscar-servico","dwlabs-sdr/buscar-precos","dwlabs-sdr/buscar-portfolio","dwlabs-sdr/salvar-lead","dwlabs-sdr/atualizar-lead","dwlabs-sdr/buscar-lead","dwlabs-sdr/buscar-cliente","dwlabs-sdr/registrar-interacao","dwlabs-sdr/calcular-score","dwlabs-sdr/verificar-agenda","dwlabs-sdr/agendar-reuniao","dwlabs-sdr/reagendar-reuniao","dwlabs-sdr/cancelar-reuniao","dwlabs-sdr/criar-resumo","dwlabs-sdr/notificar-vendedor","dwlabs-sdr/agendar-followup","dwlabs-sdr/cancelar-followup","dwlabs-sdr/buscar-conhecimento","dwlabs-sdr/transcrever-audio","dwlabs-sdr/transferir-humano","dwlabs-sdr/sincronizar-sheets"]'
deny_tools_json='["group:runtime","group:fs","group:automation","http","gateway","config","plugins_admin","debug"]'
plugin_config_json="$(printf '{"baseUrl":"%s","timeoutMs":%s,"allowlist":%s}' "${OPENCLAW_PLUGIN_BASE_URL}" "${OPENCLAW_PLUGIN_TIMEOUT_MS}" "${plugin_allowlist_json}")"

bundle_path="$(build_plugin_bundle)"
docker cp "${bundle_path}" "${OPENCLAW_CONTAINER}:/tmp/dwlabs-sdr-tools.tgz"
docker_exec "${OPENCLAW_CONTAINER}" openclaw plugins install --force /tmp/dwlabs-sdr-tools.tgz >/dev/null
docker_exec "${OPENCLAW_CONTAINER}" openclaw plugins enable dwlabs-sdr-tools >/dev/null

patch_openclaw_env
sync_workspace
ensure_agent
agent_index="$(read_agent_index)"
configure_plugin "${plugin_config_json}"
configure_agent_tools "${agent_index}" "${sdr_tools_json}" "${deny_tools_json}"
set_agent_identity

docker_exec "${OPENCLAW_CONTAINER}" rm -f /tmp/dwlabs-sdr-tools.tgz >/dev/null
(
  cd "${OPENCLAW_HOST_ROOT}"
  docker compose up -d --force-recreate openclaw-gateway >/dev/null
)
wait_for_container_health "${OPENCLAW_CONTAINER}" 120
docker_exec "${OPENCLAW_CONTAINER}" openclaw plugins inspect dwlabs-sdr-tools --runtime >/dev/null
docker_exec "${OPENCLAW_CONTAINER}" openclaw agents list | grep -q "${SDR_AGENT_ID}"

if [[ "${SDR_BIND_WHATSAPP}" == "true" ]]; then
  docker_exec "${OPENCLAW_CONTAINER}" openclaw agents bind --agent "${SDR_AGENT_ID}" --bind "${SDR_WHATSAPP_BINDING:-whatsapp}" >/dev/null
fi

log "Plugin/agente OpenClaw instalados e configurados de forma idempotente."
