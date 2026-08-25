BEGIN;

DROP FUNCTION IF EXISTS ops.fail_sheet_sync(UUID, TEXT);
DROP FUNCTION IF EXISTS ops.complete_sheet_sync(UUID);
DROP FUNCTION IF EXISTS ops.claim_sheet_sync(TEXT);
DROP FUNCTION IF EXISTS ops.fail_calendar_integration(UUID, TEXT);
DROP FUNCTION IF EXISTS ops.complete_calendar_integration(UUID, JSONB);
DROP FUNCTION IF EXISTS ops.claim_calendar_integration(TEXT, TEXT);

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

ALTER TABLE core.meetings
  DROP COLUMN IF EXISTS external_sync_updated_at,
  DROP COLUMN IF EXISTS external_sync_error_code,
  DROP COLUMN IF EXISTS external_sync_status,
  DROP COLUMN IF EXISTS external_meet_url;

COMMIT;
