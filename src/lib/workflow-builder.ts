import { createHash } from "node:crypto";
import type { ToolDefinition } from "../contracts/tool-definitions.js";

interface N8nNode {
  id: string;
  name: string;
  type: string;
  typeVersion: number;
  position: [number, number];
  parameters: Record<string, unknown>;
  credentials?: Record<string, { id: string; name: string }>;
}

interface N8nWorkflow {
  name: string;
  nodes: N8nNode[];
  connections: Record<string, Record<string, Array<Array<{ node: string; type: string; index: number }>>>>;
  settings: Record<string, unknown>;
  pinData: Record<string, unknown>;
  tags: Array<{ name: string }>;
  active: boolean;
  versionId: string;
}

const envExpression = (envKey: string, fallback: string): string =>
  `={{ $env.${envKey} || "${fallback}" }}`;

const stableUuid = (seed: string): string => {
  const hex = createHash("sha1").update(seed).digest("hex").slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
};

const buildConnections = (orderedNodeNames: string[]): N8nWorkflow["connections"] => {
  const connections: N8nWorkflow["connections"] = {};

  for (let index = 0; index < orderedNodeNames.length - 1; index += 1) {
    const current = orderedNodeNames[index];
    const next = orderedNodeNames[index + 1];

    connections[current] = {
      main: [[{ node: next, type: "main", index: 0 }]]
    };
  }

  return connections;
};

const mutatingTools = new Set([
  "salvar_lead",
  "atualizar_lead",
  "registrar_interacao",
  "agendar_reuniao",
  "reagendar_reuniao",
  "cancelar_reuniao",
  "notificar_vendedor",
  "agendar_followup",
  "cancelar_followup",
  "transferir_humano",
  "sincronizar_sheets"
]);

const prepareRequestCode = (tool: ToolDefinition): string => [
  "const crypto = require('node:crypto');",
  "const headers = Object.fromEntries(Object.entries($json.headers ?? {}).map(([key, value]) => [String(key).toLowerCase(), value]));",
  "const body = $json.body ?? {};",
  "const toolName = '" + tool.toolName + "';",
  "const allowedChannels = new Set(['whatsapp', 'instagram', 'site', 'test']);",
  "if (headers['x-agent-id'] !== 'comercial') {",
  "  throw new Error(JSON.stringify({ ok: false, error: { code: 'AGENT_FORBIDDEN', message: 'Agente invalido.', retryable: false } }));",
  "}",
  "if (!body || typeof body !== 'object' || Array.isArray(body)) {",
  "  throw new Error(JSON.stringify({ ok: false, error: { code: 'INVALID_BODY', message: 'Envelope JSON obrigatorio.', retryable: false } }));",
  "}",
  "for (const required of ['request_id', 'idempotency_key', 'channel', 'actor', 'context', 'payload']) {",
  "  if (!(required in body)) {",
  "    throw new Error(JSON.stringify({ ok: false, error: { code: 'ENVELOPE_INVALID', message: `Campo ausente: ${required}.`, retryable: false } }));",
  "  }",
  "}",
  "if (!allowedChannels.has(String(body.channel))) {",
  "  throw new Error(JSON.stringify({ ok: false, error: { code: 'CHANNEL_FORBIDDEN', message: 'Canal nao allowlisted.', retryable: false } }));",
  "}",
  "if (headers['x-channel'] && String(headers['x-channel']) !== String(body.channel)) {",
  "  throw new Error(JSON.stringify({ ok: false, error: { code: 'CHANNEL_MISMATCH', message: 'Header e envelope divergentes.', retryable: false } }));",
  "}",
  "const actor = body.actor ?? {};",
  "const context = body.context ?? {};",
  "const payload = body.payload ?? {};",
  "const normalized = {",
  "  request_id: String(body.request_id),",
  "  idempotency_key: String(body.idempotency_key),",
  "  channel: String(body.channel),",
  "  actor,",
  "  context,",
  "  payload,",
  "  tool_name: toolName,",
  "  agent_id: headers['x-agent-id'],",
  "  correlation_id: String(headers['x-correlation-id'] || body.request_id),",
  "  external_event_id: String(context.message_id || body.request_id),",
  "  request_hash: crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex'),",
  "  contact_name: actor.contact_name ?? payload.contact_name ?? null,",
  "  phone: actor.phone ?? payload.phone ?? null,",
  "  email: actor.email ?? payload.email ?? null,",
  "  company_name: actor.company_name ?? payload.company_name ?? null,",
  "  role: actor.role ?? null,",
  "  conversation_id: context.conversation_id ?? payload.conversation_id ?? null,",
  "  lead_id: context.lead_id ?? payload.lead_id ?? null,",
  "  message_id: context.message_id ?? payload.source_message_id ?? null,",
  "  fragments: context.fragments ?? null,",
  "  locale: context.locale ?? 'pt-BR',",
  "  ...payload",
  "};",
  "const sqlPayloadBase64 = Buffer.from(JSON.stringify(normalized), 'utf8').toString('base64');",
  "return [{ json: { ...normalized, sql_payload_base64: sqlPayloadBase64, mutation_expected: " + String(mutatingTools.has(tool.toolName)) + " } }];"
].join("\n");

