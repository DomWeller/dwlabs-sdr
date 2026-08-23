BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS rag;
CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS api;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'lead_stage') THEN
    CREATE TYPE core.lead_stage AS ENUM (
      'NOVO_LEAD',
      'EM_QUALIFICACAO',
      'QUALIFICADO',
      'REUNIAO_MARCADA',
      'REUNIAO_REALIZADA',
      'PROPOSTA',
      'NEGOCIACAO',
      'FECHADO',
      'PERDIDO',
      'FOLLOWUP'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'interaction_type') THEN
    CREATE TYPE core.interaction_type AS ENUM ('inbound', 'outbound', 'note', 'system', 'handoff', 'followup');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'meeting_status') THEN
    CREATE TYPE core.meeting_status AS ENUM ('pending', 'scheduled', 'rescheduled', 'cancelled', 'completed');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'followup_status') THEN
    CREATE TYPE core.followup_status AS ENUM ('scheduled', 'sent', 'cancelled', 'stopped');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'handoff_status') THEN
    CREATE TYPE core.handoff_status AS ENUM ('open', 'acknowledged', 'closed');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'consent_status') THEN
    CREATE TYPE core.consent_status AS ENUM ('unknown', 'granted', 'opted_out');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS core.companies (
  company_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  normalized_name TEXT GENERATED ALWAYS AS (lower(trim(name))) STORED,
  website_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS core.contacts (
  contact_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES core.companies(company_id) ON DELETE SET NULL,
  full_name TEXT NOT NULL,
  normalized_phone TEXT,
  email TEXT,
  role_title TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE NULLS NOT DISTINCT (normalized_phone),
  UNIQUE NULLS NOT DISTINCT (email)
);

CREATE TABLE IF NOT EXISTS core.leads (
  lead_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id UUID NOT NULL REFERENCES core.contacts(contact_id) ON DELETE CASCADE,
  company_id UUID REFERENCES core.companies(company_id) ON DELETE SET NULL,
  source TEXT NOT NULL DEFAULT 'unknown',
  stage core.lead_stage NOT NULL DEFAULT 'NOVO_LEAD',
  score INTEGER NOT NULL DEFAULT 0 CHECK (score BETWEEN 0 AND 100),
  temperature_band TEXT NOT NULL DEFAULT 'frio',
  needs_summary TEXT,
  indicative_budget TEXT,
  urgency TEXT,
  origin_detail TEXT,
  owner_name TEXT,
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS core.conversations (
  conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID NOT NULL REFERENCES core.leads(lead_id) ON DELETE CASCADE,
  channel TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  agent_id TEXT NOT NULL DEFAULT 'comercial',
  latest_summary TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (channel, peer_id, agent_id)
);

CREATE TABLE IF NOT EXISTS core.interactions (
  interaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES core.leads(lead_id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES core.conversations(conversation_id) ON DELETE CASCADE,
  interaction_type core.interaction_type NOT NULL,
  source_message_id TEXT,
  content_redacted TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  delivery_status TEXT NOT NULL DEFAULT 'stored',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS core.services (
  service_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  summary TEXT NOT NULL,
  qualification_hint TEXT NOT NULL,
  pricing_mode TEXT NOT NULL DEFAULT 'sob_consulta',
  price_from NUMERIC(12, 2),
  price_to NUMERIC(12, 2),
  currency TEXT NOT NULL DEFAULT 'BRL',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS core.service_upsells (
  service_id UUID NOT NULL REFERENCES core.services(service_id) ON DELETE CASCADE,
  upsell_service_id UUID NOT NULL REFERENCES core.services(service_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (service_id, upsell_service_id)
);

CREATE TABLE IF NOT EXISTS core.qualification_questions (
  question_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  question TEXT NOT NULL,
  objective TEXT NOT NULL,
  weight INTEGER NOT NULL CHECK (weight BETWEEN 0 AND 100),
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS core.portfolio_items (
  portfolio_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id UUID REFERENCES core.services(service_id) ON DELETE SET NULL,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  segment TEXT NOT NULL,
  summary TEXT NOT NULL,
  proof TEXT NOT NULL,
  is_public BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS core.meetings (
  meeting_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID NOT NULL REFERENCES core.leads(lead_id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES core.contacts(contact_id) ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'America/Sao_Paulo',
  status core.meeting_status NOT NULL DEFAULT 'pending',
  external_event_id TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS core.followups (
  followup_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID NOT NULL REFERENCES core.leads(lead_id) ON DELETE CASCADE,
  policy_code TEXT NOT NULL,
  scheduled_for TIMESTAMPTZ NOT NULL,
  status core.followup_status NOT NULL DEFAULT 'scheduled',
  message_template TEXT,
  stop_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS core.consents (
  consent_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID NOT NULL REFERENCES core.leads(lead_id) ON DELETE CASCADE,
  status core.consent_status NOT NULL DEFAULT 'unknown',
  opted_out_at TIMESTAMPTZ,
  granted_at TIMESTAMPTZ,
  source TEXT NOT NULL DEFAULT 'conversation',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (lead_id)
);

CREATE TABLE IF NOT EXISTS core.handoffs (
  handoff_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID NOT NULL REFERENCES core.leads(lead_id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  priority TEXT NOT NULL,
  status core.handoff_status NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rag.knowledge_documents (
  document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  category TEXT NOT NULL,
  source_uri TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  body TEXT NOT NULL,
  body_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rag.knowledge_chunks (
  chunk_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES rag.knowledge_documents(document_id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  body_tsv tsvector NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (document_id, chunk_index)
);

CREATE TABLE IF NOT EXISTS ops.idempotency_inbox (
  inbox_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_system TEXT NOT NULL,
  external_event_id TEXT NOT NULL,
  tool_name TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  request_envelope JSONB NOT NULL DEFAULT '{}'::jsonb,
  response_payload JSONB,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  replay_count INTEGER NOT NULL DEFAULT 0,
  UNIQUE (source_system, external_event_id),
  UNIQUE (idempotency_key)
);

CREATE TABLE IF NOT EXISTS ops.runtime_flags (
  flag_name TEXT PRIMARY KEY,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.notification_outbox (
  notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES core.leads(lead_id) ON DELETE CASCADE,
  mode TEXT NOT NULL DEFAULT 'mock',
  payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.sheet_sync_outbox (
  sync_job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scope TEXT NOT NULL,
  payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit.redacted_event_log (
  event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  lead_id UUID,
  payload_redacted JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.metrics_events (
  metric_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  metric_name TEXT NOT NULL,
  metric_value NUMERIC(12, 2) NOT NULL DEFAULT 0,
  dimensions JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leads_stage ON core.leads(stage);
CREATE INDEX IF NOT EXISTS idx_leads_score ON core.leads(score);
CREATE INDEX IF NOT EXISTS idx_interactions_lead ON core.interactions(lead_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_meetings_range ON core.meetings(starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_followups_schedule ON core.followups(status, scheduled_for);
CREATE INDEX IF NOT EXISTS idx_chunks_fts ON rag.knowledge_chunks USING GIN (body_tsv);

CREATE OR REPLACE FUNCTION ops.normalize_phone(input TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT CASE
    WHEN input IS NULL OR regexp_replace(input, '\D+', '', 'g') = '' THEN NULL
    WHEN regexp_replace(input, '\D+', '', 'g') ~ '^55\d{10,13}$' THEN regexp_replace(input, '\D+', '', 'g')
    ELSE '55' || regexp_replace(input, '\D+', '', 'g')
  END
$$;

CREATE OR REPLACE FUNCTION ops.temperature_band(score_value INTEGER)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT CASE
    WHEN score_value >= 85 THEN 'muito_quente'
    WHEN score_value >= 70 THEN 'quente'
    WHEN score_value >= 40 THEN 'morno'
    ELSE 'frio'
  END
$$;

CREATE OR REPLACE FUNCTION ops.redact_text(input TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT regexp_replace(
    regexp_replace(
      COALESCE(input, ''),
      '(^|[^0-9])55[0-9]{10,13}([^0-9]|$)',
      '\1[telefone-redigido]\2',
      'g'
    ),
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
    '[email-redigido]',
    'g'
  )
$$;

CREATE OR REPLACE FUNCTION ops.wrap_success(data JSONB, redactions TEXT[] DEFAULT ARRAY[]::TEXT[])
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT jsonb_build_object(
    'ok', TRUE,
    'data', COALESCE(data, '{}'::jsonb),
    'error', NULL,
    'audit', jsonb_build_object(
      'correlation_id', gen_random_uuid(),
      'redactions_applied', to_jsonb(redactions)
    )
  )
$$;

CREATE OR REPLACE FUNCTION ops.wrap_error(code TEXT, message TEXT, retryable BOOLEAN)
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT jsonb_build_object(
    'ok', FALSE,
    'data', NULL,
    'error', jsonb_build_object(
      'code', code,
      'message', message,
      'retryable', retryable
    ),
    'audit', jsonb_build_object(
      'correlation_id', gen_random_uuid(),
      'redactions_applied', '[]'::jsonb
    )
  )
$$;

CREATE OR REPLACE FUNCTION ops.integration_enabled(flag_name_value TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM ops.runtime_flags
    WHERE flag_name = flag_name_value
      AND enabled
  )
$$;

CREATE OR REPLACE FUNCTION ops.payload_hash(input JSONB)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT encode(digest(COALESCE(input::TEXT, ''), 'sha256'), 'hex')
$$;

CREATE OR REPLACE FUNCTION ops.is_lead_in_actor_scope(payload JSONB, target_lead_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
  SELECT target_lead_id IS NOT NULL
    AND (
      NULLIF(payload #>> '{context,lead_id}', '') = target_lead_id::TEXT
      OR EXISTS (
        SELECT 1
        FROM core.conversations conv
        WHERE conv.lead_id = target_lead_id
          AND conv.conversation_id::TEXT = NULLIF(payload #>> '{context,conversation_id}', '')
      )
      OR EXISTS (
        SELECT 1
        FROM core.leads scoped_lead
        JOIN core.contacts scoped_contact ON scoped_contact.contact_id = scoped_lead.contact_id
        WHERE scoped_lead.lead_id = target_lead_id
          AND (
            (
              NULLIF(payload #>> '{actor,phone}', '') IS NOT NULL
              AND scoped_contact.normalized_phone = ops.normalize_phone(payload #>> '{actor,phone}')
            )
            OR (
              NULLIF(payload #>> '{actor,email}', '') IS NOT NULL
              AND scoped_contact.email = lower(payload #>> '{actor,email}')
            )
          )
      )
    )
$$;

CREATE OR REPLACE FUNCTION ops.calculate_score_from_payload(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  total_score INTEGER := 10;
  factors JSONB := '[]'::jsonb;
  urgency_level TEXT := COALESCE(payload ->> 'urgency_level', 'baixa');
  budget_signal TEXT := COALESCE(payload ->> 'budget_signal', 'nenhum');
  authority_level TEXT := COALESCE(payload ->> 'authority_level', 'incerto');
  inbound_intent TEXT := COALESCE(payload ->> 'inbound_intent', 'fraca');
  existing_channels TEXT := COALESCE(payload ->> 'existing_channels', 'nenhum');
BEGIN
  factors := factors || jsonb_build_array(jsonb_build_object('label', 'base', 'delta', 10));

  IF COALESCE((payload ->> 'has_defined_offer')::BOOLEAN, FALSE) THEN
    total_score := total_score + 15;
    factors := factors || jsonb_build_array(jsonb_build_object('label', 'oferta_definida', 'delta', 15));
  END IF;

  CASE urgency_level
    WHEN 'media' THEN total_score := total_score + 12;
    WHEN 'alta' THEN total_score := total_score + 22;
    ELSE total_score := total_score + 4;
  END CASE;

  CASE budget_signal
    WHEN 'baixo' THEN total_score := total_score + 6;
    WHEN 'medio' THEN total_score := total_score + 12;
    WHEN 'alto' THEN total_score := total_score + 18;
    ELSE total_score := total_score + 2;
  END CASE;

  CASE authority_level
    WHEN 'influenciador' THEN total_score := total_score + 8;
    WHEN 'decisor' THEN total_score := total_score + 14;
    ELSE total_score := total_score + 2;
  END CASE;

  CASE inbound_intent
    WHEN 'moderada' THEN total_score := total_score + 10;
    WHEN 'forte' THEN total_score := total_score + 18;
    ELSE total_score := total_score + 3;
  END CASE;

  CASE existing_channels
    WHEN 'organico' THEN total_score := total_score + 6;
    WHEN 'pago' THEN total_score := total_score + 8;
    WHEN 'misto' THEN total_score := total_score + 10;
    ELSE total_score := total_score + 2;
  END CASE;

  IF COALESCE((payload ->> 'wants_meeting')::BOOLEAN, FALSE) THEN
    total_score := total_score + 14;
  END IF;

  IF COALESCE((payload ->> 'asks_for_proposal')::BOOLEAN, FALSE) THEN
    total_score := total_score + 18;
  END IF;

  total_score := LEAST(100, GREATEST(0, total_score));

  RETURN jsonb_build_object(
    'score', total_score,
    'temperature_band', ops.temperature_band(total_score),
    'factors', factors
  );
END
$$;

CREATE OR REPLACE FUNCTION audit.append_event(event_type_value TEXT, lead_id_value UUID, payload_value JSONB)
RETURNS VOID
LANGUAGE SQL
AS $$
  INSERT INTO audit.redacted_event_log (event_type, lead_id, payload_redacted)
  VALUES (event_type_value, lead_id_value, payload_value);
$$;

CREATE OR REPLACE FUNCTION api.buscar_servicos(payload JSONB)
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT ops.wrap_success(
    jsonb_build_object(
      'services',
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'service_id', s.service_id,
              'slug', s.slug,
              'name', s.name,
              'summary', s.summary,
              'pricing_mode', s.pricing_mode,
              'upsells', COALESCE((
                SELECT jsonb_agg(s2.slug ORDER BY s2.slug)
                FROM core.service_upsells su
                JOIN core.services s2 ON s2.service_id = su.upsell_service_id
                WHERE su.service_id = s.service_id
              ), '[]'::jsonb)
            )
            ORDER BY s.name
          )
          FROM core.services s
          WHERE (payload ->> 'category' IS NULL OR s.category = payload ->> 'category')
            AND (COALESCE((payload ->> 'active_only')::BOOLEAN, TRUE) = FALSE OR s.active = TRUE)
            AND (
              payload -> 'service_ids' IS NULL
              OR s.slug IN (
                SELECT jsonb_array_elements_text(payload -> 'service_ids')
              )
            )
        ),
        '[]'::jsonb
      )
    )
  )
$$;

CREATE OR REPLACE FUNCTION api.buscar_servico(payload JSONB)
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT COALESCE(
    (
      SELECT ops.wrap_success(
        jsonb_build_object(
          'service',
          jsonb_build_object(
            'service_id', s.service_id,
            'slug', s.slug,
            'name', s.name,
            'summary', s.summary,
            'qualification_hint', s.qualification_hint,
            'pricing_mode', s.pricing_mode
          )
        )
      )
      FROM core.services s
      WHERE s.slug = COALESCE(payload ->> 'slug', payload ->> 'service_id')
         OR lower(s.name) = lower(COALESCE(payload ->> 'name', ''))
      LIMIT 1
    ),
    ops.wrap_error('SERVICE_NOT_FOUND', 'Servico nao encontrado.', FALSE)
  )
$$;

CREATE OR REPLACE FUNCTION api.buscar_precos(payload JSONB)
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT ops.wrap_success(
    jsonb_build_object(
      'prices',
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'service_id', s.service_id,
              'pricing_mode', s.pricing_mode,
              'price_from', s.price_from,
              'price_to', s.price_to,
              'currency', s.currency,
              'sob_consulta', s.price_from IS NULL AND s.price_to IS NULL
            )
          )
          FROM core.services s
          WHERE s.slug IN (
            SELECT jsonb_array_elements_text(payload -> 'service_ids')
          )
        ),
        '[]'::jsonb
      )
    )
  )
$$;

CREATE OR REPLACE FUNCTION api.buscar_portfolio(payload JSONB)
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT ops.wrap_success(
    jsonb_build_object(
      'items',
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'title', p.title,
              'segment', p.segment,
              'summary', p.summary,
              'proof', p.proof
            )
            ORDER BY p.title
          )
          FROM (
            SELECT p.*
            FROM core.portfolio_items p
            LEFT JOIN core.services s ON s.service_id = p.service_id
            WHERE p.is_public = TRUE
              AND (payload ->> 'segment' IS NULL OR p.segment = payload ->> 'segment')
              AND (payload ->> 'service_id' IS NULL OR s.slug = payload ->> 'service_id')
            LIMIT COALESCE((payload ->> 'limit')::INTEGER, 3)
          ) p
        ),
        '[]'::jsonb
      )
    )
  )
$$;

CREATE OR REPLACE FUNCTION api.salvar_lead(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  company_row core.companies%ROWTYPE;
  contact_row core.contacts%ROWTYPE;
  lead_row core.leads%ROWTYPE;
  conversation_row core.conversations%ROWTYPE;
  created_flag BOOLEAN := FALSE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));

  SELECT *
  INTO idempotency_row
  FROM ops.idempotency_inbox
  WHERE idempotency_key = payload ->> 'idempotency_key'
  FOR UPDATE;

  IF idempotency_row.inbox_id IS NOT NULL THEN
    IF idempotency_row.payload_hash <> payload_hash_value THEN
      RETURN ops.wrap_error('IDEMPOTENCY_HASH_MISMATCH', 'Mesmo idempotency_key com payload diferente.', FALSE);
    END IF;

    IF idempotency_row.completed_at IS NOT NULL THEN
      UPDATE ops.idempotency_inbox
      SET replay_count = replay_count + 1
      WHERE inbox_id = idempotency_row.inbox_id;
      RETURN idempotency_row.response_payload;
    END IF;
  ELSE
    INSERT INTO ops.idempotency_inbox (
      source_system,
      external_event_id,
      tool_name,
      idempotency_key,
      payload_hash,
      request_envelope
    )
    VALUES (
      'openclaw',
      COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'),
      'salvar_lead',
      payload ->> 'idempotency_key',
      payload_hash_value,
      payload
    )
    RETURNING * INTO idempotency_row;
  END IF;

  IF payload ->> 'company_name' IS NOT NULL THEN
    INSERT INTO core.companies (name)
    VALUES (payload ->> 'company_name')
    ON CONFLICT DO NOTHING;

    SELECT *
    INTO company_row
    FROM core.companies
    WHERE normalized_name = lower(trim(payload ->> 'company_name'))
    LIMIT 1;
  END IF;

  INSERT INTO core.contacts (company_id, full_name, normalized_phone, email)
  VALUES (
    company_row.company_id,
    COALESCE(payload ->> 'contact_name', 'Contato sem nome'),
    ops.normalize_phone(payload ->> 'phone'),
    lower(NULLIF(payload ->> 'email', ''))
  )
  ON CONFLICT (normalized_phone) DO UPDATE
  SET full_name = EXCLUDED.full_name,
      company_id = COALESCE(EXCLUDED.company_id, core.contacts.company_id),
      email = COALESCE(EXCLUDED.email, core.contacts.email),
      updated_at = NOW()
  RETURNING * INTO contact_row;

  SELECT *
  INTO lead_row
  FROM core.leads
  WHERE contact_id = contact_row.contact_id
  LIMIT 1;

  IF lead_row.lead_id IS NULL THEN
    created_flag := TRUE;
    INSERT INTO core.leads (contact_id, company_id, source, needs_summary, last_message_at)
    VALUES (
      contact_row.contact_id,
      company_row.company_id,
      COALESCE(payload ->> 'source', 'unknown'),
      payload ->> 'need_summary',
      NOW()
    )
    RETURNING * INTO lead_row;
  ELSE
    UPDATE core.leads
    SET needs_summary = COALESCE(payload ->> 'need_summary', needs_summary),
        last_message_at = NOW(),
        updated_at = NOW()
    WHERE lead_id = lead_row.lead_id
    RETURNING * INTO lead_row;
  END IF;

  INSERT INTO core.consents (lead_id, status, granted_at, opted_out_at)
  VALUES (
    lead_row.lead_id,
    COALESCE((payload ->> 'consent_status')::core.consent_status, 'unknown'),
    CASE WHEN payload ->> 'consent_status' = 'granted' THEN NOW() ELSE NULL END,
    CASE WHEN payload ->> 'consent_status' = 'opted_out' THEN NOW() ELSE NULL END
  )
  ON CONFLICT (lead_id) DO UPDATE
  SET status = EXCLUDED.status,
      granted_at = COALESCE(EXCLUDED.granted_at, core.consents.granted_at),
      opted_out_at = COALESCE(EXCLUDED.opted_out_at, core.consents.opted_out_at),
      updated_at = NOW();

  INSERT INTO core.conversations (lead_id, channel, peer_id, agent_id)
  VALUES (
    lead_row.lead_id,
    COALESCE(payload ->> 'channel', 'test'),
    COALESCE(ops.normalize_phone(payload ->> 'phone'), lower(COALESCE(payload ->> 'email', 'anonimo'))),
    'comercial'
  )
  ON CONFLICT (channel, peer_id, agent_id) DO UPDATE
  SET updated_at = NOW()
  RETURNING * INTO conversation_row;

  PERFORM audit.append_event(
    'lead_saved',
    lead_row.lead_id,
    jsonb_build_object(
      'contact_name', payload ->> 'contact_name',
      'company_name', payload ->> 'company_name',
      'phone', ops.redact_text(payload ->> 'phone'),
      'email', ops.redact_text(payload ->> 'email')
    )
  );

  response_value := ops.wrap_success(
    jsonb_build_object(
      'lead_id', lead_row.lead_id,
      'contact_id', contact_row.contact_id,
      'conversation_id', conversation_row.conversation_id,
      'created', created_flag,
      'merged', NOT created_flag
    ),
    ARRAY['phone', 'email']
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.atualizar_lead(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  updated_lead_id UUID;
  response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  IF NULLIF(payload ->> 'lead_id', '') IS NULL THEN
    RETURN ops.wrap_error('LEAD_ID_REQUIRED', 'lead_id obrigatorio.', FALSE);
  END IF;

  IF payload -> 'context' ->> 'lead_id' IS NOT NULL
     AND payload ->> 'lead_id' IS NOT NULL
     AND payload -> 'context' ->> 'lead_id' <> payload ->> 'lead_id' THEN
    RETURN ops.wrap_error('LEAD_CONTEXT_MISMATCH', 'Contexto do lead divergente.', FALSE);
  END IF;

  IF NOT ops.is_lead_in_actor_scope(payload, (payload ->> 'lead_id')::UUID) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));

  SELECT *
  INTO idempotency_row
  FROM ops.idempotency_inbox
  WHERE idempotency_key = payload ->> 'idempotency_key'
  FOR UPDATE;

  IF idempotency_row.inbox_id IS NOT NULL THEN
    IF idempotency_row.payload_hash <> payload_hash_value THEN
      RETURN ops.wrap_error('IDEMPOTENCY_HASH_MISMATCH', 'Mesmo idempotency_key com payload diferente.', FALSE);
    END IF;
    IF idempotency_row.completed_at IS NOT NULL THEN
      UPDATE ops.idempotency_inbox
      SET replay_count = replay_count + 1
      WHERE inbox_id = idempotency_row.inbox_id;
      RETURN idempotency_row.response_payload;
    END IF;
  ELSE
    INSERT INTO ops.idempotency_inbox (
      source_system,
      external_event_id,
      tool_name,
      idempotency_key,
      payload_hash,
      request_envelope
    )
    VALUES (
      'openclaw',
      COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'),
      'atualizar_lead',
      payload ->> 'idempotency_key',
      payload_hash_value,
      payload
    )
    RETURNING * INTO idempotency_row;
  END IF;

  UPDATE core.leads
  SET stage = COALESCE((payload ->> 'stage')::core.lead_stage, stage),
      needs_summary = COALESCE(array_to_string(ARRAY(SELECT jsonb_array_elements_text(payload -> 'needs')), '; '), needs_summary),
      indicative_budget = COALESCE(payload ->> 'indicative_budget', indicative_budget),
      urgency = COALESCE(payload ->> 'urgency', urgency),
      origin_detail = COALESCE(payload ->> 'origin', origin_detail),
      owner_name = COALESCE(payload ->> 'owner', owner_name),
      updated_at = NOW()
  WHERE lead_id = (payload ->> 'lead_id')::UUID
  RETURNING lead_id INTO updated_lead_id;

  response_value := COALESCE(
    CASE
      WHEN updated_lead_id IS NOT NULL THEN ops.wrap_success(jsonb_build_object('lead_id', updated_lead_id, 'updated', TRUE))
      ELSE NULL
    END,
    ops.wrap_error('LEAD_NOT_FOUND', 'Lead nao encontrado.', FALSE)
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

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
        'needs', COALESCE(string_to_array(l.needs_summary, '; '), ARRAY[]::TEXT[])
      )
    )
  )
  INTO response_value
  FROM core.leads l
  WHERE l.lead_id = target_lead_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.buscar_cliente(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  target_contact_id UUID;
  target_lead_id UUID;
  response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'contact_ref', '') IS NULL THEN
    RETURN ops.wrap_error('CONTACT_REF_REQUIRED', 'contact_ref obrigatorio.', FALSE);
  END IF;

  SELECT c.contact_id, l.lead_id
  INTO target_contact_id, target_lead_id
  FROM core.contacts c
  LEFT JOIN core.leads l ON l.contact_id = c.contact_id
  WHERE c.contact_id::TEXT = payload ->> 'contact_ref'
     OR c.normalized_phone = ops.normalize_phone(payload ->> 'contact_ref')
     OR c.email = lower(payload ->> 'contact_ref')
  LIMIT 1;

  IF target_contact_id IS NULL OR target_lead_id IS NULL THEN
    RETURN ops.wrap_error('CUSTOMER_NOT_FOUND', 'Cliente nao encontrado.', FALSE);
  END IF;

  IF NOT ops.is_lead_in_actor_scope(payload, target_lead_id) THEN
    RETURN ops.wrap_error('CUSTOMER_SCOPE_FORBIDDEN', 'Cliente fora do contexto autorizado.', FALSE);
  END IF;

  SELECT ops.wrap_success(
    jsonb_build_object(
      'customer',
      jsonb_build_object(
        'contact_id', c.contact_id,
        'display_name', c.full_name,
        'company_name', comp.name,
        'stage', l.stage
      )
    )
  )
  INTO response_value
  FROM core.contacts c
  LEFT JOIN core.companies comp ON comp.company_id = c.company_id
  LEFT JOIN core.leads l ON l.contact_id = c.contact_id
  WHERE c.contact_id = target_contact_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.registrar_interacao(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  interaction_row core.interactions%ROWTYPE;
  target_lead_id UUID;
  redacted_content TEXT := ops.redact_text(payload ->> 'content');
  payload_hash_value TEXT := ops.payload_hash(payload);
  response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  IF NULLIF(payload ->> 'lead_id', '') IS NULL AND NULLIF(payload ->> 'conversation_id', '') IS NULL THEN
    RETURN ops.wrap_error('LEAD_OR_CONVERSATION_REQUIRED', 'lead_id ou conversation_id obrigatorio.', FALSE);
  END IF;

  SELECT COALESCE(
    NULLIF(payload ->> 'lead_id', '')::UUID,
    (
      SELECT conv.lead_id
      FROM core.conversations conv
      WHERE conv.conversation_id::TEXT = NULLIF(payload ->> 'conversation_id', '')
      LIMIT 1
    )
  )
  INTO target_lead_id;

  IF NOT ops.is_lead_in_actor_scope(payload, target_lead_id) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));

  SELECT *
  INTO idempotency_row
  FROM ops.idempotency_inbox
  WHERE idempotency_key = payload ->> 'idempotency_key'
  FOR UPDATE;

  IF idempotency_row.inbox_id IS NOT NULL THEN
    IF idempotency_row.payload_hash <> payload_hash_value THEN
      RETURN ops.wrap_error('IDEMPOTENCY_HASH_MISMATCH', 'Mesmo idempotency_key com payload diferente.', FALSE);
    END IF;
    IF idempotency_row.completed_at IS NOT NULL THEN
      UPDATE ops.idempotency_inbox
      SET replay_count = replay_count + 1
      WHERE inbox_id = idempotency_row.inbox_id;
      RETURN idempotency_row.response_payload;
    END IF;
  ELSE
    INSERT INTO ops.idempotency_inbox (
      source_system,
      external_event_id,
      tool_name,
      idempotency_key,
      payload_hash,
      request_envelope
    )
    VALUES (
      'openclaw',
      COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'),
      'registrar_interacao',
      payload ->> 'idempotency_key',
      payload_hash_value,
      payload
    )
    RETURNING * INTO idempotency_row;
  END IF;

  INSERT INTO core.interactions (
    lead_id,
    conversation_id,
    interaction_type,
    source_message_id,
    content_redacted,
    content_hash
  )
  VALUES (
    target_lead_id,
    NULLIF(payload ->> 'conversation_id', '')::UUID,
    (payload ->> 'interaction_type')::core.interaction_type,
    payload ->> 'source_message_id',
    redacted_content,
    encode(digest(COALESCE(payload ->> 'content', ''), 'sha256'), 'hex')
  )
  RETURNING * INTO interaction_row;

  PERFORM audit.append_event(
    'interaction_stored',
    interaction_row.lead_id,
    jsonb_build_object('interaction_type', payload ->> 'interaction_type', 'content', redacted_content)
  );

  response_value := ops.wrap_success(
    jsonb_build_object('interaction_id', interaction_row.interaction_id, 'stored', TRUE),
    ARRAY['content', 'phone', 'email']
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.calcular_score(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  score_payload JSONB := COALESCE(payload -> 'facts', '{}'::jsonb);
  score_result JSONB;
  lead_uuid UUID := NULLIF(payload ->> 'lead_id', '')::UUID;
BEGIN
  score_result := ops.calculate_score_from_payload(score_payload);

  IF lead_uuid IS NOT NULL THEN
    IF NOT ops.is_lead_in_actor_scope(payload, lead_uuid) THEN
      RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
    END IF;

    UPDATE core.leads
    SET score = (score_result ->> 'score')::INTEGER,
        temperature_band = score_result ->> 'temperature_band',
        updated_at = NOW()
    WHERE lead_id = lead_uuid;
  END IF;

  RETURN ops.wrap_success(score_result);
END
$$;

CREATE OR REPLACE FUNCTION api.verificar_agenda(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT ops.integration_enabled('google_calendar_enabled') THEN
    RETURN ops.wrap_error('CALENDAR_DISABLED', 'Google Calendar desativado ou sem credencial valida.', FALSE);
  END IF;

  RETURN ops.wrap_success(
    jsonb_build_object(
      'slots', '[]'::jsonb,
      'integration_status', 'enabled',
      'dispatch_required', TRUE
    )
  );
END
$$;

CREATE OR REPLACE FUNCTION api.agendar_reuniao(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  lead_row core.leads%ROWTYPE;
  contact_row core.contacts%ROWTYPE;
  meeting_row core.meetings%ROWTYPE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  response_value JSONB;
BEGIN
  IF NOT ops.integration_enabled('google_calendar_enabled') THEN
    RETURN ops.wrap_error('CALENDAR_DISABLED', 'Google Calendar desativado ou sem credencial valida.', FALSE);
  END IF;

  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  IF COALESCE((payload ->> 'authorized')::BOOLEAN, FALSE) = FALSE THEN
    RETURN ops.wrap_error('MEETING_AUTH_REQUIRED', 'Autorizacao explicita do lead e obrigatoria.', FALSE);
  END IF;

  IF NOT ops.is_lead_in_actor_scope(payload, (payload ->> 'lead_id')::UUID) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));

  SELECT *
  INTO idempotency_row
  FROM ops.idempotency_inbox
  WHERE idempotency_key = payload ->> 'idempotency_key'
  FOR UPDATE;

  IF idempotency_row.inbox_id IS NOT NULL THEN
    IF idempotency_row.payload_hash <> payload_hash_value THEN
      RETURN ops.wrap_error('IDEMPOTENCY_HASH_MISMATCH', 'Mesmo idempotency_key com payload diferente.', FALSE);
    END IF;
    IF idempotency_row.completed_at IS NOT NULL THEN
      UPDATE ops.idempotency_inbox
      SET replay_count = replay_count + 1
      WHERE inbox_id = idempotency_row.inbox_id;
      RETURN idempotency_row.response_payload;
    END IF;
  ELSE
    INSERT INTO ops.idempotency_inbox (
      source_system,
      external_event_id,
      tool_name,
      idempotency_key,
      payload_hash,
      request_envelope
    )
    VALUES (
      'openclaw',
      COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'),
      'agendar_reuniao',
      payload ->> 'idempotency_key',
      payload_hash_value,
      payload
    )
    RETURNING * INTO idempotency_row;
  END IF;

  SELECT * INTO lead_row FROM core.leads WHERE lead_id = (payload ->> 'lead_id')::UUID;
  IF lead_row.lead_id IS NULL THEN
    RETURN ops.wrap_error('LEAD_NOT_FOUND', 'Lead nao encontrado.', FALSE);
  END IF;

  SELECT * INTO contact_row FROM core.contacts WHERE contact_id = lead_row.contact_id;

  INSERT INTO core.meetings (lead_id, contact_id, starts_at, ends_at, status, notes)
  VALUES (
    lead_row.lead_id,
    contact_row.contact_id,
    (payload ->> 'starts_at')::TIMESTAMPTZ,
    (payload ->> 'ends_at')::TIMESTAMPTZ,
    'scheduled',
    payload ->> 'notes'
  )
  RETURNING * INTO meeting_row;

  UPDATE core.leads
  SET stage = 'REUNIAO_MARCADA',
      updated_at = NOW()
  WHERE lead_id = lead_row.lead_id;

  PERFORM audit.append_event(
    'meeting_scheduled',
    lead_row.lead_id,
    jsonb_build_object('meeting_id', meeting_row.meeting_id, 'starts_at', meeting_row.starts_at, 'ends_at', meeting_row.ends_at)
  );

  response_value := ops.wrap_success(
    jsonb_build_object(
      'meeting_id', meeting_row.meeting_id,
      'status', meeting_row.status,
      'external_sync', 'pending'
    )
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.reagendar_reuniao(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  target_lead_id UUID;
  updated_meeting_id UUID;
  response_value JSONB;
BEGIN
  IF NOT ops.integration_enabled('google_calendar_enabled') THEN
    RETURN ops.wrap_error('CALENDAR_DISABLED', 'Google Calendar desativado ou sem credencial valida.', FALSE);
  END IF;

  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  SELECT lead_id INTO target_lead_id
  FROM core.meetings
  WHERE meeting_id::TEXT = payload ->> 'meeting_id';

  IF NOT ops.is_lead_in_actor_scope(payload, target_lead_id) THEN
    RETURN ops.wrap_error('MEETING_SCOPE_FORBIDDEN', 'Reuniao fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox WHERE idempotency_key = payload ->> 'idempotency_key' FOR UPDATE;

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
    VALUES ('openclaw', COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'), 'reagendar_reuniao', payload ->> 'idempotency_key', payload_hash_value, payload)
    RETURNING * INTO idempotency_row;
  END IF;

  UPDATE core.meetings
  SET starts_at = (payload ->> 'target_start_at')::TIMESTAMPTZ,
      ends_at = (payload ->> 'target_end_at')::TIMESTAMPTZ,
      status = 'rescheduled',
      updated_at = NOW()
  WHERE meeting_id = (payload ->> 'meeting_id')::UUID
  RETURNING meeting_id INTO updated_meeting_id;

  response_value := COALESCE(
    CASE
      WHEN updated_meeting_id IS NOT NULL THEN ops.wrap_success(jsonb_build_object('meeting_id', updated_meeting_id, 'rescheduled', TRUE))
      ELSE NULL
    END,
    ops.wrap_error('MEETING_NOT_FOUND', 'Reuniao nao encontrada.', FALSE)
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.cancelar_reuniao(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  target_lead_id UUID;
  updated_meeting_id UUID;
  response_value JSONB;
BEGIN
  IF NOT ops.integration_enabled('google_calendar_enabled') THEN
    RETURN ops.wrap_error('CALENDAR_DISABLED', 'Google Calendar desativado ou sem credencial valida.', FALSE);
  END IF;

  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  SELECT lead_id INTO target_lead_id
  FROM core.meetings
  WHERE meeting_id::TEXT = payload ->> 'meeting_id';

  IF NOT ops.is_lead_in_actor_scope(payload, target_lead_id) THEN
    RETURN ops.wrap_error('MEETING_SCOPE_FORBIDDEN', 'Reuniao fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox WHERE idempotency_key = payload ->> 'idempotency_key' FOR UPDATE;

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
    VALUES ('openclaw', COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'), 'cancelar_reuniao', payload ->> 'idempotency_key', payload_hash_value, payload)
    RETURNING * INTO idempotency_row;
  END IF;

  UPDATE core.meetings
  SET status = 'cancelled',
      notes = COALESCE(payload ->> 'reason', notes),
      updated_at = NOW()
  WHERE meeting_id = (payload ->> 'meeting_id')::UUID
  RETURNING meeting_id INTO updated_meeting_id;

  response_value := COALESCE(
    CASE
      WHEN updated_meeting_id IS NOT NULL THEN ops.wrap_success(jsonb_build_object('meeting_id', updated_meeting_id, 'cancelled', TRUE))
      ELSE NULL
    END,
    ops.wrap_error('MEETING_NOT_FOUND', 'Reuniao nao encontrada.', FALSE)
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.criar_resumo(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  target_lead_id UUID;
  response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'lead_id', '') IS NULL AND NULLIF(payload ->> 'conversation_id', '') IS NULL THEN
    RETURN ops.wrap_error('SUMMARY_CONTEXT_REQUIRED', 'lead_id ou conversation_id obrigatorio.', FALSE);
  END IF;

  SELECT COALESCE(
    NULLIF(payload ->> 'lead_id', '')::UUID,
    (
      SELECT conv.lead_id
      FROM core.conversations conv
      WHERE conv.conversation_id::TEXT = NULLIF(payload ->> 'conversation_id', '')
      LIMIT 1
    )
  )
  INTO target_lead_id;

  IF NOT ops.is_lead_in_actor_scope(payload, target_lead_id) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  SELECT ops.wrap_success(
    jsonb_build_object(
      'summary',
      concat_ws(
        ' | ',
        'stage=' || l.stage,
        'score=' || l.score,
        'temperatura=' || l.temperature_band,
        'necessidades=' || COALESCE(l.needs_summary, 'nao informado'),
        'ultimas_interacoes=' || COALESCE((
          SELECT string_agg(i.content_redacted, ' / ' ORDER BY i.created_at DESC)
          FROM (
            SELECT content_redacted, created_at
            FROM core.interactions
            WHERE lead_id = l.lead_id
            ORDER BY created_at DESC
            LIMIT 5
          ) i
        ), 'sem historico')
      )
    )
  )
  INTO response_value
  FROM core.leads l
  WHERE l.lead_id = target_lead_id;

  RETURN COALESCE(response_value, ops.wrap_error('LEAD_NOT_FOUND', 'Lead nao encontrado.', FALSE));
END
$$;

CREATE OR REPLACE FUNCTION api.notificar_vendedor(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  notification_row ops.notification_outbox%ROWTYPE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  response_value JSONB;
BEGIN
  IF NOT ops.integration_enabled('notification_webhook_enabled') THEN
    RETURN ops.wrap_error('NOTIFICATION_DISABLED', 'Canal de notificacao desativado ou sem credencial valida.', FALSE);
  END IF;

  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  IF payload ->> 'lead_id' IS NOT NULL
     AND NOT ops.is_lead_in_actor_scope(payload, (payload ->> 'lead_id')::UUID) THEN
    RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN', 'Lead fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox WHERE idempotency_key = payload ->> 'idempotency_key' FOR UPDATE;

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
    VALUES ('openclaw', COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'), 'notificar_vendedor', payload ->> 'idempotency_key', payload_hash_value, payload)
    RETURNING * INTO idempotency_row;
  END IF;

  INSERT INTO ops.notification_outbox (lead_id, mode, payload)
  VALUES (
    NULLIF(payload ->> 'lead_id', '')::UUID,
    'webhook',
    payload
  )
  RETURNING * INTO notification_row;

  response_value := ops.wrap_success(
    jsonb_build_object(
      'notification_id', notification_row.notification_id,
      'mode', notification_row.mode
    )
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.agendar_followup(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  followup_row core.followups%ROWTYPE;
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
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox WHERE idempotency_key = payload ->> 'idempotency_key' FOR UPDATE;

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
    VALUES ('openclaw', COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'), 'agendar_followup', payload ->> 'idempotency_key', payload_hash_value, payload)
    RETURNING * INTO idempotency_row;
  END IF;

  INSERT INTO core.followups (lead_id, policy_code, scheduled_for, status)
  VALUES (
    (payload ->> 'lead_id')::UUID,
    payload ->> 'policy_code',
    (payload ->> 'run_at')::TIMESTAMPTZ,
    'scheduled'
  )
  RETURNING * INTO followup_row;

  response_value := ops.wrap_success(
    jsonb_build_object('followup_id', followup_row.followup_id, 'scheduled', TRUE)
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.cancelar_followup(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  target_lead_id UUID;
  cancelled_followup_id UUID;
  response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  IF NULLIF(payload ->> 'followup_id', '') IS NULL AND NULLIF(payload ->> 'lead_id', '') IS NULL THEN
    RETURN ops.wrap_error('FOLLOWUP_TARGET_REQUIRED', 'followup_id ou lead_id obrigatorio.', FALSE);
  END IF;

  SELECT COALESCE(
    NULLIF(payload ->> 'lead_id', '')::UUID,
    (
      SELECT followup.lead_id
      FROM core.followups followup
      WHERE followup.followup_id::TEXT = NULLIF(payload ->> 'followup_id', '')
      LIMIT 1
    )
  )
  INTO target_lead_id;

  IF NOT ops.is_lead_in_actor_scope(payload, target_lead_id) THEN
    RETURN ops.wrap_error('FOLLOWUP_SCOPE_FORBIDDEN', 'Follow-up fora do contexto autorizado.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox WHERE idempotency_key = payload ->> 'idempotency_key' FOR UPDATE;

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
    VALUES ('openclaw', COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'), 'cancelar_followup', payload ->> 'idempotency_key', payload_hash_value, payload)
    RETURNING * INTO idempotency_row;
  END IF;

  UPDATE core.followups
  SET status = 'cancelled',
      stop_reason = COALESCE(payload ->> 'reason', 'manual'),
      updated_at = NOW()
  WHERE (
      NULLIF(payload ->> 'followup_id', '') IS NOT NULL
      AND followup_id = (payload ->> 'followup_id')::UUID
    )
    OR (
      NULLIF(payload ->> 'followup_id', '') IS NULL
      AND NULLIF(payload ->> 'lead_id', '') IS NOT NULL
      AND lead_id = (payload ->> 'lead_id')::UUID
    )
  RETURNING followup_id INTO cancelled_followup_id;

  response_value := ops.wrap_success(jsonb_build_object('cancelled', cancelled_followup_id IS NOT NULL));

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.buscar_conhecimento(payload JSONB)
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT ops.wrap_success(
    jsonb_build_object(
      'matches',
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'title', kc.title,
              'snippet', left(kc.body, 240),
              'source', kd.slug,
              'score', ts_rank(kc.body_tsv, plainto_tsquery('portuguese', payload ->> 'query'))
            )
            ORDER BY ts_rank(kc.body_tsv, plainto_tsquery('portuguese', payload ->> 'query')) DESC
          )
          FROM rag.knowledge_chunks kc
          JOIN rag.knowledge_documents kd ON kd.document_id = kc.document_id
          WHERE kc.body_tsv @@ plainto_tsquery('portuguese', payload ->> 'query')
          LIMIT 5
        ),
        '[]'::jsonb
      )
    )
  )
$$;

CREATE OR REPLACE FUNCTION api.transcrever_audio(payload JSONB)
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM ops.runtime_flags WHERE flag_name = 'audio_provider_enabled' AND enabled) THEN
      ops.wrap_success(
        jsonb_build_object(
          'transcript', 'Provider real deve ser configurado manualmente fora do Git.',
          'provider_status', 'configured_but_manual_step_required'
        )
      )
    ELSE
      ops.wrap_error('AUDIO_PROVIDER_DISABLED', 'Provider de audio desativado por seguranca.', FALSE)
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
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox WHERE idempotency_key = payload ->> 'idempotency_key' FOR UPDATE;

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
  VALUES (
    (payload ->> 'lead_id')::UUID,
    payload ->> 'reason',
    payload ->> 'priority',
    'open'
  )
  RETURNING * INTO handoff_row;

  UPDATE core.followups
  SET status = 'stopped',
      stop_reason = 'handoff',
      updated_at = NOW()
  WHERE lead_id = handoff_row.lead_id
    AND status = 'scheduled';

  response_value := ops.wrap_success(
    jsonb_build_object(
      'handoff_id', handoff_row.handoff_id,
      'blocked_automation', TRUE
    )
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.sincronizar_sheets(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  idempotency_row ops.idempotency_inbox%ROWTYPE;
  sync_row ops.sheet_sync_outbox%ROWTYPE;
  payload_hash_value TEXT := ops.payload_hash(payload);
  response_value JSONB;
BEGIN
  IF NOT ops.integration_enabled('google_sheets_enabled') THEN
    RETURN ops.wrap_error('GOOGLE_SHEETS_DISABLED', 'Google Sheets desativado ou sem credencial valida.', FALSE);
  END IF;

  IF NULLIF(payload ->> 'idempotency_key', '') IS NULL THEN
    RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED', 'Chave de idempotencia obrigatoria.', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(payload ->> 'idempotency_key'));
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox WHERE idempotency_key = payload ->> 'idempotency_key' FOR UPDATE;

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
    VALUES ('openclaw', COALESCE(payload ->> 'external_event_id', payload ->> 'request_id'), 'sincronizar_sheets', payload ->> 'idempotency_key', payload_hash_value, payload)
    RETURNING * INTO idempotency_row;
  END IF;

  INSERT INTO ops.sheet_sync_outbox (scope, payload, status)
  VALUES (
    payload ->> 'scope',
    payload,
    'queued'
  )
  RETURNING * INTO sync_row;

  response_value := ops.wrap_success(
    jsonb_build_object(
      'sync_job_id', sync_row.sync_job_id,
      'integration_status', sync_row.status
    )
  );

  UPDATE ops.idempotency_inbox
  SET response_payload = response_value,
      completed_at = NOW()
  WHERE inbox_id = idempotency_row.inbox_id;

  RETURN response_value;
END
$$;

COMMIT;
