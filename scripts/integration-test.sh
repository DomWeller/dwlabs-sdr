#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_env
require_remote_runtime
require_env POSTGRES_DB
require_env N8N_SDR_SHARED_TOKEN

manual_public_guard

run_id="${DWL_SDR_INTEGRATION_RUN_ID:-it-$(date -u '+%Y%m%d%H%M%S')-$$}"
if [[ ! "${run_id}" =~ ^[A-Za-z0-9-]+$ ]]; then
  echo "DWL_SDR_INTEGRATION_RUN_ID aceita apenas letras, numeros e hifen." >&2
  exit 1
fi

email_a="codex-${run_id}-a@example.invalid"
email_b="codex-${run_id}-b@example.invalid"
company_a="codex integration ${run_id} a"
company_b="codex integration ${run_id} b"
remote_script="/tmp/dwlabs-sdr-integration-${run_id}.mjs"
cleanup_complete=false

cleanup_test_data() {
  if [[ "${cleanup_complete}" == "true" ]]; then
    return 0
  fi

  local escaped_run_id
  local escaped_email_a
  local escaped_email_b
  local escaped_company_a
  local escaped_company_b
  escaped_run_id="$(escape_sql_literal "${run_id}")"
  escaped_email_a="$(escape_sql_literal "${email_a}")"
  escaped_email_b="$(escape_sql_literal "${email_b}")"
  escaped_company_a="$(escape_sql_literal "${company_a}")"
  escaped_company_b="$(escape_sql_literal "${company_b}")"

  postgres_query "${POSTGRES_DB}" "
    BEGIN;
    CREATE TEMP TABLE integration_test_leads ON COMMIT DROP AS
      SELECT l.lead_id
      FROM core.leads l
      JOIN core.contacts c ON c.contact_id = l.contact_id
      WHERE c.email IN ('${escaped_email_a}', '${escaped_email_b}');
    DELETE FROM audit.redacted_event_log
      WHERE lead_id IN (SELECT lead_id FROM integration_test_leads);
    DELETE FROM core.contacts
      WHERE email IN ('${escaped_email_a}', '${escaped_email_b}');
    DELETE FROM core.companies
      WHERE normalized_name IN ('${escaped_company_a}', '${escaped_company_b}');
    DELETE FROM ops.idempotency_inbox
      WHERE idempotency_key LIKE '${escaped_run_id}-%';
    COMMIT;
  " >/dev/null

  docker_exec "${N8N_CONTAINER}" rm -f "${remote_script}" >/dev/null 2>&1 || true
  cleanup_complete=true
}

trap cleanup_test_data EXIT INT TERM

existing_rows="$(postgres_query "${POSTGRES_DB}" "
  SELECT count(*)
  FROM core.contacts
  WHERE email IN ('$(escape_sql_literal "${email_a}")', '$(escape_sql_literal "${email_b}")');
")"
if [[ "${existing_rows}" != "0" ]]; then
  echo "Dados de um run_id anterior ainda existem; limpeza manual necessaria para ${run_id}." >&2
  exit 1
fi

docker cp "${ROOT_DIR}/tests/remote-integration.mjs" "${N8N_CONTAINER}:${remote_script}" >/dev/null
printf '%s' "${N8N_SDR_SHARED_TOKEN}" |
  docker_exec_i "${N8N_CONTAINER}" node "${remote_script}" "${N8N_BASE_URL%/}/webhook" "${run_id}"

database_state="$(postgres_query "${POSTGRES_DB}" "
  WITH test_contacts AS (
    SELECT contact_id FROM core.contacts
    WHERE email IN ('$(escape_sql_literal "${email_a}")', '$(escape_sql_literal "${email_b}")')
  ), test_leads AS (
    SELECT lead_id FROM core.leads WHERE contact_id IN (SELECT contact_id FROM test_contacts)
  )
  SELECT concat_ws('|',
    (SELECT count(*) FROM test_contacts),
    (SELECT count(*) FROM test_leads),
    (SELECT count(*) FROM audit.redacted_event_log WHERE lead_id IN (SELECT lead_id FROM test_leads)),
    (SELECT count(*) FROM ops.idempotency_inbox WHERE idempotency_key LIKE '$(escape_sql_literal "${run_id}")-%'),
    (SELECT replay_count FROM ops.idempotency_inbox WHERE idempotency_key = '$(escape_sql_literal "${run_id}")-save-a')
  );
")"

IFS='|' read -r contacts_count leads_count audit_count idempotency_count replay_count <<<"${database_state}"
[[ "${contacts_count}" == "2" ]]
[[ "${leads_count}" == "2" ]]
[[ "${audit_count}" -ge "3" ]]
[[ "${idempotency_count}" == "7" ]]
[[ "${replay_count}" == "1" ]]

cleanup_test_data
trap - EXIT INT TERM

remaining_rows="$(postgres_query "${POSTGRES_DB}" "
  SELECT
    (SELECT count(*) FROM core.contacts WHERE email IN ('$(escape_sql_literal "${email_a}")', '$(escape_sql_literal "${email_b}")'))
    + (SELECT count(*) FROM core.companies WHERE normalized_name IN ('$(escape_sql_literal "${company_a}")', '$(escape_sql_literal "${company_b}")'))
    + (SELECT count(*) FROM ops.idempotency_inbox WHERE idempotency_key LIKE '$(escape_sql_literal "${run_id}")-%');
")"
[[ "${remaining_rows}" == "0" ]]

log "Integracao real concluida: 22 ferramentas, idempotencia, isolamento e limpeza controlada."