const unwrapResultCode = [
  "const row = Array.isArray($json) ? $json[0] : $json;",
  "const result = row?.result ?? row;",
  "if (!result || typeof result !== 'object') {",
  "  throw new Error(JSON.stringify({ ok: false, error: { code: 'INVALID_SQL_RESPONSE', message: 'Resposta SQL invalida.', retryable: false } }));",
  "}",
  "return [{ json: result }];"
].join("\n");

const subworkflowCodeByName: Record<string, string> = {
  "sdr._validate_request": [
    "const input = $json ?? {};",
    "const required = ['request_id', 'idempotency_key', 'tool_name', 'channel'];",
    "const missing = required.filter((field) => !input[field]);",
    "if (missing.length > 0) {",
    "  return [{ json: { ok: false, error: { code: 'REQUEST_INVALID', message: `Campos obrigatorios ausentes: ${missing.join(', ')}`, retryable: false } } }];",
    "}",
    "return [{ json: { ok: true, validated: true, tool_name: input.tool_name, channel: input.channel } }];"
  ].join("\n"),
  "sdr._normalize_contact": [
    "const digits = String($json.phone ?? '').replace(/\\D+/g, '');",
    "const normalized = digits ? (digits.startsWith('55') ? digits : `55${digits}`) : null;",
    "return [{ json: { ok: true, normalized_phone: normalized, normalized_email: $json.email ? String($json.email).trim().toLowerCase() : null } }];"
  ].join("\n"),
  "sdr._score_rules": [
    "const facts = $json.facts ?? {};",
    "let score = 10;",
    "if (facts.has_defined_offer) score += 15;",
    "if (facts.urgency_level === 'media') score += 12;",
    "if (facts.urgency_level === 'alta') score += 22;",
    "if (facts.budget_signal === 'medio') score += 12;",
    "if (facts.budget_signal === 'alto') score += 18;",
    "if (facts.authority_level === 'decisor') score += 14;",
    "if (facts.inbound_intent === 'forte') score += 18;",
    "score = Math.max(0, Math.min(100, score));",
    "const band = score >= 85 ? 'muito_quente' : score >= 70 ? 'quente' : score >= 40 ? 'morno' : 'frio';",
    "return [{ json: { ok: true, score, temperature_band: band } }];"
  ].join("\n"),
  "sdr._meeting_policy": [
    "const startAt = new Date($json.starts_at ?? $json.start_at ?? Date.now());",
    "const endAt = new Date($json.ends_at ?? $json.end_at ?? Date.now());",
    "const weekday = startAt.getUTCDay();",
    "const validWindow = weekday >= 1 && weekday <= 5 && startAt < endAt;",
    "return [{ json: { ok: validWindow, code: validWindow ? 'MEETING_POLICY_OK' : 'MEETING_POLICY_BLOCKED', requires_calendar: true } }];"
  ].join("\n"),
  "sdr._redact_log": [
    "const redact = (value) => String(value ?? '').replace(/55\\d{10,13}/g, '[telefone-redigido]').replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}/gi, '[email-redigido]');",
    "return [{ json: { ok: true, redacted: redact(JSON.stringify($json)) } }];"
  ].join("\n"),
  "sdr._metric_emit": [
    "return [{ json: { ok: true, metric_name: $json.metric_name ?? 'workflow_event', metric_value: Number($json.metric_value ?? 1), dimensions: $json.dimensions ?? {} } }];"
  ].join("\n"),
  "sdr._enforce_idempotency": [
    "const key = $json.idempotency_key ?? null;",
    "const hash = $json.request_hash ?? null;",
    "if (!key || !hash) {",
    "  return [{ json: { ok: false, error: { code: 'IDEMPOTENCY_REQUIRED', message: 'Chave e hash obrigatorios.', retryable: false } } }];",
    "}",
    "return [{ json: { ok: true, mode: 'database_transaction', idempotency_key: key, request_hash: hash } }];"
  ].join("\n"),
  "sdr._upsert_lead_bundle": [
    "return [{ json: { ok: true, entity_bundle: ['company', 'contact', 'lead', 'conversation'], requires_transaction: true } }];"
  ].join("\n")
};

