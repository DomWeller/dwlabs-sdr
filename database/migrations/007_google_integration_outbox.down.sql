BEGIN;

DROP FUNCTION IF EXISTS ops.fail_sheet_sync(UUID, TEXT);
DROP FUNCTION IF EXISTS ops.complete_sheet_sync(UUID);
DROP FUNCTION IF EXISTS ops.claim_sheet_sync(TEXT);
DROP FUNCTION IF EXISTS ops.fail_calendar_integration(UUID, TEXT);
DROP FUNCTION IF EXISTS ops.complete_calendar_integration(UUID, JSONB);
DROP FUNCTION IF EXISTS ops.claim_calendar_integration(TEXT, TEXT);
DROP FUNCTION IF EXISTS ops.replace_google_calendar_busy_cache(JSONB);

DROP TRIGGER IF EXISTS trg_enqueue_calendar_integration ON core.meetings;
DROP FUNCTION IF EXISTS ops.enqueue_calendar_integration();

DROP INDEX IF EXISTS ops.idx_sheet_sync_outbox_claim;
ALTER TABLE ops.sheet_sync_outbox
  DROP CONSTRAINT IF EXISTS sheet_sync_outbox_attempts_check,
  DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS last_error_code,
  DROP COLUMN IF EXISTS claimed_at,
  DROP COLUMN IF EXISTS available_at,
  DROP COLUMN IF EXISTS attempts;

DROP TABLE IF EXISTS ops.calendar_integration_jobs;
DROP TABLE IF EXISTS ops.calendar_sync_state;

DROP INDEX IF EXISTS core.uq_calendar_blocks_source_external;
ALTER TABLE core.calendar_blocks
  DROP COLUMN IF EXISTS refreshed_at,
  DROP COLUMN IF EXISTS external_key,
  DROP COLUMN IF EXISTS source;

ALTER TABLE core.meetings
  DROP COLUMN IF EXISTS external_sync_updated_at,
  DROP COLUMN IF EXISTS external_sync_error_code,
  DROP COLUMN IF EXISTS external_sync_status,
  DROP COLUMN IF EXISTS external_meet_url;

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

COMMIT;
