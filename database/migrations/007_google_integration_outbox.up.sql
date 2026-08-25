BEGIN;

ALTER TABLE core.meetings
  ADD COLUMN IF NOT EXISTS external_meet_url TEXT,
  ADD COLUMN IF NOT EXISTS external_sync_status TEXT NOT NULL DEFAULT 'not_requested',
  ADD COLUMN IF NOT EXISTS external_sync_error_code TEXT,
  ADD COLUMN IF NOT EXISTS external_sync_updated_at TIMESTAMPTZ;

ALTER TABLE core.calendar_blocks
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS external_key TEXT,
  ADD COLUMN IF NOT EXISTS refreshed_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS uq_calendar_blocks_source_external
  ON core.calendar_blocks (source, external_key);

CREATE TABLE IF NOT EXISTS ops.calendar_sync_state (
  provider TEXT PRIMARY KEY,
  coverage_start TIMESTAMPTZ NOT NULL,
  coverage_end TIMESTAMPTZ NOT NULL,
  last_success_at TIMESTAMPTZ NOT NULL,
  last_error_code TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (coverage_end > coverage_start)
);

CREATE TABLE IF NOT EXISTS ops.calendar_integration_jobs (
  job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id UUID NOT NULL REFERENCES core.meetings(meeting_id) ON DELETE CASCADE,
  operation TEXT NOT NULL CHECK (operation IN ('create', 'update', 'delete')),
  dedupe_key TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'claimed', 'retry', 'completed', 'failed', 'cancelled')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  claimed_at TIMESTAMPTZ,
  last_error_code TEXT,
  external_event_id TEXT,
  result_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_calendar_integration_jobs_claim
  ON ops.calendar_integration_jobs (operation, status, available_at, created_at);

ALTER TABLE ops.sheet_sync_outbox
  ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_error_code TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE ops.sheet_sync_outbox
  DROP CONSTRAINT IF EXISTS sheet_sync_outbox_attempts_check;

ALTER TABLE ops.sheet_sync_outbox
  ADD CONSTRAINT sheet_sync_outbox_attempts_check CHECK (attempts BETWEEN 0 AND 3);

CREATE INDEX IF NOT EXISTS idx_sheet_sync_outbox_claim
  ON ops.sheet_sync_outbox (status, available_at, created_at);

CREATE OR REPLACE FUNCTION ops.enqueue_calendar_integration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
DECLARE
  target_operation TEXT;
  target_key TEXT;
BEGIN
  IF NOT ops.integration_enabled('google_calendar_enabled') THEN
    RETURN NEW;
  END IF;

  UPDATE ops.calendar_integration_jobs
  SET status = 'cancelled',
      updated_at = NOW()
  WHERE meeting_id = NEW.meeting_id
    AND status IN ('queued', 'retry');

  IF NEW.status = 'cancelled' AND NULLIF(NEW.external_event_id, '') IS NULL THEN
    UPDATE core.meetings
    SET external_sync_status = 'not_required',
        external_sync_error_code = NULL,
        external_sync_updated_at = NOW()
    WHERE meeting_id = NEW.meeting_id;
    RETURN NEW;
  END IF;

  target_operation := CASE
    WHEN NEW.status = 'cancelled' THEN 'delete'
    WHEN NULLIF(NEW.external_event_id, '') IS NULL THEN 'create'
    ELSE 'update'
  END;

  target_key := encode(
    public.digest(
      concat_ws(':', NEW.meeting_id::TEXT, target_operation, NEW.starts_at::TEXT, NEW.ends_at::TEXT, NEW.status::TEXT, COALESCE(NEW.external_event_id, '')),
      'sha256'
    ),
    'hex'
  );

  INSERT INTO ops.calendar_integration_jobs (meeting_id, operation, dedupe_key)
  VALUES (NEW.meeting_id, target_operation, target_key)
  ON CONFLICT (dedupe_key) DO NOTHING;

  UPDATE core.meetings
  SET external_sync_status = 'queued',
      external_sync_error_code = NULL,
      external_sync_updated_at = NOW()
  WHERE meeting_id = NEW.meeting_id;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_enqueue_calendar_integration ON core.meetings;
CREATE TRIGGER trg_enqueue_calendar_integration
AFTER INSERT OR UPDATE OF starts_at, ends_at, status ON core.meetings
FOR EACH ROW
EXECUTE FUNCTION ops.enqueue_calendar_integration();

