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

installed_plugin_matches_source() {
  local source_root="${ROOT_DIR}/plugins/dwlabs-sdr-tools"
  local installed_root="${OPENCLAW_HOST_ROOT}/data/config/extensions/dwlabs-sdr-tools"

  [[ -f "${source_root}/dist/index.js" ]] || return 1
  [[ -f "${installed_root}/dist/index.js" ]] || return 1
  [[ -f "${source_root}/openclaw.plugin.json" ]] || return 1
  [[ -f "${installed_root}/openclaw.plugin.json" ]] || return 1
  [[ -f "${source_root}/package.json" ]] || return 1
  [[ -f "${installed_root}/package.json" ]] || return 1

  cmp -s "${source_root}/dist/index.js" "${installed_root}/dist/index.js" &&
    cmp -s "${source_root}/openclaw.plugin.json" "${installed_root}/openclaw.plugin.json" &&
    cmp -s "${source_root}/package.json" "${installed_root}/package.json"
}

refresh_installed_plugin_files() {
  local source_root="${ROOT_DIR}/plugins/dwlabs-sdr-tools"
  local installed_root="${OPENCLAW_HOST_ROOT}/data/config/extensions/dwlabs-sdr-tools"

  mkdir -p "${installed_root}/dist" "${installed_root}/src"
  cp "${source_root}/dist/index.js" "${installed_root}/dist/index.js"
  cp "${source_root}/src/index.ts" "${installed_root}/src/index.ts"
  cp "${source_root}/openclaw.plugin.json" "${installed_root}/openclaw.plugin.json"
  cp "${source_root}/package.json" "${installed_root}/package.json"
  cp "${source_root}/README.md" "${installed_root}/README.md"
  cp "${source_root}/tsconfig.json" "${installed_root}/tsconfig.json"
}

install_or_reuse_plugin() {
  if installed_plugin_matches_source; then
    log "Plugin OpenClaw ja corresponde ao build atual; reinstalacao ignorada."
    return 0
  fi

  local installed_root="${OPENCLAW_HOST_ROOT}/data/config/extensions/dwlabs-sdr-tools"
  if [[ -d "${installed_root}/node_modules/typebox" ]]; then
    refresh_installed_plugin_files
    log "Plugin OpenClaw atualizado no diretorio gerenciado, preservando dependencias instaladas."
    return 0
  fi

  local bundle_path
  bundle_path="$(build_plugin_bundle)"
  docker cp "${bundle_path}" "${OPENCLAW_CONTAINER}:/tmp/dwlabs-sdr-tools.tgz"
  docker_exec "${OPENCLAW_CONTAINER}" openclaw plugins install --force /tmp/dwlabs-sdr-tools.tgz >/dev/null
  docker_exec "${OPENCLAW_CONTAINER}" rm -f /tmp/dwlabs-sdr-tools.tgz >/dev/null
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
  docker_exec_i "${OPENCLAW_CONTAINER}" node - "${SDR_AGENT_ID}" <<'NODE'
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

merge_json_arrays() {
  local current_json="$1"
  local added_json="$2"

  docker_exec_i "${OPENCLAW_CONTAINER}" node - "${current_json}" "${added_json}" <<'NODE'
const current = JSON.parse(process.argv[2]);
const added = JSON.parse(process.argv[3]);
process.stdout.write(JSON.stringify([...new Set([...current, ...added])]))
NODE
}

configure_global_tool_visibility() {
  local sdr_tools_json="$1"
  local global_allow_json
  local merged_global_allow_json
  local main_agent_index
  local main_deny_json
  local merged_main_deny_json

  global_allow_json="$(docker_exec "${OPENCLAW_CONTAINER}" openclaw config get tools.allow --json 2>/dev/null || printf '[]')"
  merged_global_allow_json="$(merge_json_arrays "${global_allow_json}" "${sdr_tools_json}")"
  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw config set tools.allow "${merged_global_allow_json}" --strict-json >/dev/null

  main_agent_index="$(read_agent_index main)"
  main_deny_json="$(docker_exec "${OPENCLAW_CONTAINER}" openclaw config get "agents.list[${main_agent_index}].tools.deny" --json 2>/dev/null || printf '[]')"
  merged_main_deny_json="$(merge_json_arrays "${main_deny_json}" "${sdr_tools_json}")"
  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw config set "agents.list[${main_agent_index}].tools.deny" "${merged_main_deny_json}" --strict-json >/dev/null

  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw config set plugins.entries.codex.config.codexDynamicToolsLoading '"direct"' --strict-json >/dev/null
}

configure_agent_tools() {
  local agent_index="$1"
  local allow_json="$2"
  local deny_json="$3"

  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw config unset "agents.list[${agent_index}].tools.alsoAllow" >/dev/null 2>&1 || true
  docker_exec "${OPENCLAW_CONTAINER}" \
    openclaw config set "agents.list[${agent_index}].tools.profile" '"full"' --strict-json >/dev/null
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
deny_tools_json='["group:runtime","group:fs","group:automation","group:web","group:ui","group:messaging","group:memory","group:sessions","group:media","group:nodes","group:agents","http","gateway","config","plugins_admin","debug"]'
plugin_config_json="$(printf '{"baseUrl":"%s","bearerToken":{"source":"env","provider":"default","id":"SDR_N8N_TOKEN"},"timeoutMs":%s,"allowlist":%s}' "${OPENCLAW_PLUGIN_BASE_URL}" "${OPENCLAW_PLUGIN_TIMEOUT_MS}" "${plugin_allowlist_json}")"

install_or_reuse_plugin
docker_exec "${OPENCLAW_CONTAINER}" openclaw plugins enable dwlabs-sdr-tools >/dev/null

patch_openclaw_env
sync_workspace
ensure_agent
agent_index="$(read_agent_index)"
configure_plugin "${plugin_config_json}"
configure_global_tool_visibility "${sdr_tools_json}"
configure_agent_tools "${agent_index}" "${sdr_tools_json}" "${deny_tools_json}"
set_agent_identity

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
