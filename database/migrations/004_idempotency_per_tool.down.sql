DROP INDEX IF EXISTS ops.uq_idempotency_inbox_source_event_tool;

ALTER TABLE ops.idempotency_inbox
  ADD CONSTRAINT idempotency_inbox_source_system_external_event_id_key
  UNIQUE (source_system, external_event_id);

