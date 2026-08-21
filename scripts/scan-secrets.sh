#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if command -v rg >/dev/null 2>&1; then
  PATTERN='(sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----)'
  if rg -n "${PATTERN}" "${ROOT_DIR}" \
    --glob '!node_modules/**' \
    --glob '!package-lock.json' \
    --glob '!.git/**' >/dev/null; then
    echo "Padrao de segredo encontrado. Revise antes de prosseguir." >&2
    exit 1
  fi
  echo "Nenhum padrao de segredo encontrado."
  exit 0
fi

if command -v node >/dev/null 2>&1; then
  node "${ROOT_DIR}/scripts/scan-secrets.mjs" "${ROOT_DIR}"
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY' "${ROOT_DIR}"
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
pattern = re.compile(r"(sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----)")
ignore_dirs = {".git", "node_modules", "dist"}

for path in root.rglob("*"):
    if any(part in ignore_dirs for part in path.parts):
        continue
    if not path.is_file() or path.name == "package-lock.json":
        continue
    text = path.read_text(encoding="utf-8")
    for line_no, line in enumerate(text.splitlines(), start=1):
        if pattern.search(line):
            print(f"Padrao de segredo encontrado: {path.relative_to(root)}:{line_no}", file=sys.stderr)
            sys.exit(1)

print("Nenhum padrao de segredo encontrado.")
PY
  exit 0
fi

echo "Falha fechada: rg, node ou python3 sao obrigatorios para scan de segredos." >&2
exit 1
