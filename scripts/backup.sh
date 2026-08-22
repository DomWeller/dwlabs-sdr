#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_DB

stamp="$(date '+%Y%m%d-%H%M%S')"
backup_dir="${REMOTE_DEPLOY_ROOT}/backups/${stamp}"
mkdir -p "${backup_dir}"
restrict_permissions "${backup_dir}"

superuser="$(detect_postgres_superuser)"

if postgres_db_exists "${POSTGRES_DB}" "${superuser}"; then
  docker_exec "${N8N_POSTGRES_CONTAINER}" \
    sh -lc "pg_dump -Fc -U '${superuser}' '${POSTGRES_DB}' > '/tmp/${POSTGRES_DB}.dump'"
  docker cp "${N8N_POSTGRES_CONTAINER}:/tmp/${POSTGRES_DB}.dump" "${backup_dir}/${POSTGRES_DB}.dump"
  docker_exec "${N8N_POSTGRES_CONTAINER}" rm -f "/tmp/${POSTGRES_DB}.dump"
else
  log "Banco ${POSTGRES_DB} ainda nao existe; dump SQL inicial foi pulado."
fi

docker_exec "${N8N_CONTAINER}" sh -lc "rm -rf /tmp/dwlabs-sdr-backup && mkdir -p /tmp/dwlabs-sdr-backup && n8n export:workflow --backup --output=/tmp/dwlabs-sdr-backup >/dev/null"
docker cp "${N8N_CONTAINER}:/tmp/dwlabs-sdr-backup/." "${backup_dir}/n8n-workflows"
docker_exec "${N8N_CONTAINER}" rm -rf /tmp/dwlabs-sdr-backup

cp "${ROOT_DIR}/database/migrations/001_init.up.sql" "${backup_dir}/"
cp "${ROOT_DIR}/database/migrations/001_init.down.sql" "${backup_dir}/"
cp "${ROOT_DIR}/database/seeds/001_seed_catalog.sql" "${backup_dir}/"

if [[ -f "${OPENCLAW_HOST_ENV_FILE}" ]]; then
  cp "${OPENCLAW_HOST_ENV_FILE}" "${backup_dir}/openclaw.env"
fi

if [[ -f "${OPENCLAW_HOST_CONFIG_FILE}" ]]; then
  cp "${OPENCLAW_HOST_CONFIG_FILE}" "${backup_dir}/openclaw.json"
fi

if [[ -f "${OPENCLAW_HOST_COMPOSE_OVERRIDE}" ]]; then
  cp "${OPENCLAW_HOST_COMPOSE_OVERRIDE}" "${backup_dir}/docker-compose.override.yml"
fi

restrict_permissions "${backup_dir}"

log "Backup concluido em ${backup_dir}"
