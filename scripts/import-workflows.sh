#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env

WORKFLOW_DIR="${ROOT_DIR}/workflows"
log "Importe os workflows desativados com:"
echo "n8n import:workflow --separate --input=${WORKFLOW_DIR}/public-tools --active=false"
echo "n8n import:workflow --separate --input=${WORKFLOW_DIR}/subworkflows --active=false"
echo "n8n import:workflow --separate --input=${WORKFLOW_DIR}/schedulers --active=false"
