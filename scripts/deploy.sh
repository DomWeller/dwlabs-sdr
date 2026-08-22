#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime

build_release() {
  if command -v npm >/dev/null 2>&1; then
    (
      cd "${ROOT_DIR}"
      npm ci
      npm run build
    )
    return 0
  fi

  docker run --rm \
    -v "${ROOT_DIR}:/work" \
    -w /work \
    node:22-bookworm sh -lc 'npm ci && npm run build'
}

manual_public_guard
ensure_remote_layout
wait_for_container_running "${N8N_POSTGRES_CONTAINER}" 60
wait_for_container_running "${N8N_CONTAINER}" 60
wait_for_container_running "${OPENCLAW_CONTAINER}" 60

build_release
bash "${ROOT_DIR}/scripts/bootstrap-env.sh"
bash "${ROOT_DIR}/scripts/backup.sh"
bash "${ROOT_DIR}/scripts/bootstrap-database.sh"
bash "${ROOT_DIR}/scripts/migrate.sh"
bash "${ROOT_DIR}/scripts/seed.sh"
bash "${ROOT_DIR}/scripts/import-workflows.sh"
bash "${ROOT_DIR}/scripts/install-openclaw.sh"
bash "${ROOT_DIR}/scripts/healthcheck.sh"

log "Deploy preparado sem bind publico. Publique o canal apenas no gate final."
