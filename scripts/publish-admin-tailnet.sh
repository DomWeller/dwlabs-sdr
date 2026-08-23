#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env

require_cmd tailscale
curl -fsS http://127.0.0.1:5680/healthz >/dev/null
if tailscale serve status | grep -q ':8445'; then
  log "Tailscale Serve :8445 ja esta configurado."
  exit 0
fi
tailscale serve --bg --yes --https=8445 http://127.0.0.1:5680
log "Painel publicado somente no tailnet pela porta HTTPS 8445."
