#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

find "${ROOT_DIR}/scripts" -maxdepth 1 -type f -name '*.sh' -print0 | while IFS= read -r -d '' file; do
  bash -n "${file}"
done