CREATE OR REPLACE FUNCTION ops.claim_calendar_integration(worker_name TEXT, requested_operation TEXT)
RETURNS TABLE (
  job_id UUID,
  meeting_id UUID,
  operation TEXT,
  calendar_id TEXT,
  event_id TEXT,
  start_at TIMESTAMPTZ,
  end_at TIMESTAMPTZ,
  attendee_email TEXT,
  authorized BOOLEAN,
  summary TEXT,
  description TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
DECLARE
  selected_job_id UUID;
BEGIN
  IF requested_operation NOT IN ('create', 'update', 'delete') THEN
    RAISE EXCEPTION 'CALENDAR_OPERATION_INVALID';
  END IF;
  IF COALESCE(length(trim(worker_name)), 0) < 3 THEN
    RAISE EXCEPTION 'CALENDAR_WORKER_INVALID';
  END IF;
  IF NOT ops.integration_enabled('google_calendar_enabled') THEN
    RETURN;
  END IF;

  UPDATE ops.calendar_integration_jobs
  SET status = CASE WHEN attempts >= 3 THEN 'failed' ELSE 'retry' END,
      available_at = CASE WHEN attempts >= 3 THEN available_at ELSE NOW() END,
      claimed_at = NULL,
      last_error_code = CASE WHEN attempts >= 3 THEN 'LEASE_EXHAUSTED' ELSE 'LEASE_EXPIRED' END,
      updated_at = NOW()
  WHERE status = 'claimed'
    AND claimed_at < NOW() - INTERVAL '5 minutes';

  SELECT candidate.job_id
  INTO selected_job_id
  FROM ops.calendar_integration_jobs candidate
  JOIN core.meetings meeting ON meeting.meeting_id = candidate.meeting_id
  WHERE candidate.operation = requested_operation
    AND candidate.status IN ('queued', 'retry')
    AND candidate.available_at <= NOW()
    AND candidate.attempts < 3
    AND (requested_operation = 'create' OR NULLIF(meeting.external_event_id, '') IS NOT NULL)
  ORDER BY candidate.created_at
  FOR UPDATE OF candidate SKIP LOCKED
  LIMIT 1;

  IF selected_job_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE ops.calendar_integration_jobs claimed
  SET status = 'claimed',
      attempts = attempts + 1,
      claimed_at = NOW(),
      last_error_code = NULL,
      updated_at = NOW()
  WHERE claimed.job_id = selected_job_id;

  RETURN QUERY
  SELECT claimed.job_id,
         meeting.meeting_id,
         claimed.operation,
         flag.metadata ->> 'calendar_id',
         meeting.external_event_id,
         meeting.starts_at,
         meeting.ends_at,
         contact.email,
         TRUE,
         'Reuniao comercial DWLabs'::TEXT,
         'Reuniao comercial agendada pelo atendimento oficial DWLabs.'::TEXT
  FROM ops.calendar_integration_jobs claimed
  JOIN core.meetings meeting ON meeting.meeting_id = claimed.meeting_id
  JOIN core.contacts contact ON contact.contact_id = meeting.contact_id
  JOIN ops.runtime_flags flag ON flag.flag_name = 'google_calendar_enabled'
  WHERE claimed.job_id = selected_job_id
    AND NULLIF(flag.metadata ->> 'calendar_id', '') IS NOT NULL;

  IF NOT FOUND THEN
    UPDATE ops.calendar_integration_jobs
    SET status = 'failed',
        last_error_code = 'CALENDAR_ID_MISSING',
        claimed_at = NULL,
        updated_at = NOW()
    WHERE ops.calendar_integration_jobs.job_id = selected_job_id;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION ops.complete_calendar_integration(target_job_id UUID, result JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
DECLARE
  completed_meeting_id UUID;
  completed_operation TEXT;
  safe_event_id TEXT := NULLIF(result ->> 'external_event_id', '');
  safe_meet_url TEXT := NULLIF(result ->> 'meet_url', '');
BEGIN
  UPDATE ops.calendar_integration_jobs
  SET status = 'completed',
      external_event_id = safe_event_id,
      result_metadata = jsonb_strip_nulls(jsonb_build_object('status', left(COALESCE(result ->> 'status', 'completed'), 40))),
      claimed_at = NULL,
      last_error_code = NULL,
      updated_at = NOW()
  WHERE job_id = target_job_id
    AND status = 'claimed'
  RETURNING meeting_id, operation INTO completed_meeting_id, completed_operation;

  IF completed_meeting_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE core.meetings
  SET external_event_id = CASE WHEN completed_operation = 'delete' THEN NULL ELSE COALESCE(safe_event_id, external_event_id) END,
      external_meet_url = CASE WHEN completed_operation = 'delete' THEN NULL ELSE COALESCE(safe_meet_url, external_meet_url) END,
      external_sync_status = 'completed',
      external_sync_error_code = NULL,
      external_sync_updated_at = NOW(),
      updated_at = NOW()
  WHERE meeting_id = completed_meeting_id;

  RETURN TRUE;
END
$$;

CREATE OR REPLACE FUNCTION ops.fail_calendar_integration(target_job_id UUID, error_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
DECLARE
  affected_meeting_id UUID;
  next_status TEXT;
BEGIN
  UPDATE ops.calendar_integration_jobs
  SET status = CASE WHEN attempts >= 3 THEN 'failed' ELSE 'retry' END,
      available_at = CASE WHEN attempts >= 3 THEN available_at ELSE NOW() + make_interval(mins => power(2, attempts)::INTEGER) END,
      claimed_at = NULL,
      last_error_code = left(regexp_replace(upper(COALESCE(error_code, 'UNKNOWN_ERROR')), '[^A-Z0-9_:-]', '_', 'g'), 80),
      updated_at = NOW()
  WHERE job_id = target_job_id
    AND status = 'claimed'
  RETURNING meeting_id, status INTO affected_meeting_id, next_status;

  IF affected_meeting_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE core.meetings
  SET external_sync_status = next_status,
      external_sync_error_code = left(regexp_replace(upper(COALESCE(error_code, 'UNKNOWN_ERROR')), '[^A-Z0-9_:-]', '_', 'g'), 80),
      external_sync_updated_at = NOW(),
      updated_at = NOW()
  WHERE meeting_id = affected_meeting_id;

  RETURN TRUE;
END
$$;

CREATE OR REPLACE FUNCTION ops.claim_sheet_sync(worker_name TEXT)
RETURNS TABLE (
  sync_job_id UUID,
  document_id TEXT,
  sheet_name TEXT,
  authorized BOOLEAN,
  row_payload JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
DECLARE
  selected_job_id UUID;
BEGIN
  IF COALESCE(length(trim(worker_name)), 0) < 3 THEN
    RAISE EXCEPTION 'SHEETS_WORKER_INVALID';
  END IF;
  IF NOT ops.integration_enabled('google_sheets_enabled') THEN
    RETURN;
  END IF;

  UPDATE ops.sheet_sync_outbox
  SET status = CASE WHEN attempts >= 3 THEN 'failed' ELSE 'retry' END,
      available_at = CASE WHEN attempts >= 3 THEN available_at ELSE NOW() END,
      claimed_at = NULL,
      last_error_code = CASE WHEN attempts >= 3 THEN 'LEASE_EXHAUSTED' ELSE 'LEASE_EXPIRED' END,
      updated_at = NOW()
  WHERE status = 'claimed'
    AND claimed_at < NOW() - INTERVAL '5 minutes';

  SELECT job.sync_job_id
  INTO selected_job_id
  FROM ops.sheet_sync_outbox job
  WHERE job.status IN ('queued', 'retry')
    AND job.available_at <= NOW()
    AND job.attempts < 3
  ORDER BY job.created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  IF selected_job_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE ops.sheet_sync_outbox
  SET status = 'claimed',
      attempts = attempts + 1,
      claimed_at = NOW(),
      last_error_code = NULL,
      updated_at = NOW()
  WHERE ops.sheet_sync_outbox.sync_job_id = selected_job_id;

  RETURN QUERY
  SELECT selected_job_id,
         flag.metadata ->> 'document_id',
         COALESCE(NULLIF(flag.metadata ->> 'sheet_name', ''), 'Pipeline'),
         TRUE,
         jsonb_build_object(
           'lead_id', lead.lead_id,
           'company', COALESCE(company.name, ''),
           'stage', lead.stage,
           'score', lead.score,
           'temperature', lead.temperature_band,
           'segment', COALESCE(lead.segment, ''),
           'city', COALESCE(lead.city, ''),
           'services', array_to_string(COALESCE(lead.service_interests, ARRAY[]::TEXT[]), ', '),
           'owner', COALESCE(lead.owner_name, ''),
           'updated_at', lead.updated_at
         )
  FROM ops.sheet_sync_outbox job
  JOIN ops.runtime_flags flag ON flag.flag_name = 'google_sheets_enabled'
  CROSS JOIN LATERAL (
    SELECT candidate.*
    FROM core.leads candidate
    WHERE job.scope IN ('pipeline', 'full')
       OR (job.scope = 'followups' AND EXISTS (SELECT 1 FROM core.followups followup WHERE followup.lead_id = candidate.lead_id))
       OR (job.scope = 'meetings' AND EXISTS (SELECT 1 FROM core.meetings meeting WHERE meeting.lead_id = candidate.lead_id))
    ORDER BY candidate.updated_at DESC
  ) lead
  LEFT JOIN core.companies company ON company.company_id = lead.company_id
  WHERE job.sync_job_id = selected_job_id
    AND NULLIF(flag.metadata ->> 'document_id', '') IS NOT NULL;

  IF NOT FOUND THEN
    UPDATE ops.sheet_sync_outbox
    SET status = 'failed',
        last_error_code = 'SHEETS_CONFIG_OR_SCOPE_INVALID',
        claimed_at = NULL,
        updated_at = NOW()
    WHERE ops.sheet_sync_outbox.sync_job_id = selected_job_id;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION ops.complete_sheet_sync(target_job_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = pg_catalog, ops
AS $$
  WITH updated AS (
    UPDATE ops.sheet_sync_outbox
    SET status = 'completed', claimed_at = NULL, last_error_code = NULL, updated_at = NOW()
    WHERE sync_job_id = target_job_id AND status = 'claimed'
    RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM updated)
$$;

CREATE OR REPLACE FUNCTION ops.fail_sheet_sync(target_job_id UUID, error_code TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = pg_catalog, ops
AS $$
  WITH updated AS (
    UPDATE ops.sheet_sync_outbox
    SET status = CASE WHEN attempts >= 3 THEN 'failed' ELSE 'retry' END,
        available_at = CASE WHEN attempts >= 3 THEN available_at ELSE NOW() + make_interval(mins => power(2, attempts)::INTEGER) END,
        claimed_at = NULL,
        last_error_code = left(regexp_replace(upper(COALESCE(error_code, 'UNKNOWN_ERROR')), '[^A-Z0-9_:-]', '_', 'g'), 80),
        updated_at = NOW()
    WHERE sync_job_id = target_job_id AND status = 'claimed'
    RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM updated)
$$;

CREATE OR REPLACE FUNCTION ops.replace_google_calendar_busy_cache(payload JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core, ops
AS $$
DECLARE
  window_start TIMESTAMPTZ;
  window_end TIMESTAMPTZ;
  slots JSONB := COALESCE(payload -> 'busy_slots', '[]'::jsonb);
  inserted_count INTEGER := 0;
BEGIN
  BEGIN
    window_start := (payload ->> 'start_at')::TIMESTAMPTZ;
    window_end := (payload ->> 'end_at')::TIMESTAMPTZ;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CALENDAR_CACHE_WINDOW_INVALID';
  END;

  IF NULLIF(payload ->> 'calendar_id', '') IS NULL
     OR window_end <= window_start
     OR window_end - window_start > INTERVAL '45 days'
     OR jsonb_typeof(slots) <> 'array'
     OR jsonb_array_length(slots) > 2000 THEN
    RAISE EXCEPTION 'CALENDAR_CACHE_PAYLOAD_INVALID';
  END IF;

  DELETE FROM core.calendar_blocks
  WHERE source = 'google_calendar'
    AND starts_at < window_end
    AND ends_at > window_start;

  INSERT INTO core.calendar_blocks (starts_at, ends_at, reason, active, source, external_key, refreshed_at)
  SELECT parsed.starts_at,
         parsed.ends_at,
         'Google Calendar ocupado',
         TRUE,
         'google_calendar',
         encode(public.digest(parsed.starts_at::TEXT || ':' || parsed.ends_at::TEXT, 'sha256'), 'hex'),
         NOW()
  FROM (
    SELECT (slot ->> 'start')::TIMESTAMPTZ AS starts_at,
           (slot ->> 'end')::TIMESTAMPTZ AS ends_at
    FROM jsonb_array_elements(slots) slot
  ) parsed
  WHERE parsed.ends_at > parsed.starts_at
    AND parsed.starts_at < window_end
    AND parsed.ends_at > window_start
  ON CONFLICT (source, external_key) DO UPDATE
  SET starts_at = EXCLUDED.starts_at,
      ends_at = EXCLUDED.ends_at,
      active = TRUE,
      refreshed_at = NOW();

  GET DIAGNOSTICS inserted_count = ROW_COUNT;

  INSERT INTO ops.calendar_sync_state (provider, coverage_start, coverage_end, last_success_at, last_error_code, updated_at)
  VALUES ('google_calendar', window_start, window_end, NOW(), NULL, NOW())
  ON CONFLICT (provider) DO UPDATE
  SET coverage_start = EXCLUDED.coverage_start,
      coverage_end = EXCLUDED.coverage_end,
      last_success_at = EXCLUDED.last_success_at,
      last_error_code = NULL,
      updated_at = NOW();

  RETURN inserted_count;
END
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
  sync_state ops.calendar_sync_state%ROWTYPE;
BEGIN
  BEGIN
    requested_start := (payload ->> 'start_at')::TIMESTAMPTZ;
    requested_end := (payload ->> 'end_at')::TIMESTAMPTZ;
    duration_minutes := (payload ->> 'duration_minutes')::INTEGER;
  EXCEPTION WHEN OTHERS THEN
    RETURN ops.wrap_error('CALENDAR_WINDOW_INVALID','Janela de agenda invalida.',FALSE);
  END;
  IF requested_end <= requested_start
     OR requested_end - requested_start > INTERVAL '31 days'
     OR duration_minutes < 15
     OR duration_minutes > 180 THEN
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

  SELECT * INTO sync_state
  FROM ops.calendar_sync_state
  WHERE provider = 'google_calendar';

  IF sync_state.provider IS NULL
     OR sync_state.last_success_at < NOW() - INTERVAL '15 minutes'
     OR sync_state.coverage_start > requested_start
     OR sync_state.coverage_end < requested_end THEN
    RETURN ops.wrap_error('CALENDAR_CACHE_STALE','Disponibilidade real ainda nao foi sincronizada; tente novamente em alguns minutos.',TRUE);
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'starts_at',candidate_start,
    'ends_at',candidate_start + make_interval(mins => duration_minutes),
    'channel','google_calendar_cache'
  ) ORDER BY candidate_start),'[]'::jsonb)
  INTO slots
  FROM (
    SELECT candidate_start
    FROM generate_series(requested_start,requested_end - make_interval(mins => duration_minutes),make_interval(mins => duration_minutes)) candidate_start
    JOIN core.business_hours hours ON hours.weekday=EXTRACT(DOW FROM candidate_start AT TIME ZONE hours.timezone)::INTEGER
    WHERE hours.enabled
      AND (candidate_start AT TIME ZONE hours.timezone)::TIME >= hours.opens_at
      AND ((candidate_start + make_interval(mins => duration_minutes)) AT TIME ZONE hours.timezone)::TIME <= hours.closes_at
      AND NOT EXISTS (SELECT 1 FROM core.calendar_blocks block WHERE block.active AND tstzrange(candidate_start,candidate_start + make_interval(mins => duration_minutes),'[)') && tstzrange(block.starts_at,block.ends_at,'[)'))
      AND NOT EXISTS (SELECT 1 FROM core.meetings meeting WHERE meeting.status IN ('pending','scheduled','rescheduled') AND tstzrange(candidate_start,candidate_start + make_interval(mins => duration_minutes),'[)') && tstzrange(meeting.starts_at,meeting.ends_at,'[)'))
    ORDER BY candidate_start
    LIMIT 20
  ) available;

  RETURN ops.wrap_success(jsonb_build_object(
    'slots',slots,
    'integration_status','live_cache',
    'dispatch_required',FALSE,
    'cache_refreshed_at',sync_state.last_success_at
  ));
END
$$;

COMMIT;
