#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env() {
  if [[ -f "${ROOT_DIR}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/.env"
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
}

require_remote_runtime() {
  require_cmd docker
  require_cmd node
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
