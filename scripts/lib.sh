#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1091
    source "${ENV_FILE}"
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Comando obrigatorio ausente: ${cmd}" >&2
    exit 1
  fi
}

require_env() {
  local var_name="$1"
  local value="${!var_name:-}"
  if [[ -z "${value}" || "${value}" == "__PLACEHOLDER_ONLY__" ]]; then
    echo "Variavel obrigatoria ausente: ${var_name}" >&2
    exit 1
  fi
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

manual_public_guard() {
  local flag="${SDR_PUBLIC_FLAG:-false}"
  if [[ "${flag}" != "true" ]]; then
    log "Canal publico segue bloqueado. Defina SDR_PUBLIC_FLAG=true apenas no gate final."
  fi
}

remote_tmp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/dwlabs-sdr.XXXXXX"
}

cleanup_dir() {
  local dir_path="$1"
  if [[ -n "${dir_path}" && -d "${dir_path}" ]]; then
    rm -rf "${dir_path}"
  fi
}

docker_exec() {
  local container_name="$1"
  shift
  docker exec "${container_name}" "$@"
}

docker_exec_i() {
  local container_name="$1"
  shift
  docker exec -i "${container_name}" "$@"
}

require_runtime_defaults() {
  : "${N8N_CONTAINER:=n8n}"
  : "${N8N_POSTGRES_CONTAINER:=n8n-postgres}"
  : "${OPENCLAW_CONTAINER:=openclaw-openclaw-gateway-1}"
  : "${REMOTE_DEPLOY_ROOT:=/home/dominique/docker/dwlabs-sdr}"
  : "${OPENCLAW_HOST_ROOT:=/home/dominique/docker/openclaw}"
  : "${OPENCLAW_HOST_ENV_FILE:=${OPENCLAW_HOST_ROOT}/.env}"
  : "${OPENCLAW_HOST_CONFIG_FILE:=${OPENCLAW_HOST_ROOT}/data/config/openclaw.json}"
  : "${OPENCLAW_HOST_COMPOSE_OVERRIDE:=${OPENCLAW_HOST_ROOT}/docker-compose.override.yml}"
  : "${OPENCLAW_PLUGIN_WORKSPACE_ROOT:=${OPENCLAW_HOST_ROOT}/data/config/workspace-comercial}"
  : "${OPENCLAW_PLUGIN_BASE_URL:=http://100.94.57.43:5678/webhook}"
  : "${OPENCLAW_PLUGIN_TIMEOUT_MS:=8000}"
  : "${POSTGRES_DB:=dwlabs_sdr}"
  : "${POSTGRES_USER:=dwlabs_sdr_app}"
  : "${POSTGRES_OWNER_USER:=dwlabs_sdr_owner}"
  : "${POSTGRES_ADMIN_USER:=dwlabs_sdr_admin}"
  : "${POSTGRES_DISPATCHER_USER:=dwlabs_sdr_dispatcher}"
  : "${POSTGRES_HOST:=postgres}"
  : "${POSTGRES_PORT:=5432}"
  : "${N8N_BASE_URL:=http://127.0.0.1:5678}"
  : "${SDR_BIND_WHATSAPP:=false}"
  : "${SDR_AGENT_ID:=comercial}"
}

require_remote_runtime() {
  require_cmd docker
  require_runtime_defaults
}

copy_into_container() {
  local source_path="$1"
  local container_name="$2"
  local target_path="$3"
  docker cp "${source_path}" "${container_name}:${target_path}"
}

ensure_remote_layout() {
  mkdir -p "${REMOTE_DEPLOY_ROOT}/backups"
  mkdir -p "${REMOTE_DEPLOY_ROOT}/imports"
  mkdir -p "${REMOTE_DEPLOY_ROOT}/exports"
}

ensure_env_file() {
  touch "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
}

env_file_get() {
  local key="$1"
  if [[ ! -f "${ENV_FILE}" ]]; then
    return 1
  fi

  awk -F= -v key="${key}" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      print value
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "${ENV_FILE}"
}

env_file_has_real_value() {
  local key="$1"
  local value
  value="$(env_file_get "${key}" 2>/dev/null || true)"
  [[ -n "${value}" && "${value}" != "__PLACEHOLDER_ONLY__" ]]
}

upsert_env_value() {
  local key="$1"
  local value="$2"

  ensure_env_file

  if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    perl -0pi -e "s#^\\Q${key}\\E=.*\$#${key}=${value}#m" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi

  chmod 600 "${ENV_FILE}"
}

