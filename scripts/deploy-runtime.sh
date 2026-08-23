#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_PASSWORD

ensure_env_file
if ! env_file_has_real_value ADMIN_SESSION_SECRET; then
  upsert_env_value ADMIN_SESSION_SECRET "$(generate_secret_hex)$(generate_secret_hex)"
fi

if ! env_file_has_real_value ADMIN_PASSWORD_HASH; then
  initial_password="$(docker run --rm node:22-bookworm sh -lc "od -An -N18 -tx1 /dev/urandom | tr -d ' \n'")"
  printf '%s\n' "${initial_password}" > "${ROOT_DIR}/.admin-initial-password"
  chmod 600 "${ROOT_DIR}/.admin-initial-password"
  admin_hash="$(docker run --rm -v "${ROOT_DIR}:/app:ro" -w /app node:22-bookworm node scripts/hash-admin-password.mjs "${initial_password}")"
  upsert_env_value ADMIN_PASSWORD_HASH "${admin_hash}"
  log "Senha inicial do painel guardada em ${ROOT_DIR}/.admin-initial-password (chmod 600)."
fi

if ! env_file_has_real_value OPENCLAW_GATEWAY_TOKEN; then
  gateway_token="$(docker inspect "${OPENCLAW_CONTAINER}" --format '{{range .Config.Env}}{{println .}}{{end}}' | awk -F= '$1=="OPENCLAW_GATEWAY_TOKEN" {print substr($0,index($0,"=")+1); exit}')"
  [[ -n "${gateway_token}" ]] || { echo "OPENCLAW_GATEWAY_TOKEN nao encontrado no container." >&2; exit 1; }
  upsert_env_value OPENCLAW_GATEWAY_TOKEN "${gateway_token}"
fi

docker compose --env-file "${ROOT_DIR}/.env" -f "${ROOT_DIR}/deploy/docker-compose.sdr.yml" build
docker compose --env-file "${ROOT_DIR}/.env" -f "${ROOT_DIR}/deploy/docker-compose.sdr.yml" up -d admin dispatcher

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:5680/healthz >/dev/null 2>&1; then
    log "Painel e dispatcher iniciados; automacoes permanecem desligadas por runtime flag."
    exit 0
  fi
  sleep 2
done

echo "Painel nao ficou pronto em 60 segundos." >&2
exit 1

