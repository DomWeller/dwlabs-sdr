ALTER TABLE ops.idempotency_inbox
  DROP CONSTRAINT IF EXISTS idempotency_inbox_source_system_external_event_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_idempotency_inbox_source_event_tool
  ON ops.idempotency_inbox(source_system, external_event_id, tool_name);