docker_env_value() {
  local container_name="$1"
  local key="$2"

  docker inspect "${container_name}" \
    --format '{{range .Config.Env}}{{println .}}{{end}}' |
    awk -F= -v key="${key}" '$1 == key { print substr($0, index($0, "=") + 1); exit }'
}

detect_postgres_superuser() {
  local candidate
  for candidate in POSTGRES_USER POSTGRESQL_USERNAME PGUSER; do
    local value
    value="$(docker_env_value "${N8N_POSTGRES_CONTAINER}" "${candidate}" || true)"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done

  printf 'postgres\n'
}

generate_secret_hex() {
  docker_exec "${N8N_POSTGRES_CONTAINER}" sh -lc "od -An -N32 -tx1 /dev/urandom | tr -d ' \n'"
}

escape_sql_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

postgres_db_exists() {
  local db_name="$1"
  local superuser="${2:-$(detect_postgres_superuser)}"
  local result
  result="$(
    docker_exec "${N8N_POSTGRES_CONTAINER}" \
      psql -v ON_ERROR_STOP=1 -U "${superuser}" -d postgres -Atqc \
      "SELECT 1 FROM pg_database WHERE datname = '$(escape_sql_literal "${db_name}")' LIMIT 1;"
  )"
  [[ "${result}" == "1" ]]
}

postgres_query() {
  local db_name="$1"
  local sql="$2"
  local superuser="${3:-$(detect_postgres_superuser)}"

  docker_exec "${N8N_POSTGRES_CONTAINER}" \
    psql -v ON_ERROR_STOP=1 -U "${superuser}" -d "${db_name}" -Atqc "${sql}"
}

postgres_query_file_as_owner() {
  local db_name="$1"
  local owner_role="$2"
  local sql_file="$3"
  local superuser="${4:-$(detect_postgres_superuser)}"

  {
    printf 'SET ROLE "%s";\n' "${owner_role}"
    cat "${sql_file}"
  } | docker_exec_i "${N8N_POSTGRES_CONTAINER}" \
    psql -v ON_ERROR_STOP=1 -U "${superuser}" -d "${db_name}" >/dev/null
}

apply_database_grants() {
  local superuser="${1:-$(detect_postgres_superuser)}"
  local owner_role="${POSTGRES_OWNER_USER}"
  local app_role="${POSTGRES_USER}"
  local sql

  sql=$(cat <<SQL
REVOKE ALL ON DATABASE "${POSTGRES_DB}" FROM PUBLIC;
GRANT CONNECT, TEMP ON DATABASE "${POSTGRES_DB}" TO "${app_role}";

DO \$\$
DECLARE
  target_schema TEXT;
BEGIN
  FOR target_schema IN SELECT unnest(ARRAY['core', 'rag', 'ops', 'audit', 'api'])
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.schemata s WHERE s.schema_name = target_schema) THEN
      EXECUTE format('ALTER SCHEMA %I OWNER TO %I', target_schema, '${owner_role}');
      EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', target_schema, '${app_role}');
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO %I', target_schema, '${app_role}');
      EXECUTE format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA %I TO %I', target_schema, '${app_role}');
      EXECUTE format('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA %I TO %I', target_schema, '${app_role}');
      EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', '${owner_role}', target_schema, '${app_role}');
      EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT USAGE, SELECT ON SEQUENCES TO %I', '${owner_role}', target_schema, '${app_role}');
      EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT EXECUTE ON FUNCTIONS TO %I', '${owner_role}', target_schema, '${app_role}');
    END IF;
  END LOOP;
END
\$\$;
SQL
)

  postgres_query "${POSTGRES_DB}" "${sql}" "${superuser}" >/dev/null
}

