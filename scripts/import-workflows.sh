#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env N8N_PROJECT_ID
require_env N8N_SDR_SHARED_TOKEN
require_env POSTGRES_HOST
require_env POSTGRES_DB
require_env POSTGRES_USER
require_env POSTGRES_PASSWORD

if [[ "${N8N_SDR_HEADER_AUTH_ID:-DWLABS_SDR_HEADER_AUTH}" != "DWLABS_SDR_HEADER_AUTH" ]]; then
  echo "N8N_SDR_HEADER_AUTH_ID deve permanecer DWLABS_SDR_HEADER_AUTH nesta versao." >&2
  exit 1
fi

if [[ "${N8N_WORKFLOW_PG_CREDENTIAL_ID:-DWLABS_SDR_POSTGRES_ID}" != "DWLABS_SDR_POSTGRES_ID" ]]; then
  echo "N8N_WORKFLOW_PG_CREDENTIAL_ID deve permanecer DWLABS_SDR_POSTGRES_ID nesta versao." >&2
  exit 1
fi

tmp_dir="$(remote_tmp_dir)"
container_tmp="/tmp/dwlabs-sdr-import"
trap 'cleanup_dir "${tmp_dir}"' EXIT

manual_public_guard
ensure_remote_layout

mkdir -p "${tmp_dir}/credentials"
mkdir -p "${tmp_dir}/workflows"

cat > "${tmp_dir}/credentials/${N8N_SDR_HEADER_AUTH_ID:-DWLABS_SDR_HEADER_AUTH}.json" <<JSON
{
  "id": "${N8N_SDR_HEADER_AUTH_ID:-DWLABS_SDR_HEADER_AUTH}",
  "name": "${N8N_SDR_HEADER_AUTH_NAME:-DWLabs SDR Header Auth}",
  "type": "httpHeaderAuth",
  "data": {
    "name": "Authorization",
    "value": "Bearer ${N8N_SDR_SHARED_TOKEN}"
  }
}
JSON

cat > "${tmp_dir}/credentials/${N8N_WORKFLOW_PG_CREDENTIAL_ID:-DWLABS_SDR_POSTGRES_ID}.json" <<JSON
{
  "id": "${N8N_WORKFLOW_PG_CREDENTIAL_ID:-DWLABS_SDR_POSTGRES_ID}",
  "name": "${N8N_WORKFLOW_PG_CREDENTIAL_NAME:-DWLabs SDR Postgres}",
  "type": "postgres",
  "data": {
    "host": "${POSTGRES_HOST}",
    "port": ${POSTGRES_PORT:-5432},
    "database": "${POSTGRES_DB}",
    "user": "${POSTGRES_USER}",
    "password": "${POSTGRES_PASSWORD}",
    "ssl": "disable"
  }
}
JSON

cp -R "${ROOT_DIR}/workflows/." "${tmp_dir}/workflows/"

docker_exec "${N8N_CONTAINER}" sh -lc "rm -rf '${container_tmp}' && mkdir -p '${container_tmp}'"
copy_into_container "${tmp_dir}/credentials" "${N8N_CONTAINER}" "${container_tmp}/credentials"
copy_into_container "${tmp_dir}/workflows/public-tools" "${N8N_CONTAINER}" "${container_tmp}/public-tools"
copy_into_container "${tmp_dir}/workflows/subworkflows" "${N8N_CONTAINER}" "${container_tmp}/subworkflows"
copy_into_container "${tmp_dir}/workflows/schedulers" "${N8N_CONTAINER}" "${container_tmp}/schedulers"
copy_into_container "${tmp_dir}/workflows/internal" "${N8N_CONTAINER}" "${container_tmp}/internal"

log "Importando credenciais n8n com IDs fixos"
docker_exec "${N8N_CONTAINER}" n8n import:credentials \
  --separate \
  --input="${container_tmp}/credentials" \
  --projectId="${N8N_PROJECT_ID}" \
  --include=id,name,type,data >/dev/null

log "Importando workflows SDR"
docker_exec "${N8N_CONTAINER}" n8n import:workflow \
  --separate \
  --input="${container_tmp}/public-tools" \
  --projectId="${N8N_PROJECT_ID}" \
  --activeState=false >/dev/null
docker_exec "${N8N_CONTAINER}" n8n import:workflow \
  --separate \
  --input="${container_tmp}/subworkflows" \
  --projectId="${N8N_PROJECT_ID}" \
  --activeState=false >/dev/null
docker_exec "${N8N_CONTAINER}" n8n import:workflow \
  --separate \
  --input="${container_tmp}/schedulers" \
  --projectId="${N8N_PROJECT_ID}" \
  --activeState=false >/dev/null
docker_exec "${N8N_CONTAINER}" n8n import:workflow \
  --separate \
  --input="${container_tmp}/internal" \
  --projectId="${N8N_PROJECT_ID}" \
  --activeState=false >/dev/null

publish_workflow_file() {
  local workflow_file="$1"
  local workflow_id
  local workflow_name

  workflow_id="$(json_string_from_file "${workflow_file}" "id")"
  workflow_name="$(json_string_from_file "${workflow_file}" "name")"
  if [[ -z "${workflow_id}" || -z "${workflow_name}" ]]; then
    echo "Workflow sem id ou nome: ${workflow_file}" >&2
    exit 1
  fi
  docker_exec "${N8N_CONTAINER}" n8n publish:workflow --id="${workflow_id}" >/dev/null
}

unpublish_workflow_file() {
  local workflow_file="$1"
  local workflow_id

  workflow_id="$(json_string_from_file "${workflow_file}" "id")"
  if [[ -z "${workflow_id}" ]]; then
    echo "Workflow sem id: ${workflow_file}" >&2
    exit 1
  fi
  docker_exec "${N8N_CONTAINER}" n8n unpublish:workflow --id="${workflow_id}" >/dev/null
}

while IFS= read -r workflow_file; do
  publish_workflow_file "${workflow_file}"
done < <(active_workflow_json_files)

while IFS= read -r workflow_file; do
  unpublish_workflow_file "${workflow_file}"
done < <(optional_scheduler_json_files)

docker_exec "${N8N_CONTAINER}" sh -lc "rm -rf '${container_tmp}'"

log "Reiniciando n8n para consolidar importacao/publicacao"
docker restart "${N8N_CONTAINER}" >/dev/null
wait_for_container_health "${N8N_CONTAINER}" 120
wait_for_n8n_ready 120

log "Importacao, publicacao e restart do n8n concluidos."
