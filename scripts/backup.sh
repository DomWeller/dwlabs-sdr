#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env

STAMP="$(date '+%Y%m%d-%H%M%S')"
TARGET_DIR="${ROOT_DIR}/database/backups/${STAMP}"

mkdir -p "${TARGET_DIR}"
cp -f "${ROOT_DIR}/database/migrations/001_init.up.sql" "${TARGET_DIR}/"
cp -f "${ROOT_DIR}/database/migrations/001_init.down.sql" "${TARGET_DIR}/"
cp -f "${ROOT_DIR}/database/seeds/001_seed_catalog.sql" "${TARGET_DIR}/"

log "Backup local versionavel gerado em ${TARGET_DIR}"
manual_public_guard