apply_specialized_database_grants() {
  local superuser="${1:-$(detect_postgres_superuser)}"
  local sql
  sql=$(cat <<SQL
GRANT CONNECT ON DATABASE "${POSTGRES_DB}" TO "${POSTGRES_ADMIN_USER}", "${POSTGRES_DISPATCHER_USER}";
GRANT USAGE ON SCHEMA core, rag, ops, audit TO "${POSTGRES_ADMIN_USER}";
GRANT SELECT ON ALL TABLES IN SCHEMA core, rag, ops, audit TO "${POSTGRES_ADMIN_USER}";
GRANT UPDATE ON core.services, core.handoffs, ops.runtime_flags TO "${POSTGRES_ADMIN_USER}";
GRANT INSERT ON audit.admin_change_log TO "${POSTGRES_ADMIN_USER}";
GRANT USAGE ON SCHEMA ops TO "${POSTGRES_DISPATCHER_USER}";
REVOKE ALL ON ALL TABLES IN SCHEMA core, rag, ops, audit FROM "${POSTGRES_DISPATCHER_USER}";
GRANT SELECT ON ops.runtime_flags TO "${POSTGRES_DISPATCHER_USER}";
REVOKE ALL ON FUNCTION ops.enqueue_due_followups(TEXT,BOOLEAN), ops.claim_delivery(TEXT), ops.delivery_is_sendable(UUID), ops.complete_delivery(UUID,TEXT), ops.fail_delivery(UUID,TEXT) FROM PUBLIC, "${POSTGRES_USER}", "${POSTGRES_ADMIN_USER}";
GRANT EXECUTE ON FUNCTION ops.enqueue_due_followups(TEXT,BOOLEAN), ops.claim_delivery(TEXT), ops.delivery_is_sendable(UUID), ops.complete_delivery(UUID,TEXT), ops.fail_delivery(UUID,TEXT) TO "${POSTGRES_DISPATCHER_USER}";
SQL
)
  postgres_query "${POSTGRES_DB}" "${sql}" "${superuser}" >/dev/null
}

restrict_permissions() {
  local target_path="$1"
  if [[ -d "${target_path}" ]]; then
    chmod 700 "${target_path}"
    find "${target_path}" -type d -exec chmod 700 {} +
    find "${target_path}" -type f -exec chmod 600 {} +
  elif [[ -f "${target_path}" ]]; then
    chmod 600 "${target_path}"
  fi
}

wait_for_container_running() {
  local container_name="$1"
  local timeout_seconds="${2:-60}"
  local start_epoch
  start_epoch="$(date +%s)"

  while true; do
    local status
    status="$(docker inspect --format '{{.State.Status}}' "${container_name}" 2>/dev/null || true)"
    if [[ "${status}" == "running" ]]; then
      return 0
    fi
    if (( "$(date +%s)" - start_epoch >= timeout_seconds )); then
      echo "Container nao entrou em execucao: ${container_name}" >&2
      return 1
    fi
    sleep 2
  done
}

wait_for_container_health() {
  local container_name="$1"
  local timeout_seconds="${2:-120}"
  local start_epoch
  start_epoch="$(date +%s)"

  while true; do
    local health_status
    health_status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container_name}" 2>/dev/null || true)"
    if [[ "${health_status}" == "healthy" || "${health_status}" == "running" ]]; then
      return 0
    fi
    if (( "$(date +%s)" - start_epoch >= timeout_seconds )); then
      echo "Container nao ficou saudavel: ${container_name}" >&2
      return 1
    fi
    sleep 3
  done
}

wait_for_n8n_ready() {
  local timeout_seconds="${1:-120}"
  local base_url="${N8N_BASE_URL%/}"
  local start_epoch
  start_epoch="$(date +%s)"

  while true; do
    if docker_exec "${N8N_CONTAINER}" node -e "
      const url = process.argv[1];
      fetch(url, { redirect: 'manual' })
        .then((response) => process.exit(response.status < 500 ? 0 : 1))
        .catch(() => process.exit(1));
    " "${base_url}/healthz" >/dev/null 2>&1; then
      return 0
    fi

    if (( "$(date +%s)" - start_epoch >= timeout_seconds )); then
      echo "n8n nao respondeu em ${base_url}" >&2
      return 1
    fi
    sleep 3
  done
}

json_string_from_file() {
  local json_file="$1"
  local key="$2"
  sed -n "s/.*\"${key}\": \"\\([^\"]*\\)\".*/\\1/p" "${json_file}" | head -n 1
}

workflow_json_files() {
  find "${ROOT_DIR}/workflows" -type f -name '*.json' | sort
}

active_workflow_json_files() {
  find "${ROOT_DIR}/workflows/public-tools" -type f -name '*.json' | sort
  find "${ROOT_DIR}/workflows/subworkflows" -type f -name '*.json' | sort
  printf '%s\n' "${ROOT_DIR}/workflows/schedulers/sdr.health.selfcheck.json"
}

optional_scheduler_json_files() {
  printf '%s\n' \
    "${ROOT_DIR}/workflows/schedulers/sdr.followup.scheduler.json" \
    "${ROOT_DIR}/workflows/schedulers/sdr.sheets.sync.scheduler.json"
}
