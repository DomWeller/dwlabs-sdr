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
    encode(public.digest(contact.normalized_phone, 'sha256'), 'hex'),
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
    AND NOT EXISTS (
      SELECT 1
      FROM ops.optout_suppression suppression
      WHERE suppression.contact_hash = encode(public.digest(contact.normalized_phone, 'sha256'), 'hex')
    )
  ON CONFLICT (idempotency_key) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END
$$;

