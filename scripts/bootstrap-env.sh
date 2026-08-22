#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime

ensure_env_file

preserve_or_generate() {
  local key="$1"
  if env_file_has_real_value "${key}"; then
    return 0
  fi

  upsert_env_value "${key}" "$(generate_secret_hex)"
}

discover_n8n_project_id() {
  local superuser="$1"
  local query
  local result=""

  local queries=(
    "SELECT id::text FROM public.project ORDER BY CASE WHEN type = 'personal' THEN 0 ELSE 1 END, id LIMIT 1;"
    "SELECT id::text FROM public.project ORDER BY id LIMIT 1;"
    "SELECT \"id\"::text FROM public.\"project\" ORDER BY CASE WHEN \"type\" = 'personal' THEN 0 ELSE 1 END, \"id\" LIMIT 1;"
    "SELECT \"id\"::text FROM public.\"project\" ORDER BY \"id\" LIMIT 1;"
  )

  for query in "${queries[@]}"; do
    result="$(docker_exec "${N8N_POSTGRES_CONTAINER}" psql -U "${superuser}" -d n8n -Atqc "${query}" 2>/dev/null || true)"
    if [[ -n "${result}" ]]; then
      printf '%s\n' "${result}"
      return 0
    fi
  done

  return 1
}

superuser="$(detect_postgres_superuser)"

preserve_or_generate "N8N_SDR_SHARED_TOKEN"
preserve_or_generate "POSTGRES_PASSWORD"

if ! env_file_has_real_value "N8N_PROJECT_ID"; then
  project_id="$(discover_n8n_project_id "${superuser}")"
  if [[ -z "${project_id}" ]]; then
    echo "Nao foi possivel descobrir N8N_PROJECT_ID no banco n8n." >&2
    exit 1
  fi
  upsert_env_value "N8N_PROJECT_ID" "${project_id}"
fi

upsert_env_value "POSTGRES_DB" "${POSTGRES_DB}"
upsert_env_value "POSTGRES_USER" "${POSTGRES_USER}"
upsert_env_value "POSTGRES_OWNER_USER" "${POSTGRES_OWNER_USER}"
upsert_env_value "POSTGRES_HOST" "${POSTGRES_HOST}"
upsert_env_value "POSTGRES_PORT" "${POSTGRES_PORT}"
upsert_env_value "N8N_CONTAINER" "${N8N_CONTAINER}"
upsert_env_value "N8N_POSTGRES_CONTAINER" "${N8N_POSTGRES_CONTAINER}"
upsert_env_value "OPENCLAW_CONTAINER" "${OPENCLAW_CONTAINER}"
upsert_env_value "REMOTE_DEPLOY_ROOT" "${REMOTE_DEPLOY_ROOT}"
upsert_env_value "OPENCLAW_HOST_ROOT" "${OPENCLAW_HOST_ROOT}"
upsert_env_value "SDR_N8N_TOKEN" "${N8N_SDR_SHARED_TOKEN}"
upsert_env_value "OPENCLAW_PLUGIN_BASE_URL" "${OPENCLAW_PLUGIN_BASE_URL}"
upsert_env_value "OPENCLAW_PLUGIN_TIMEOUT_MS" "${OPENCLAW_PLUGIN_TIMEOUT_MS}"

chmod 600 "${ENV_FILE}"
log "Bootstrap de ambiente concluido com segredos preservados/gerados sem exposicao em log."
