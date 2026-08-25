BEGIN;

CREATE OR REPLACE FUNCTION ops.calculate_score_from_payload(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  total_score INTEGER := 10;
  factors JSONB := jsonb_build_array(jsonb_build_object('label', 'base', 'delta', 10));
  urgency_level TEXT := COALESCE(payload ->> 'urgency_level', 'baixa');
  budget_signal TEXT := COALESCE(payload ->> 'budget_signal', 'nenhum');
  authority_level TEXT := COALESCE(payload ->> 'authority_level', 'incerto');
  inbound_intent TEXT := COALESCE(payload ->> 'inbound_intent', 'fraca');
  existing_channels TEXT := COALESCE(payload ->> 'existing_channels', 'nenhum');
BEGIN
  IF COALESCE((payload ->> 'has_defined_offer')::BOOLEAN, FALSE) THEN total_score := total_score + 15; factors := factors || jsonb_build_array(jsonb_build_object('label','oferta_definida','delta',15)); END IF;
  total_score := total_score + CASE urgency_level WHEN 'media' THEN 12 WHEN 'alta' THEN 22 ELSE 4 END;
  total_score := total_score + CASE budget_signal WHEN 'baixo' THEN 6 WHEN 'medio' THEN 12 WHEN 'alto' THEN 18 ELSE 2 END;
  total_score := total_score + CASE authority_level WHEN 'influenciador' THEN 8 WHEN 'decisor' THEN 14 ELSE 2 END;
  total_score := total_score + CASE inbound_intent WHEN 'moderada' THEN 10 WHEN 'forte' THEN 18 ELSE 3 END;
  total_score := total_score + CASE existing_channels WHEN 'organico' THEN 6 WHEN 'pago' THEN 8 WHEN 'misto' THEN 10 ELSE 2 END;
  IF COALESCE((payload ->> 'wants_meeting')::BOOLEAN, FALSE) THEN total_score := total_score + 14; END IF;
  IF COALESCE((payload ->> 'asks_for_proposal')::BOOLEAN, FALSE) THEN total_score := total_score + 18; END IF;
  total_score := LEAST(100, GREATEST(0, total_score));
  RETURN jsonb_build_object('score',total_score,'temperature_band',ops.temperature_band(total_score),'factors',factors);
END
$$;

CREATE OR REPLACE FUNCTION api.buscar_servicos(payload JSONB)
RETURNS JSONB LANGUAGE SQL AS $$
  SELECT ops.wrap_success(jsonb_build_object('services',COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'service_id',s.service_id,'slug',s.slug,'name',s.name,'summary',s.summary,'pricing_mode',s.pricing_mode,
      'upsells',COALESCE((SELECT jsonb_agg(s2.slug ORDER BY s2.slug) FROM core.service_upsells su JOIN core.services s2 ON s2.service_id=su.upsell_service_id WHERE su.service_id=s.service_id),'[]'::jsonb)
    ) ORDER BY s.name)
    FROM core.services s
    WHERE (payload ->> 'category' IS NULL OR s.category=payload ->> 'category')
      AND (COALESCE((payload ->> 'active_only')::BOOLEAN,TRUE)=FALSE OR s.active=TRUE)
      AND (payload -> 'service_ids' IS NULL OR s.slug IN (SELECT jsonb_array_elements_text(payload -> 'service_ids')))
  ),'[]'::jsonb)))
$$;

CREATE OR REPLACE FUNCTION api.buscar_servico(payload JSONB)
RETURNS JSONB LANGUAGE SQL AS $$
  SELECT COALESCE((
    SELECT ops.wrap_success(jsonb_build_object('service',jsonb_build_object(
      'service_id',s.service_id,'slug',s.slug,'name',s.name,'summary',s.summary,
      'qualification_hint',s.qualification_hint,'pricing_mode',s.pricing_mode
    )))
    FROM core.services s
    WHERE s.slug=COALESCE(payload ->> 'slug',payload ->> 'service_id') OR lower(s.name)=lower(COALESCE(payload ->> 'name',''))
    LIMIT 1
  ),ops.wrap_error('SERVICE_NOT_FOUND','Servico nao encontrado.',FALSE))
$$;

CREATE OR REPLACE FUNCTION api.buscar_precos(payload JSONB)
RETURNS JSONB LANGUAGE SQL AS $$
  SELECT ops.wrap_success(jsonb_build_object('prices',COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'service_id',s.service_id,'pricing_mode',s.pricing_mode,'price_from',s.price_from,
      'price_to',s.price_to,'currency',s.currency,'sob_consulta',s.price_from IS NULL AND s.price_to IS NULL
    ))
    FROM core.services s WHERE s.slug IN (SELECT jsonb_array_elements_text(payload -> 'service_ids'))
  ),'[]'::jsonb)))
$$;

