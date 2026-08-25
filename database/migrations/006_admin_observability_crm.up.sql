BEGIN;

ALTER TABLE core.companies ADD COLUMN IF NOT EXISTS segment TEXT;
ALTER TABLE core.companies ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE core.companies ADD COLUMN IF NOT EXISTS region TEXT;
ALTER TABLE core.companies ADD COLUMN IF NOT EXISTS instagram_url TEXT;

ALTER TABLE core.contacts ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE core.contacts ADD COLUMN IF NOT EXISTS region TEXT;
ALTER TABLE core.contacts ADD COLUMN IF NOT EXISTS instagram_handle TEXT;

ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS segment TEXT;
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS objective TEXT;
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS problem_summary TEXT;
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS service_interests TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS deadline TEXT;
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS acquisition_channels TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS has_google_business BOOLEAN;
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS has_crm BOOLEAN;
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS team_size INTEGER CHECK (team_size IS NULL OR team_size >= 0);
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS notes_redacted TEXT;
ALTER TABLE core.leads ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE core.services ADD COLUMN IF NOT EXISTS duration_estimate TEXT;
ALTER TABLE core.services ADD COLUMN IF NOT EXISTS commercial_url TEXT;
ALTER TABLE core.services ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE core.portfolio_items ADD COLUMN IF NOT EXISTS project_url TEXT;
ALTER TABLE core.portfolio_items ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE core.portfolio_items ADD COLUMN IF NOT EXISTS technologies TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
ALTER TABLE core.portfolio_items ADD COLUMN IF NOT EXISTS outcome_summary TEXT;
ALTER TABLE core.portfolio_items ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE rag.knowledge_documents ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE TABLE IF NOT EXISTS core.score_rules (
  rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  fact_key TEXT NOT NULL,
  match_value TEXT NOT NULL,
  label TEXT NOT NULL,
  delta INTEGER NOT NULL CHECK (delta BETWEEN -100 AND 100),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS core.business_hours (
  weekday SMALLINT PRIMARY KEY CHECK (weekday BETWEEN 0 AND 6),
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  opens_at TIME NOT NULL DEFAULT '09:00',
  closes_at TIME NOT NULL DEFAULT '18:00',
  timezone TEXT NOT NULL DEFAULT 'America/Sao_Paulo',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (closes_at > opens_at)
);

CREATE TABLE IF NOT EXISTS core.calendar_blocks (
  block_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  reason TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (ends_at > starts_at)
);

INSERT INTO core.score_rules(code,fact_key,match_value,label,delta)
VALUES
  ('base','__base__','*','base',10),
  ('offer-defined','has_defined_offer','true','oferta_definida',15),
  ('urgency-low','urgency_level','baixa','urgencia_baixa',4),
  ('urgency-medium','urgency_level','media','urgencia_media',12),
  ('urgency-high','urgency_level','alta','urgencia_alta',22),
  ('budget-none','budget_signal','nenhum','orcamento_nao_informado',2),
  ('budget-low','budget_signal','baixo','orcamento_baixo',6),
  ('budget-medium','budget_signal','medio','orcamento_medio',12),
  ('budget-high','budget_signal','alto','orcamento_alto',18),
  ('authority-unknown','authority_level','incerto','autoridade_incerta',2),
  ('authority-influencer','authority_level','influenciador','influenciador',8),
  ('authority-decision','authority_level','decisor','decisor',14),
  ('intent-low','inbound_intent','fraca','intencao_fraca',3),
  ('intent-medium','inbound_intent','moderada','intencao_moderada',10),
  ('intent-high','inbound_intent','forte','intencao_forte',18),
  ('channels-none','existing_channels','nenhum','sem_canal',2),
  ('channels-organic','existing_channels','organico','canal_organico',6),
  ('channels-paid','existing_channels','pago','canal_pago',8),
  ('channels-mixed','existing_channels','misto','canais_mistos',10),
  ('wants-meeting','wants_meeting','true','quer_reuniao',14),
  ('asks-proposal','asks_for_proposal','true','pede_proposta',18)
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.business_hours(weekday,enabled,opens_at,closes_at)
VALUES
  (0,FALSE,'09:00','18:00'),
  (1,TRUE,'09:00','18:00'),
  (2,TRUE,'09:00','18:00'),
  (3,TRUE,'09:00','18:00'),
  (4,TRUE,'09:00','18:00'),
  (5,TRUE,'09:00','18:00'),
  (6,FALSE,'09:00','18:00')
ON CONFLICT (weekday) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_metrics_name_created ON ops.metrics_events(metric_name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_score_rules_active ON core.score_rules(active, fact_key);
CREATE INDEX IF NOT EXISTS idx_calendar_blocks_range ON core.calendar_blocks(starts_at, ends_at) WHERE active;

CREATE OR REPLACE FUNCTION ops.calculate_score_from_payload(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  total_score INTEGER;
  factors JSONB;
BEGIN
  SELECT COALESCE(sum(rule.delta), 0)::INTEGER,
         COALESCE(jsonb_agg(jsonb_build_object('label', rule.label, 'delta', rule.delta) ORDER BY rule.code), '[]'::jsonb)
  INTO total_score, factors
  FROM core.score_rules rule
  WHERE rule.active
    AND (
      rule.fact_key = '__base__'
      OR COALESCE(
        payload ->> rule.fact_key,
        CASE rule.fact_key
          WHEN 'urgency_level' THEN 'baixa'
          WHEN 'budget_signal' THEN 'nenhum'
          WHEN 'authority_level' THEN 'incerto'
          WHEN 'inbound_intent' THEN 'fraca'
          WHEN 'existing_channels' THEN 'nenhum'
          ELSE ''
        END
      ) = rule.match_value
    );

  total_score := LEAST(100, GREATEST(0, total_score));
  RETURN jsonb_build_object(
    'score', total_score,
    'temperature_band', ops.temperature_band(total_score),
    'factors', factors
  );
END
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
              'duration_estimate', s.duration_estimate,
              'commercial_url', s.commercial_url,
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
              OR s.slug IN (SELECT jsonb_array_elements_text(payload -> 'service_ids'))
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
            'pricing_mode', s.pricing_mode,
            'duration_estimate', s.duration_estimate,
            'commercial_url', s.commercial_url
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
              'slug', s.slug,
              'name', s.name,
              'pricing_mode', s.pricing_mode,
              'price_from', s.price_from,
              'price_to', s.price_to,
              'currency', s.currency,
              'duration_estimate', s.duration_estimate,
              'commercial_url', s.commercial_url,
              'sob_consulta', s.pricing_mode = 'sob_consulta' OR (s.price_from IS NULL AND s.price_to IS NULL)
            )
            ORDER BY s.name
          )
          FROM core.services s
          WHERE s.slug IN (SELECT jsonb_array_elements_text(payload -> 'service_ids'))
             OR s.service_id::TEXT IN (SELECT jsonb_array_elements_text(payload -> 'service_ids'))
        ),
        '[]'::jsonb
      )
    )
  )
