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

tmp_dir="$(remote_tmp_dir)"
container_tmp="/tmp/dwlabs-sdr-import"
trap 'cleanup_dir "${tmp_dir}"' EXIT

manual_public_guard
ensure_remote_layout

node "${ROOT_DIR}/scripts/render-n8n-credentials.mjs" "${tmp_dir}/credentials" >/dev/null
cp -R "${ROOT_DIR}/workflows" "${tmp_dir}/workflows"

docker_exec "${N8N_CONTAINER}" sh -lc "rm -rf '${container_tmp}' && mkdir -p '${container_tmp}'"
copy_into_container "${tmp_dir}/credentials" "${N8N_CONTAINER}" "${container_tmp}/credentials"
copy_into_container "${tmp_dir}/workflows/public-tools" "${N8N_CONTAINER}" "${container_tmp}/public-tools"
copy_into_container "${tmp_dir}/workflows/subworkflows" "${N8N_CONTAINER}" "${container_tmp}/subworkflows"
copy_into_container "${tmp_dir}/workflows/schedulers" "${N8N_CONTAINER}" "${container_tmp}/schedulers"

log "Importando credenciais transitórias do n8n"
docker_exec "${N8N_CONTAINER}" n8n import:credentials \
  --separate \
  --input="${container_tmp}/credentials" \
  --projectId="${N8N_PROJECT_ID}" \
  --include=id,name,type,data >/dev/null

log "Importando workflows SDR desativados"
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

docker_exec "${N8N_CONTAINER}" sh -lc "rm -rf '${container_tmp}'"
log "Importacao concluida."
