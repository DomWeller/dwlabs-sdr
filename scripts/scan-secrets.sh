#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATTERN='(sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----)'

if rg -n "${PATTERN}" "${ROOT_DIR}" \
  --glob '!node_modules/**' \
  --glob '!package-lock.json' \
  --glob '!.git/**' >/dev/null; then
  echo "Padrao de segredo encontrado. Revise antes de prosseguir." >&2
  exit 1
fi

echo "Nenhum padrao de segredo encontrado."