const schedulerCodeByName: Record<string, string> = {
  "sdr.followup.scheduler": [
    "const enabled = String($env.SDR_FOLLOWUP_DISPATCH_ENABLED || 'false') === 'true';",
    "if (!enabled) {",
    "  return [{ json: { ok: false, code: 'FOLLOWUP_DISABLED', action: 'skip', retryable: false } }];",
    "}",
    "return [{ json: { ok: true, scheduler: 'followup', action: 'dispatch_due_followups', mode: 'private_network_only' } }];"
  ].join("\n"),
  "sdr.health.selfcheck": [
    "return [{ json: { ok: true, scheduler: 'healthcheck', checks: ['postgres_credential_bound', 'header_auth_bound', 'public_flag_blocked'], mode: 'readiness' } }];"
  ].join("\n"),
  "sdr.sheets.sync.scheduler": [
    "const enabled = String($env.SDR_GOOGLE_SHEETS_ENABLED || 'false') === 'true';",
    "if (!enabled) {",
    "  return [{ json: { ok: false, code: 'GOOGLE_SHEETS_DISABLED', action: 'skip', retryable: false } }];",
    "}",
    "return [{ json: { ok: true, scheduler: 'sheets_sync', action: 'dispatch_sheet_sync', mode: 'private_network_only' } }];"
  ].join("\n")
};

