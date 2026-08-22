#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_DB
require_env POSTGRES_OWNER_USER

manual_public_guard

while IFS= read -r workflow_file; do
  workflow_id="$(json_string_from_file "${workflow_file}" "id")"
  docker_exec "${N8N_CONTAINER}" n8n unpublish:workflow --id="${workflow_id}" >/dev/null || true
done < <(workflow_json_files)

if [[ "${ROLLBACK_REMOVE_BINDING:-false}" == "true" ]]; then
  docker_exec "${OPENCLAW_CONTAINER}" openclaw agents unbind --agent "${SDR_AGENT_ID}" --bind "${SDR_WHATSAPP_BINDING:-whatsapp}" >/dev/null || true
fi

if [[ "${ROLLBACK_REMOVE_AGENT:-false}" == "true" ]]; then
  docker_exec "${OPENCLAW_CONTAINER}" openclaw agents delete "${SDR_AGENT_ID}" >/dev/null || true
fi

if [[ "${ROLLBACK_REMOVE_PLUGIN:-false}" == "true" ]]; then
  docker_exec "${OPENCLAW_CONTAINER}" openclaw plugins uninstall dwlabs-sdr-tools --force >/dev/null || true
fi

if [[ -n "${ROLLBACK_RESTORE_DUMP:-}" ]]; then
  if [[ ! -f "${ROLLBACK_RESTORE_DUMP}" ]]; then
    echo "Dump solicitado para restore nao existe: ${ROLLBACK_RESTORE_DUMP}" >&2
    exit 1
  fi

  superuser="$(detect_postgres_superuser)"
  docker cp "${ROLLBACK_RESTORE_DUMP}" "${N8N_POSTGRES_CONTAINER}:/tmp/restore.dump"
  docker_exec "${N8N_POSTGRES_CONTAINER}" sh -lc "dropdb -U '${superuser}' --if-exists '${POSTGRES_DB}' && createdb -U '${superuser}' -O '${POSTGRES_OWNER_USER}' '${POSTGRES_DB}'"
  docker_exec "${N8N_POSTGRES_CONTAINER}" sh -lc "pg_restore -U '${superuser}' -d '${POSTGRES_DB}' /tmp/restore.dump"
  docker_exec "${N8N_POSTGRES_CONTAINER}" rm -f /tmp/restore.dump
fi

log "Rollback seletivo concluido."