CREATE OR REPLACE FUNCTION api.verificar_agenda(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT ops.integration_enabled('google_calendar_enabled') THEN RETURN ops.wrap_error('CALENDAR_DISABLED','Google Calendar desativado ou sem credencial valida.',FALSE); END IF;
  RETURN ops.wrap_success(jsonb_build_object('slots','[]'::jsonb,'integration_status','enabled','dispatch_required',TRUE));
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
  IF NULLIF(payload ->> 'idempotency_key','') IS NULL THEN RETURN ops.wrap_error('IDEMPOTENCY_REQUIRED','Chave de idempotencia obrigatoria.',FALSE); END IF;
  IF NULLIF(payload ->> 'lead_id','') IS NULL THEN RETURN ops.wrap_error('LEAD_ID_REQUIRED','lead_id obrigatorio.',FALSE); END IF;
  IF payload -> 'context' ->> 'lead_id' IS NOT NULL AND payload ->> 'lead_id' IS NOT NULL AND payload -> 'context' ->> 'lead_id' <> payload ->> 'lead_id' THEN RETURN ops.wrap_error('LEAD_CONTEXT_MISMATCH','Contexto do lead divergente.',FALSE); END IF;
  IF NOT ops.is_lead_in_actor_scope(payload,(payload ->> 'lead_id')::UUID) THEN RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN','Lead fora do contexto autorizado.',FALSE); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('atualizar_lead:' || (payload ->> 'idempotency_key')));
  SELECT * INTO idempotency_row FROM ops.idempotency_inbox WHERE idempotency_key=payload ->> 'idempotency_key' AND tool_name='atualizar_lead' FOR UPDATE;
  IF idempotency_row.inbox_id IS NOT NULL THEN
    IF idempotency_row.payload_hash<>payload_hash_value THEN RETURN ops.wrap_error('IDEMPOTENCY_HASH_MISMATCH','Mesmo idempotency_key com payload diferente.',FALSE); END IF;
    IF idempotency_row.completed_at IS NOT NULL THEN UPDATE ops.idempotency_inbox SET replay_count=replay_count+1 WHERE inbox_id=idempotency_row.inbox_id; RETURN idempotency_row.response_payload; END IF;
  ELSE
    INSERT INTO ops.idempotency_inbox(source_system,external_event_id,tool_name,idempotency_key,payload_hash,request_envelope)
    VALUES('openclaw',COALESCE(payload ->> 'external_event_id',payload ->> 'request_id'),'atualizar_lead',payload ->> 'idempotency_key',payload_hash_value,payload)
    RETURNING * INTO idempotency_row;
  END IF;
  UPDATE core.leads SET
    stage=COALESCE((payload ->> 'stage')::core.lead_stage,stage),
    needs_summary=COALESCE(array_to_string(ARRAY(SELECT jsonb_array_elements_text(payload -> 'needs')),'; '),needs_summary),
    indicative_budget=COALESCE(payload ->> 'indicative_budget',indicative_budget),
    urgency=COALESCE(payload ->> 'urgency',urgency),origin_detail=COALESCE(payload ->> 'origin',origin_detail),
    owner_name=COALESCE(payload ->> 'owner',owner_name),updated_at=NOW()
  WHERE lead_id=(payload ->> 'lead_id')::UUID RETURNING lead_id INTO updated_lead_id;
  response_value := COALESCE(CASE WHEN updated_lead_id IS NOT NULL THEN ops.wrap_success(jsonb_build_object('lead_id',updated_lead_id,'updated',TRUE)) END,ops.wrap_error('LEAD_NOT_FOUND','Lead nao encontrado.',FALSE));
  UPDATE ops.idempotency_inbox SET response_payload=response_value,completed_at=NOW() WHERE inbox_id=idempotency_row.inbox_id;
  RETURN response_value;
END
$$;

CREATE OR REPLACE FUNCTION api.buscar_lead(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE target_lead_id UUID; response_value JSONB;
BEGIN
  IF NULLIF(payload ->> 'lead_id','') IS NULL AND NULLIF(payload ->> 'phone','') IS NULL AND NULLIF(payload ->> 'email','') IS NULL THEN RETURN ops.wrap_error('LEAD_LOOKUP_REQUIRED','Informe lead_id, phone ou email.',FALSE); END IF;
  SELECT l.lead_id INTO target_lead_id FROM core.leads l JOIN core.contacts c ON c.contact_id=l.contact_id
  WHERE (NULLIF(payload ->> 'lead_id','') IS NOT NULL AND l.lead_id::TEXT=payload ->> 'lead_id')
     OR (NULLIF(payload ->> 'phone','') IS NOT NULL AND c.normalized_phone=ops.normalize_phone(payload ->> 'phone'))
     OR (NULLIF(payload ->> 'email','') IS NOT NULL AND c.email=lower(NULLIF(payload ->> 'email',''))) LIMIT 1;
  IF target_lead_id IS NULL THEN RETURN ops.wrap_error('LEAD_NOT_FOUND','Lead nao encontrado.',FALSE); END IF;
  IF NOT ops.is_lead_in_actor_scope(payload,target_lead_id) THEN RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN','Lead fora do contexto autorizado.',FALSE); END IF;
  SELECT ops.wrap_success(jsonb_build_object('lead',jsonb_build_object(
    'lead_id',l.lead_id,'stage',l.stage,'score',l.score,'temperature_band',l.temperature_band,
    'needs',COALESCE(string_to_array(l.needs_summary,'; '),ARRAY[]::TEXT[]),
    'handoff',(SELECT jsonb_build_object('handoff_id',h.handoff_id,'status',h.status,'priority',h.priority) FROM core.handoffs h WHERE h.lead_id=l.lead_id AND h.status IN ('open','acknowledged') ORDER BY h.created_at DESC LIMIT 1)
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
  IF NULLIF(payload ->> 'lead_id','') IS NULL AND NULLIF(payload ->> 'conversation_id','') IS NULL THEN RETURN ops.wrap_error('SUMMARY_CONTEXT_REQUIRED','lead_id ou conversation_id obrigatorio.',FALSE); END IF;
  SELECT COALESCE(NULLIF(payload ->> 'lead_id','')::UUID,(SELECT c.lead_id FROM core.conversations c WHERE c.conversation_id::TEXT=NULLIF(payload ->> 'conversation_id','') LIMIT 1)) INTO target_lead_id;
  IF NOT ops.is_lead_in_actor_scope(payload,target_lead_id) THEN RETURN ops.wrap_error('LEAD_SCOPE_FORBIDDEN','Lead fora do contexto autorizado.',FALSE); END IF;
  SELECT ops.wrap_success(jsonb_build_object('summary',concat_ws(' | ',
    'stage='||l.stage,'score='||l.score,'temperatura='||l.temperature_band,
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
    WHEN EXISTS (SELECT 1 FROM ops.runtime_flags WHERE flag_name='audio_provider_enabled' AND enabled) THEN
      ops.wrap_success(jsonb_build_object('transcript','Provider real deve ser configurado manualmente fora do Git.','provider_status','configured_but_manual_step_required'))
    ELSE ops.wrap_error('AUDIO_PROVIDER_DISABLED','Provider de audio desativado por seguranca.',FALSE)
  END
$$;

DROP INDEX IF EXISTS core.idx_calendar_blocks_range;
DROP INDEX IF EXISTS core.idx_score_rules_active;
DROP INDEX IF EXISTS ops.idx_metrics_name_created;
DROP TABLE IF EXISTS core.calendar_blocks;
DROP TABLE IF EXISTS core.business_hours;
DROP TABLE IF EXISTS core.score_rules;

ALTER TABLE rag.knowledge_documents DROP COLUMN IF EXISTS updated_at;
ALTER TABLE core.portfolio_items DROP COLUMN IF EXISTS updated_at;
ALTER TABLE core.portfolio_items DROP COLUMN IF EXISTS outcome_summary;
ALTER TABLE core.portfolio_items DROP COLUMN IF EXISTS technologies;
ALTER TABLE core.portfolio_items DROP COLUMN IF EXISTS image_url;
ALTER TABLE core.portfolio_items DROP COLUMN IF EXISTS project_url;
ALTER TABLE core.services DROP COLUMN IF EXISTS updated_at;
ALTER TABLE core.services DROP COLUMN IF EXISTS commercial_url;
ALTER TABLE core.services DROP COLUMN IF EXISTS duration_estimate;
ALTER TABLE core.leads DROP COLUMN IF EXISTS tags;
ALTER TABLE core.leads DROP COLUMN IF EXISTS notes_redacted;
ALTER TABLE core.leads DROP COLUMN IF EXISTS team_size;
ALTER TABLE core.leads DROP COLUMN IF EXISTS has_crm;
ALTER TABLE core.leads DROP COLUMN IF EXISTS has_google_business;
ALTER TABLE core.leads DROP COLUMN IF EXISTS acquisition_channels;
ALTER TABLE core.leads DROP COLUMN IF EXISTS deadline;
ALTER TABLE core.leads DROP COLUMN IF EXISTS service_interests;
ALTER TABLE core.leads DROP COLUMN IF EXISTS problem_summary;
ALTER TABLE core.leads DROP COLUMN IF EXISTS objective;
ALTER TABLE core.leads DROP COLUMN IF EXISTS city;
ALTER TABLE core.leads DROP COLUMN IF EXISTS segment;
ALTER TABLE core.contacts DROP COLUMN IF EXISTS instagram_handle;
ALTER TABLE core.contacts DROP COLUMN IF EXISTS region;
ALTER TABLE core.contacts DROP COLUMN IF EXISTS city;
ALTER TABLE core.companies DROP COLUMN IF EXISTS instagram_url;
ALTER TABLE core.companies DROP COLUMN IF EXISTS region;
ALTER TABLE core.companies DROP COLUMN IF EXISTS city;
ALTER TABLE core.companies DROP COLUMN IF EXISTS segment;

COMMIT;
