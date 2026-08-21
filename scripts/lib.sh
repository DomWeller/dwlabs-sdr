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

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

manual_public_guard() {
  local flag="${SDR_PUBLIC_FLAG:-false}"
  if [[ "${flag}" != "true" ]]; then
    log "Canal publico segue bloqueado. Defina SDR_PUBLIC_FLAG=true apenas no gate final."
  fi
}
