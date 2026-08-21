#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

EXPORT_DIR="${ROOT_DIR}/workflows/exported-snapshot"
mkdir -p "${EXPORT_DIR}"
log "Comando sugerido para export local do n8n:"
echo "n8n export:workflow --all --pretty --separate --output=${EXPORT_DIR}"
