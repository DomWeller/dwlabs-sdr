#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime

stamp="$(date '+%Y%m%d-%H%M%S')"
tmp_dir="$(remote_tmp_dir)"
trap 'cleanup_dir "${tmp_dir}"' EXIT

docker_exec "${N8N_CONTAINER}" sh -lc "rm -rf /tmp/dwlabs-sdr-export && mkdir -p /tmp/dwlabs-sdr-export"
docker_exec "${N8N_CONTAINER}" n8n export:workflow --all --pretty --separate --output=/tmp/dwlabs-sdr-export >/dev/null
docker cp "${N8N_CONTAINER}:/tmp/dwlabs-sdr-export/." "${tmp_dir}/"
mkdir -p "${ROOT_DIR}/workflows/exported-snapshot/${stamp}"
cp -R "${tmp_dir}/." "${ROOT_DIR}/workflows/exported-snapshot/${stamp}/"
docker_exec "${N8N_CONTAINER}" sh -lc "rm -rf /tmp/dwlabs-sdr-export"
log "Export concluido em ${ROOT_DIR}/workflows/exported-snapshot/${stamp}"
