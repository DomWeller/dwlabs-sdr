BEGIN;

ALTER TABLE core.handoffs ADD COLUMN IF NOT EXISTS assigned_to TEXT;
ALTER TABLE core.handoffs ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;
ALTER TABLE core.handoffs ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;
ALTER TABLE core.handoffs ADD COLUMN IF NOT EXISTS resolution_note TEXT;

WITH ranked AS (
  SELECT handoff_id,
         row_number() OVER (PARTITION BY lead_id ORDER BY created_at DESC, handoff_id DESC) AS position
  FROM core.handoffs
  WHERE status IN ('open', 'acknowledged')
)
UPDATE core.handoffs handoff
SET status = 'closed',
    closed_at = COALESCE(handoff.closed_at, NOW()),
    resolution_note = COALESCE(handoff.resolution_note, 'Consolidado pela migration 005.'),
    updated_at = NOW()
FROM ranked
WHERE handoff.handoff_id = ranked.handoff_id
  AND ranked.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_handoffs_one_active_per_lead
  ON core.handoffs(lead_id)
  WHERE status IN ('open', 'acknowledged');

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

  SELECT l.lead_id
  INTO target_lead_id
  FROM core.leads l
  JOIN core.contacts c ON c.contact_id = l.contact_id
  WHERE (
      NULLIF(payload ->> 'lead_id', '') IS NOT NULL
      AND l.lead_id::TEXT = payload ->> 'lead_id'
    )
    OR (
      NULLIF(payload ->> 'phone', '') IS NOT NULL
      AND c.normalized_phone = ops.normalize_phone(payload ->> 'phone')
    )
    OR (
      NULLIF(payload ->> 'email', '') IS NOT NULL
      AND c.email = lower(NULLIF(payload ->> 'email', ''))
    )
  LIMIT 1;

  IF target_lead_id IS NULL THEN
    RETURN ops.wrap_error('LEAD_NOT_FOUND', 'Lead nao encontrado.', FALSE);
  END IF;

  IF NOT ops.is_lead_in_actor_scope(payload, target_lead_id) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  SELECT ops.wrap_success(
    jsonb_build_object(
      'lead',
      jsonb_build_object(
        'lead_id', l.lead_id,
        'stage', l.stage,
        'score', l.score,
        'temperature_band', l.temperature_band,
        'needs', COALESCE(string_to_array(l.needs_summary, '; '), ARRAY[]::TEXT[]),
        'handoff', (
          SELECT jsonb_build_object(
            'handoff_id', handoff.handoff_id,
            'status', handoff.status,
            'priority', handoff.priority
          )
          FROM core.handoffs handoff
          WHERE handoff.lead_id = l.lead_id
            AND handoff.status IN ('open', 'acknowledged')
          ORDER BY handoff.created_at DESC
          LIMIT 1
        )
      )
    )
  )
  INTO response_value
  FROM core.leads l
  WHERE l.lead_id = target_lead_id;

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
  reused_handoff BOOLEAN := FALSE;
BEGIN
  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  IF NOT ops.is_lead_in_actor_scope(payload, (payload ->> 'lead_id')::UUID) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('transferir_humano:' || (payload ->> 'idempotency_key')));
  SELECT * INTO idempotency_row
  FROM ops.idempotency_inbox
  WHERE idempotency_key = payload ->> 'idempotency_key'
    AND tool_name = 'transferir_humano'
  FOR UPDATE;

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

  PERFORM pg_advisory_xact_lock(hashtext('handoff-lead:' || (payload ->> 'lead_id')));

  SELECT * INTO handoff_row
  FROM core.handoffs
  WHERE lead_id = (payload ->> 'lead_id')::UUID
    AND status IN ('open', 'acknowledged')
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF handoff_row.handoff_id IS NULL THEN
    INSERT INTO core.handoffs (lead_id, reason, priority, status)
    VALUES (
      (payload ->> 'lead_id')::UUID,
      payload ->> 'reason',
      payload ->> 'priority',
      'open'
    )
    RETURNING * INTO handoff_row;
  ELSE
    reused_handoff := TRUE;
  END IF;

  UPDATE core.followups
  SET status = 'stopped',
      stop_reason = 'handoff',
      updated_at = NOW()
  WHERE lead_id = handoff_row.lead_id
    AND status = 'scheduled';

  UPDATE ops.delivery_outbox
  SET status = 'cancelled',
      updated_at = NOW()
  WHERE lead_id = handoff_row.lead_id
    AND status IN ('queued', 'retry', 'claimed');

  response_value := ops.wrap_success(
    jsonb_build_object(
      'handoff_id', handoff_row.handoff_id,
      'status', handoff_row.status,
      'reused', reused_handoff,
      'blocked_automation', TRUE
    )
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  PERFORM audit.append_event(
    'human_handoff_opened',
    handoff_row.lead_id,
    jsonb_build_object('handoff_id', handoff_row.handoff_id, 'priority', handoff_row.priority, 'reused', reused_handoff)
  );

  RETURN response_value;
END
$$;

COMMIT;
