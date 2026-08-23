#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env SDR_OWNER_ALLOWLIST

escaped_phone="$(escape_sql_literal "${SDR_OWNER_ALLOWLIST}")"
postgres_query "${POSTGRES_DB}" "SELECT ops.enqueue_due_followups('${escaped_phone}', TRUE);"

