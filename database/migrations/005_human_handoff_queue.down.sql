BEGIN;

DROP INDEX IF EXISTS core.uq_handoffs_one_active_per_lead;

CREATE OR REPLACE FUNCTION api.buscar_lead(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  target_lead_id UUID;
  response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'lead_id', '') IS NULL
     AND NULLIF(payload ->> 'phone', '') IS NULL
     AND NULLIF(payload ->> 'email', '') IS NULL THEN
    RETURN ops.wrap_error('LEAD_LOOKUP_REQUIRED', 'Informe lead_id, phone ou email.', FALSE);
  END IF;

  SELECT l.lead_id INTO target_lead_id
  FROM core.leads l JOIN core.contacts c ON c.contact_id = l.contact_id
  WHERE (NULLIF(payload ->> 'lead_id', '') IS NOT NULL AND l.lead_id::TEXT = payload ->> 'lead_id')
     OR (NULLIF(payload ->> 'phone', '') IS NOT NULL AND c.normalized_phone = ops.normalize_phone(payload ->> 'phone'))
     OR (NULLIF(payload ->> 'email', '') IS NOT NULL AND c.email = lower(NULLIF(payload ->> 'email', '')))
  LIMIT 1;

  IF target_lead_id IS NULL THEN
    RETURN ops.wrap_error('LEAD_NOT_FOUND', 'Lead nao encontrado.', FALSE);
  END IF;
  IF NOT ops.is_lead_in_actor_scope(payload, target_lead_id) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  SELECT ops.wrap_success(jsonb_build_object('lead', jsonb_build_object(
    'lead_id', l.lead_id,
    'stage', l.stage,
    'score', l.score,
    'temperature_band', l.temperature_band,
    'needs', COALESCE(string_to_array(l.needs_summary, '; '), ARRAY[]::TEXT[])
  ))) INTO response_value
  FROM core.leads l WHERE l.lead_id = target_lead_id;
  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.transferir_humano(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  handoff_row core.handoffs%ROWTYPE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;
  IF NOT ops.is_lead_in_actor_scope(payload, (payload ->> 'lead_id')::UUID) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox
  WHERE idempotency_key = payload ->> 'idempotency_key' FOR UPDATE;
  IF idempotency_row.inbox_id IS NOT NULL THEN
    IF idempotency_row.payload_hash <> payload_hash_value THEN
      RETURN ops.wrap_error('IDEMPOTENCY_HASH_MISMATCH', 'Mesmo idempotency_key com payload diferente.', FALSE);
    END IF;
    IF idempotency_row.completed_at IS NOT NULL THEN
      UPDATE ops.idempotency_inbox SET replay_count = replay_count + 1 WHERE inbox_id = idempotency_row.inbox_id;
      RETURN idempotency_row.response_payload;
    END IF;
  ELSE
    INSERT INTO ops.idempotency_inbox (source_system, external_event_id, tool_name, idempotency_key, payload_hash, request_envelope)
    VALUES ('openclaw', COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'), 'transferir_humano', payload ->> 'idempotency_key', payload_hash_value, payload)
    RETURNING * INTO idempotency_row;
  END IF;

  INSERT INTO core.handoffs (lead_id, reason, priority, status)
  VALUES ((payload ->> 'lead_id')::UUID, payload ->> 'reason', payload ->> 'priority', 'open')
  RETURNING * INTO handoff_row;
  UPDATE core.followups SET status = 'stopped', stop_reason = 'handoff', updated_at = NOW()
  WHERE lead_id = handoff_row.lead_id AND status = 'scheduled';
  response_value := ops.wrap_success(jsonb_build_object('handoff_id', handoff_row.handoff_id, 'blocked_automation', TRUE));
  UPDATE ops.idempotency_inbox SET response_payload = response_value, completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;
  RETURN response_value;
END
$$;

ALTER TABLE core.handoffs DROP COLUMN IF EXISTS resolution_note;
ALTER TABLE core.handoffs DROP COLUMN IF EXISTS closed_at;
ALTER TABLE core.handoffs DROP COLUMN IF EXISTS acknowledged_at;
ALTER TABLE core.handoffs DROP COLUMN IF EXISTS assigned_to;

COMMIT;
