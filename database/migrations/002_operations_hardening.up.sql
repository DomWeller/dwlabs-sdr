BEGIN;

CREATE TABLE IF NOT EXISTS ops.rate_limit_windows (
  scope TEXT NOT NULL,
  subject_hash TEXT NOT NULL,
  window_started_at TIMESTAMPTZ NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0 CHECK (request_count >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (scope, subject_hash, window_started_at)
);

CREATE TABLE IF NOT EXISTS ops.delivery_outbox (
  delivery_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  followup_id UUID NOT NULL REFERENCES core.followups(followup_id) ON DELETE CASCADE,
  lead_id UUID NOT NULL REFERENCES core.leads(lead_id) ON DELETE CASCADE,
  channel TEXT NOT NULL DEFAULT 'whatsapp',
  target_hash TEXT NOT NULL,
  message_redacted TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'claimed', 'retry', 'sent', 'failed', 'cancelled')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 3),
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  claimed_by TEXT,
  claimed_at TIMESTAMPTZ,
  external_message_id TEXT,
  last_error_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.privacy_requests (
  privacy_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES core.leads(lead_id) ON DELETE SET NULL,
  request_type TEXT NOT NULL CHECK (request_type IN ('export', 'anonymize', 'delete')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
  requested_by TEXT NOT NULL,
  result_redacted JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS ops.optout_suppression (
  contact_hash TEXT PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'whatsapp',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit.admin_change_log (
  change_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_subject TEXT NOT NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  diff_redacted JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE core.followups ADD COLUMN IF NOT EXISTS sequence_number SMALLINT NOT NULL DEFAULT 1;
ALTER TABLE core.followups ADD COLUMN IF NOT EXISTS consent_required BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE core.followups ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ;
ALTER TABLE core.followups ADD COLUMN IF NOT EXISTS last_error_code TEXT;

CREATE INDEX IF NOT EXISTS idx_rate_limit_cleanup ON ops.rate_limit_windows(updated_at);
CREATE INDEX IF NOT EXISTS idx_delivery_claim ON ops.delivery_outbox(status, next_attempt_at, created_at);
CREATE INDEX IF NOT EXISTS idx_privacy_requests_status ON ops.privacy_requests(status, created_at);

CREATE OR REPLACE FUNCTION ops.stop_followups_on_inbound()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.interaction_type = 'inbound' THEN
    UPDATE core.followups SET status = 'stopped', stop_reason = 'new_inbound', updated_at = NOW()
    WHERE lead_id = NEW.lead_id AND status = 'scheduled';
    UPDATE ops.delivery_outbox SET status = 'cancelled', updated_at = NOW()
    WHERE lead_id = NEW.lead_id AND status IN ('queued', 'retry', 'claimed');
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_stop_followups_on_inbound ON core.interactions;
CREATE TRIGGER trg_stop_followups_on_inbound
AFTER INSERT ON core.interactions
FOR EACH ROW EXECUTE FUNCTION ops.stop_followups_on_inbound();

CREATE OR REPLACE FUNCTION ops.sync_optout_suppression()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  phone_value TEXT;
BEGIN
  IF NEW.status = 'opted_out' THEN
    SELECT contact.normalized_phone INTO phone_value
    FROM core.leads lead JOIN core.contacts contact ON contact.contact_id = lead.contact_id
    WHERE lead.lead_id = NEW.lead_id;
    IF phone_value IS NOT NULL THEN
      INSERT INTO ops.optout_suppression(contact_hash)
      VALUES (encode(digest(phone_value, 'sha256'), 'hex')) ON CONFLICT DO NOTHING;
    END IF;
    UPDATE core.followups SET status = 'stopped', stop_reason = 'opt_out', updated_at = NOW()
    WHERE lead_id = NEW.lead_id AND status = 'scheduled';
    UPDATE ops.delivery_outbox SET status = 'cancelled', updated_at = NOW()
    WHERE lead_id = NEW.lead_id AND status IN ('queued', 'retry', 'claimed');
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_sync_optout_suppression ON core.consents;
CREATE TRIGGER trg_sync_optout_suppression
AFTER INSERT OR UPDATE OF status ON core.consents
FOR EACH ROW EXECUTE FUNCTION ops.sync_optout_suppression();

CREATE OR REPLACE FUNCTION ops.check_rate_limit(
  scope_value TEXT,
  subject_value TEXT,
  request_limit INTEGER,
  window_seconds INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  window_start TIMESTAMPTZ;
  current_count INTEGER;
  retry_after INTEGER;
BEGIN
  IF request_limit < 1 OR window_seconds < 1 OR NULLIF(subject_value, '') IS NULL THEN
    RETURN ops.wrap_error('RATE_LIMIT_CONFIG_INVALID', 'Configuracao de limite invalida.', FALSE);
  END IF;

  window_start := to_timestamp(floor(extract(epoch FROM NOW()) / window_seconds) * window_seconds);
  INSERT INTO ops.rate_limit_windows(scope, subject_hash, window_started_at, request_count)
  VALUES (scope_value, encode(digest(subject_value, 'sha256'), 'hex'), window_start, 1)
  ON CONFLICT (scope, subject_hash, window_started_at)
  DO UPDATE SET request_count = ops.rate_limit_windows.request_count + 1, updated_at = NOW()
  RETURNING request_count INTO current_count;

  retry_after := greatest(1, ceil(extract(epoch FROM (window_start + make_interval(secs => window_seconds) - NOW())))::INTEGER);
  IF current_count > request_limit THEN
    RETURN jsonb_build_object(
      'ok', FALSE,
      'data', NULL,
      'error', jsonb_build_object('code', 'RATE_LIMITED', 'message', 'Limite temporario excedido.', 'retryable', TRUE),
      'retry_after_seconds', retry_after
    );
  END IF;

  RETURN ops.wrap_success(jsonb_build_object('allowed', TRUE, 'remaining', request_limit - current_count));
END
$$;

CREATE OR REPLACE FUNCTION ops.followup_is_eligible(target_lead_id UUID)
RETURNS TABLE(eligible BOOLEAN, reason TEXT)
LANGUAGE SQL
STABLE
AS $$
  SELECT CASE
    WHEN lead.lead_id IS NULL THEN FALSE
    WHEN COALESCE(consent.status, 'unknown'::core.consent_status) <> 'granted' THEN FALSE
    WHEN lead.stage IN ('REUNIAO_MARCADA', 'PROPOSTA', 'FECHADO', 'PERDIDO') THEN FALSE
    WHEN EXISTS (SELECT 1 FROM core.handoffs h WHERE h.lead_id = lead.lead_id AND h.status = 'open') THEN FALSE
    ELSE TRUE
  END,
  CASE
    WHEN lead.lead_id IS NULL THEN 'lead_missing'
    WHEN COALESCE(consent.status, 'unknown'::core.consent_status) <> 'granted' THEN 'consent_required'
    WHEN lead.stage IN ('REUNIAO_MARCADA', 'PROPOSTA', 'FECHADO', 'PERDIDO') THEN 'stage_blocked'
    WHEN EXISTS (SELECT 1 FROM core.handoffs h WHERE h.lead_id = lead.lead_id AND h.status = 'open') THEN 'handoff'
    ELSE 'eligible'
  END
  FROM (SELECT target_lead_id AS lead_id) requested
  LEFT JOIN core.leads lead ON lead.lead_id = requested.lead_id
  LEFT JOIN core.consents consent ON consent.lead_id = lead.lead_id
$$;

CREATE OR REPLACE FUNCTION ops.enqueue_due_followups(pilot_target_phone TEXT, pilot_mode BOOLEAN DEFAULT TRUE)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
DECLARE
  inserted_count INTEGER;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM ops.runtime_flags WHERE flag_name = 'followup_enabled' AND enabled) THEN
    RETURN 0;
  END IF;

  INSERT INTO ops.delivery_outbox(
    followup_id, lead_id, target_hash, message_redacted, idempotency_key
  )
  SELECT
    followup.followup_id,
    followup.lead_id,
    encode(digest(contact.normalized_phone, 'sha256'), 'hex'),
    COALESCE(followup.message_template, contact.full_name || ', posso ajudar a organizar o proximo passo sem repetir o que voce ja explicou.'),
    'followup:' || followup.followup_id::TEXT
  FROM core.followups followup
  JOIN core.leads lead ON lead.lead_id = followup.lead_id
  JOIN core.contacts contact ON contact.contact_id = lead.contact_id
  CROSS JOIN LATERAL ops.followup_is_eligible(followup.lead_id) eligibility
  WHERE followup.status = 'scheduled'
    AND followup.scheduled_for <= NOW()
    AND eligibility.eligible
    AND extract(isodow FROM NOW() AT TIME ZONE 'America/Sao_Paulo') BETWEEN 1 AND 5
    AND (NOW() AT TIME ZONE 'America/Sao_Paulo')::TIME BETWEEN TIME '09:00' AND TIME '18:00'
    AND (NOT pilot_mode OR contact.normalized_phone = ops.normalize_phone(pilot_target_phone))
    AND NOT EXISTS (SELECT 1 FROM ops.optout_suppression s WHERE s.contact_hash = encode(digest(contact.normalized_phone, 'sha256'), 'hex'))
  ON CONFLICT (idempotency_key) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END
$$;

CREATE OR REPLACE FUNCTION ops.claim_delivery(worker_id TEXT)
RETURNS TABLE(delivery_id UUID, target_phone TEXT, message_text TEXT, idempotency_key TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
BEGIN
  RETURN QUERY
  WITH candidate AS (
    SELECT outbox.delivery_id
    FROM ops.delivery_outbox outbox
    WHERE outbox.status IN ('queued', 'retry') AND outbox.next_attempt_at <= NOW()
    ORDER BY outbox.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
  ), claimed AS (
    UPDATE ops.delivery_outbox outbox
    SET status = 'claimed', claimed_by = worker_id, claimed_at = NOW(), updated_at = NOW()
    FROM candidate
    WHERE outbox.delivery_id = candidate.delivery_id
    RETURNING outbox.delivery_id, outbox.lead_id, outbox.message_redacted, outbox.idempotency_key
  )
  SELECT claimed.delivery_id, contact.normalized_phone, claimed.message_redacted, claimed.idempotency_key
  FROM claimed
  JOIN core.leads lead ON lead.lead_id = claimed.lead_id
  JOIN core.contacts contact ON contact.contact_id = lead.contact_id;
END
$$;

CREATE OR REPLACE FUNCTION ops.delivery_is_sendable(target_delivery_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM ops.delivery_outbox outbox
    CROSS JOIN LATERAL ops.followup_is_eligible(outbox.lead_id) eligibility
    WHERE outbox.delivery_id = target_delivery_id
      AND outbox.status = 'claimed'
      AND eligibility.eligible
      AND NOT EXISTS (SELECT 1 FROM ops.runtime_flags WHERE flag_name = 'automation_paused' AND enabled)
      AND EXISTS (SELECT 1 FROM ops.runtime_flags WHERE flag_name = 'dispatcher_enabled' AND enabled)
  )
$$;

CREATE OR REPLACE FUNCTION ops.complete_delivery(target_delivery_id UUID, external_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
BEGIN
  UPDATE ops.delivery_outbox
  SET status = 'sent', external_message_id = external_id, sent_at = NOW(), updated_at = NOW()
  WHERE delivery_id = target_delivery_id AND status = 'claimed';

  UPDATE core.followups followup
  SET status = 'sent', sent_at = NOW(), updated_at = NOW()
  FROM ops.delivery_outbox outbox
  WHERE outbox.delivery_id = target_delivery_id AND followup.followup_id = outbox.followup_id;

  INSERT INTO core.followups(lead_id, policy_code, scheduled_for, status, sequence_number, consent_required, message_template)
  SELECT outbox.lead_id, 'auto_second', NOW() + INTERVAL '72 hours', 'scheduled', 2, TRUE,
         'Oi! Esta e minha ultima mensagem sobre o assunto. Se ainda fizer sentido, posso organizar o proximo passo para voce.'
  FROM ops.delivery_outbox outbox
  JOIN core.followups first_followup ON first_followup.followup_id = outbox.followup_id
  WHERE outbox.delivery_id = target_delivery_id AND first_followup.sequence_number = 1
    AND NOT EXISTS (SELECT 1 FROM core.followups existing WHERE existing.lead_id = outbox.lead_id AND existing.sequence_number = 2);
END
$$;

CREATE OR REPLACE FUNCTION ops.fail_delivery(target_delivery_id UUID, error_code TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
DECLARE
  attempts INTEGER;
BEGIN
  UPDATE ops.delivery_outbox
  SET attempt_count = attempt_count + 1,
      status = CASE WHEN attempt_count + 1 >= 3 THEN 'failed' ELSE 'retry' END,
      next_attempt_at = NOW() + CASE attempt_count + 1 WHEN 1 THEN INTERVAL '1 minute' WHEN 2 THEN INTERVAL '5 minutes' ELSE INTERVAL '15 minutes' END,
      last_error_code = left(COALESCE(error_code, 'DELIVERY_FAILED'), 80),
      claimed_by = NULL,
      claimed_at = NULL,
      updated_at = NOW()
  WHERE delivery_id = target_delivery_id AND status = 'claimed'
  RETURNING attempt_count INTO attempts;

  IF attempts >= 3 THEN
    UPDATE core.followups followup
    SET last_error_code = 'DELIVERY_FAILED', updated_at = NOW()
    FROM ops.delivery_outbox outbox
    WHERE outbox.delivery_id = target_delivery_id AND followup.followup_id = outbox.followup_id;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION ops.apply_retention(dry_run BOOLEAN DEFAULT TRUE)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  interactions_due INTEGER;
  leads_due INTEGER;
BEGIN
  SELECT count(*) INTO interactions_due FROM core.interactions WHERE created_at < NOW() - INTERVAL '90 days';
  SELECT count(*) INTO leads_due FROM core.leads WHERE COALESCE(last_message_at, updated_at) < NOW() - INTERVAL '12 months';

  IF NOT dry_run THEN
    DELETE FROM core.interactions WHERE created_at < NOW() - INTERVAL '90 days';
    UPDATE core.contacts contact
    SET full_name = 'Titular anonimizado', normalized_phone = NULL, email = NULL, role_title = NULL, updated_at = NOW()
    FROM core.leads lead
    WHERE lead.contact_id = contact.contact_id
      AND COALESCE(lead.last_message_at, lead.updated_at) < NOW() - INTERVAL '12 months';
    DELETE FROM ops.metrics_events WHERE created_at < NOW() - INTERVAL '12 months';
    DELETE FROM audit.redacted_event_log WHERE created_at < NOW() - INTERVAL '12 months';
    DELETE FROM audit.admin_change_log WHERE created_at < NOW() - INTERVAL '12 months';
    DELETE FROM ops.rate_limit_windows WHERE updated_at < NOW() - INTERVAL '2 days';
  END IF;

  RETURN ops.wrap_success(jsonb_build_object('dry_run', dry_run, 'interactions_due', interactions_due, 'leads_due', leads_due));
END
$$;

INSERT INTO ops.runtime_flags(flag_name, enabled, metadata)
VALUES
  ('followup_enabled', FALSE, '{"gate":"pilot-only"}'),
  ('dispatcher_enabled', FALSE, '{"gate":"pilot-only"}'),
  ('retention_enabled', FALSE, '{"mode":"dry-run-first"}'),
  ('automation_paused', FALSE, '{}')
ON CONFLICT (flag_name) DO NOTHING;

COMMIT;