$$;

CREATE OR REPLACE FUNCTION api.verificar_agenda(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  requested_start TIMESTAMPTZ;
  requested_end TIMESTAMPTZ;
  duration_minutes INTEGER;
  slots JSONB;
BEGIN
  BEGIN
    requested_start := (payload ->> 'start_at')::TIMESTAMPTZ;
    requested_end := (payload ->> 'end_at')::TIMESTAMPTZ;
    duration_minutes := (payload ->> 'duration_minutes')::INTEGER;
  EXCEPTION WHEN OTHERS THEN
    RETURN ops.wrap_error('CALENDAR_WINDOW_INVALID','Janela de agenda invalida.',FALSE);
  END;
  IF requested_end <= requested_start OR duration_minutes < 15 OR duration_minutes > 180 THEN
    RETURN ops.wrap_error('CALENDAR_WINDOW_INVALID','Janela ou duracao de agenda invalida.',FALSE);
  END IF;

  IF payload ->> 'channel' = 'test' AND COALESCE((payload ->> 'fixture_mode')::BOOLEAN,FALSE) THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'starts_at',candidate_start,
      'ends_at',candidate_start + make_interval(mins => duration_minutes),
      'channel','fixture'
    ) ORDER BY candidate_start),'[]'::jsonb)
    INTO slots
    FROM (
      SELECT candidate_start
      FROM generate_series(requested_start,requested_end - make_interval(mins => duration_minutes),make_interval(mins => duration_minutes)) candidate_start
      JOIN core.business_hours hours ON hours.weekday=EXTRACT(DOW FROM candidate_start AT TIME ZONE hours.timezone)::INTEGER
      WHERE hours.enabled
        AND (candidate_start AT TIME ZONE hours.timezone)::TIME >= hours.opens_at
        AND ((candidate_start + make_interval(mins => duration_minutes)) AT TIME ZONE hours.timezone)::TIME <= hours.closes_at
        AND NOT tstzrange(candidate_start,candidate_start + make_interval(mins => duration_minutes),'[)') && tstzrange('2026-08-24T13:00:00-03:00','2026-08-24T14:00:00-03:00','[)')
        AND NOT EXISTS (SELECT 1 FROM core.calendar_blocks block WHERE block.active AND tstzrange(candidate_start,candidate_start + make_interval(mins => duration_minutes),'[)') && tstzrange(block.starts_at,block.ends_at,'[)'))
        AND NOT EXISTS (SELECT 1 FROM core.meetings meeting WHERE meeting.status IN ('pending','scheduled','rescheduled') AND tstzrange(candidate_start,candidate_start + make_interval(mins => duration_minutes),'[)') && tstzrange(meeting.starts_at,meeting.ends_at,'[)'))
      ORDER BY candidate_start
      LIMIT 20
    ) available;
    RETURN ops.wrap_success(jsonb_build_object('slots',slots,'integration_status','fixture','dispatch_required',FALSE));
  END IF;

  IF NOT ops.integration_enabled('google_calendar_enabled') THEN
    RETURN ops.wrap_error('CALENDAR_DISABLED','Google Calendar desativado ou sem credencial valida.',FALSE);
  END IF;
  RETURN ops.wrap_success(jsonb_build_object('slots','[]'::jsonb,'integration_status','oauth_dispatch_required','dispatch_required',TRUE));
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

  PERFORM pg_advisory_xact_lock(hashtext('atualizar_lead:' || (payload ->> 'idempotency_key')));
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox
  WHERE idempotency_key = payload ->> 'idempotency_key' AND tool_name = 'atualizar_lead' FOR UPDATE;
  IF idempotency_row.inbox_id IS NOT NULL THEN
    IF idempotency_row.payload_hash <> payload_hash_value THEN
      RETURN ops.wrap_error('IDEMPOTENCY_HASH_MISMATCH', 'Mesmo idempotency_key com payload diferente.', FALSE);
    END IF;
    IF idempotency_row.completed_at IS NOT NULL THEN
      UPDATE ops.idempotency_inbox SET replay_count = replay_count + 1 WHERE inbox_id = idempotency_row.inbox_id;
      RETURN idempotency_row.response_payload;
    END IF;
  ELSE
    INSERT INTO ops.idempotency_inbox(source_system,external_event_id,tool_name,idempotency_key,payload_hash,request_envelope)
    VALUES('openclaw',COALESCE(payload ->> 'external_event_id',payload ->> 'request_id'),'atualizar_lead',payload ->> 'idempotency_key',payload_hash_value,payload)
    RETURNING * INTO idempotency_row;
  END IF;

  UPDATE core.leads
  SET stage = COALESCE((payload ->> 'stage')::core.lead_stage, stage),
      needs_summary = COALESCE(array_to_string(ARRAY(SELECT jsonb_array_elements_text(payload -> 'needs')), '; '), needs_summary),
      indicative_budget = COALESCE(payload ->> 'indicative_budget', indicative_budget),
      urgency = COALESCE(payload ->> 'urgency', urgency),
      origin_detail = COALESCE(payload ->> 'origin', origin_detail),
      owner_name = COALESCE(payload ->> 'owner', owner_name),
      segment = COALESCE(payload ->> 'segment', segment),
      city = COALESCE(payload ->> 'city', city),
      objective = COALESCE(payload ->> 'objective', objective),
      problem_summary = COALESCE(payload ->> 'problem_summary', problem_summary),
      service_interests = CASE WHEN payload ? 'service_interests' THEN ARRAY(SELECT jsonb_array_elements_text(payload -> 'service_interests')) ELSE service_interests END,
      deadline = COALESCE(payload ->> 'deadline', deadline),
      acquisition_channels = CASE WHEN payload ? 'acquisition_channels' THEN ARRAY(SELECT jsonb_array_elements_text(payload -> 'acquisition_channels')) ELSE acquisition_channels END,
      has_google_business = COALESCE((payload ->> 'has_google_business')::BOOLEAN, has_google_business),
      has_crm = COALESCE((payload ->> 'has_crm')::BOOLEAN, has_crm),
      team_size = COALESCE((payload ->> 'team_size')::INTEGER, team_size),
      notes_redacted = COALESCE(ops.redact_text(payload ->> 'notes'), notes_redacted),
      tags = CASE WHEN payload ? 'tags' THEN ARRAY(SELECT jsonb_array_elements_text(payload -> 'tags')) ELSE tags END,
      updated_at = NOW()
  WHERE lead_id = (payload ->> 'lead_id')::UUID
  RETURNING lead_id INTO updated_lead_id;

  response_value := COALESCE(
    CASE WHEN updated_lead_id IS NOT NULL THEN ops.wrap_success(jsonb_build_object('lead_id',updated_lead_id,'updated',TRUE),ARRAY['notes']) END,
    ops.wrap_error('LEAD_NOT_FOUND','Lead nao encontrado.',FALSE)
  );
  UPDATE ops.idempotency_inbox SET response_payload=response_value,completed_at=NOW() WHERE inbox_id=idempotency_row.inbox_id;
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
  IF NULLIF(payload ->> 'lead_id', '') IS NULL AND NULLIF(payload ->> 'phone', '') IS NULL AND NULLIF(payload ->> 'email', '') IS NULL THEN
    RETURN ops.wrap_error('LEAD_LOOKUP_REQUIRED','Informe lead_id, phone ou email.',FALSE);
  END IF;
  SELECT l.lead_id INTO target_lead_id
  FROM core.leads l JOIN core.contacts c ON c.contact_id=l.contact_id
  WHERE (NULLIF(payload ->> 'lead_id','') IS NOT NULL AND l.lead_id::TEXT=payload ->> 'lead_id')
     OR (NULLIF(payload ->> 'phone','') IS NOT NULL AND c.normalized_phone=ops.normalize_phone(payload ->> 'phone'))
     OR (NULLIF(payload ->> 'email','') IS NOT NULL AND c.email=lower(NULLIF(payload ->> 'email','')))
  LIMIT 1;
  IF target_lead_id IS NULL THEN RETURN ops.wrap_error('LEAD_NOT_FOUND','Lead nao encontrado.',FALSE); END IF;
  IF NOT ops.is_lead_in_actor_scope(payload,target_lead_id) THEN RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN','Lead fora do contexto autorizado.',FALSE); END IF;

  SELECT ops.wrap_success(jsonb_build_object('lead',jsonb_build_object(
    'lead_id',l.lead_id,'stage',l.stage,'score',l.score,'temperature_band',l.temperature_band,
    'needs',COALESCE(string_to_array(l.needs_summary,'; '),ARRAY[]::TEXT[]),
    'segment',l.segment,'city',l.city,'objective',l.objective,'problem_summary',l.problem_summary,
    'service_interests',l.service_interests,'deadline',l.deadline,'acquisition_channels',l.acquisition_channels,
    'has_google_business',l.has_google_business,'has_crm',l.has_crm,'team_size',l.team_size,'tags',l.tags,
    'handoff',(SELECT jsonb_build_object('handoff_id',h.handoff_id,'status',h.status,'priority',h.priority)
      FROM core.handoffs h WHERE h.lead_id=l.lead_id AND h.status IN ('open','acknowledged') ORDER BY h.created_at DESC LIMIT 1)
  ))) INTO response_value FROM core.leads l WHERE l.lead_id=target_lead_id;
  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.criar_resumo(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE target_lead_id UUID; response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'lead_id','') IS NULL AND NULLIF(payload ->> 'conversation_id','') IS NULL THEN
    RETURN ops.wrap_error('SUMMARY_CONTEXT_REQUIRED','lead_id ou conversation_id obrigatorio.',FALSE);
  END IF;
  SELECT COALESCE(NULLIF(payload ->> 'lead_id','')::UUID,(SELECT c.lead_id FROM core.conversations c WHERE c.conversation_id::TEXT=NULLIF(payload ->> 'conversation_id','') LIMIT 1)) INTO target_lead_id;
  IF NOT ops.is_lead_in_actor_scope(payload,target_lead_id) THEN RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN','Lead fora do contexto autorizado.',FALSE); END IF;
  SELECT ops.wrap_success(jsonb_build_object('summary',concat_ws(' | ',
    'stage='||l.stage,'score='||l.score,'temperatura='||l.temperature_band,
    'segmento='||COALESCE(l.segment,'nao informado'),'cidade='||COALESCE(l.city,'nao informada'),
    'objetivo='||COALESCE(l.objective,'nao informado'),'problema='||COALESCE(l.problem_summary,'nao informado'),
    'servicos='||COALESCE(array_to_string(l.service_interests,', '),'nao informado'),
    'orcamento='||COALESCE(l.indicative_budget,'nao informado'),'prazo='||COALESCE(l.deadline,'nao informado'),
    'necessidades='||COALESCE(l.needs_summary,'nao informado'),
    'ultimas_interacoes='||COALESCE((SELECT string_agg(i.content_redacted,' / ' ORDER BY i.created_at DESC) FROM (SELECT content_redacted,created_at FROM core.interactions WHERE lead_id=l.lead_id ORDER BY created_at DESC LIMIT 5) i),'sem historico')
  ))) INTO response_value FROM core.leads l WHERE l.lead_id=target_lead_id;
  RETURN COALESCE(response_value,ops.wrap_error('LEAD_NOT_FOUND','Lead nao encontrado.',FALSE));
END
$$;

CREATE OR REPLACE FUNCTION api.transcrever_audio(payload JSONB)
RETURNS JSONB
LANGUAGE SQL
AS $$
  SELECT CASE
    WHEN payload ->> 'channel' = 'test' AND payload ->> 'audio_ref' = 'fixture://audio-ptbr-comercial' THEN
      ops.wrap_success(jsonb_build_object(
        'transcript', 'Quero automatizar o atendimento da minha loja pelo WhatsApp e integrar com o CRM.',
        'provider_status', 'fixture'
      ))
    WHEN EXISTS (SELECT 1 FROM ops.runtime_flags WHERE flag_name = 'audio_provider_enabled' AND enabled) THEN
      ops.wrap_error('AUDIO_ADAPTER_NOT_CONFIGURED', 'Provider habilitado, mas o adaptador de transcricao ainda nao possui credencial valida.', FALSE)
    ELSE
      ops.wrap_error('AUDIO_PROVIDER_DISABLED', 'Provider de audio desativado por seguranca.', FALSE)
  END
$$;

COMMIT;