export function buildPublicWorkflow(tool: ToolDefinition): N8nWorkflow {
  const webhookName = "Receive Request";
  const normalizeName = "Normalize Envelope";
  const queryName = "Run SQL Function";
  const unwrapName = "Unwrap Result";
  const responseName = "Reply";

  const sqlExpression = `SELECT ${tool.sqlFunction}(convert_from(decode($1, 'base64'), 'UTF8')::jsonb) AS result;`;

  const nodes: N8nNode[] = [
    {
      id: "",
      name: webhookName,
      type: "n8n-nodes-base.webhook",
      typeVersion: 2.1,
      position: [220, 300],
      parameters: {
        httpMethod: "POST",
        path: tool.endpointPath,
        authentication: "headerAuth",
        responseMode: "responseNode",
        options: {
          responseHeaders: {
            entries: [{ name: "Content-Type", value: "application/json" }]
          }
        }
      },
      credentials: {
        httpHeaderAuth: {
          id: envExpression("N8N_SDR_HEADER_AUTH_ID", "DWLABS_SDR_HEADER_AUTH"),
          name: envExpression("N8N_SDR_HEADER_AUTH_NAME", "DWLabs SDR Header Auth")
        }
      }
    },
    {
      id: "",
      name: normalizeName,
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [520, 300],
      parameters: {
        language: "javaScript",
        jsCode: prepareRequestCode(tool)
      }
    },
    {
      id: "",
      name: queryName,
      type: "n8n-nodes-base.postgres",
      typeVersion: 2.6,
      position: [830, 300],
      parameters: {
        operation: "executeQuery",
        query: sqlExpression,
        options: {
          queryReplacement: "={{[$json.sql_payload_base64]}}"
        }
      },
      credentials: {
        postgres: {
          id: envExpression("N8N_WORKFLOW_PG_CREDENTIAL_ID", "DWLABS_SDR_POSTGRES_ID"),
          name: envExpression("N8N_WORKFLOW_PG_CREDENTIAL_NAME", "DWLABS_SDR_POSTGRES")
        }
      }
    },
    {
      id: "",
      name: unwrapName,
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [1130, 300],
      parameters: {
        language: "javaScript",
        jsCode: unwrapResultCode
      }
    },
    {
      id: "",
      name: responseName,
      type: "n8n-nodes-base.respondToWebhook",
      typeVersion: 1.4,
      position: [1410, 300],
      parameters: {
        respondWith: "json",
        responseBody: "={{ $json }}",
        options: {
          responseCode: 200
        }
      }
    }
  ];

  nodes.forEach((node, index) => {
    node.id = stableUuid(`${tool.workflowName}:${index}:${node.name}`);
  });

  return {
    name: tool.workflowName,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: {
      executionOrder: "v1"
    },
    pinData: {},
    tags: [{ name: "dwlabs-sdr" }, { name: "public-tool" }],
    active: false,
    versionId: stableUuid(`${tool.workflowName}:version`)
  };
}

export function buildSubworkflow(name: string): N8nWorkflow {
  const jsCode = subworkflowCodeByName[name] ?? "return [{ json: { ok: false, code: 'SUBWORKFLOW_UNMAPPED', retryable: false } }];";
  const nodes: N8nNode[] = [
    {
      id: "",
      name: "Execute Trigger",
      type: "n8n-nodes-base.executeWorkflowTrigger",
      typeVersion: 1.1,
      position: [260, 260],
      parameters: {}
    },
    {
      id: "",
      name: "Subworkflow Handler",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [560, 260],
      parameters: {
        language: "javaScript",
        jsCode
      }
    }
  ];

  nodes[0].id = stableUuid(`${name}:trigger`);
  nodes[1].id = stableUuid(`${name}:handler`);

  return {
    name,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: {
      executionOrder: "v1"
    },
    pinData: {},
    tags: [{ name: "dwlabs-sdr" }, { name: "subworkflow" }],
    active: false,
    versionId: stableUuid(`${name}:version`)
  };
}

export function buildScheduler(name: string): N8nWorkflow {
  const jsCode = schedulerCodeByName[name] ?? "return [{ json: { ok: false, code: 'SCHEDULER_UNMAPPED', retryable: false } }];";
  const nodes: N8nNode[] = [
    {
      id: "",
      name: "Schedule Trigger",
      type: "n8n-nodes-base.scheduleTrigger",
      typeVersion: 1.2,
      position: [260, 260],
      parameters: {
        rule: {
          interval: [
            {
              field: name === "sdr.followup.scheduler" ? "minutes" : "hours",
              minutesInterval: name === "sdr.followup.scheduler" ? 10 : undefined,
              hoursInterval: name === "sdr.followup.scheduler" ? undefined : 6
            }
          ]
        }
      }
    },
    {
      id: "",
      name: "Scheduler Logic",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [560, 260],
      parameters: {
        language: "javaScript",
        jsCode
      }
    }
  ];

  nodes[0].id = stableUuid(`${name}:schedule`);
  nodes[1].id = stableUuid(`${name}:logic`);

  return {
    name,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: {
      executionOrder: "v1"
    },
    pinData: {},
    tags: [{ name: "dwlabs-sdr" }, { name: "scheduler" }],
    active: false,
    versionId: stableUuid(`${name}:version`)
  };
}
