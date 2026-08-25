import { createHash } from "node:crypto";
import type { ToolDefinition } from "../contracts/tool-definitions.js";

interface N8nNode {
  id: string;
  webhookId?: string;
  name: string;
  type: string;
  typeVersion: number;
  position: [number, number];
  parameters: Record<string, unknown>;
  credentials?: Record<string, { id: string; name: string }>;
  retryOnFail?: boolean;
  maxTries?: number;
  waitBetweenTries?: number;
}

interface N8nWorkflow {
  id: string;
  name: string;
  nodes: N8nNode[];
  connections: Record<string, Record<string, Array<Array<{ node: string; type: string; index: number }>>>>;
  settings: Record<string, unknown>;
  pinData: Record<string, unknown>;
  tags: Array<{ name: string }>;
  active: boolean;
  versionId: string;
}

const HEADER_AUTH_CREDENTIAL = {
  id: "DWLABS_SDR_HEADER_AUTH",
  name: "DWLabs SDR Header Auth"
};

const POSTGRES_CREDENTIAL = {
  id: "DWLABS_SDR_POSTGRES_ID",
  name: "DWLABS_SDR_POSTGRES"
};

const GOOGLE_CALENDAR_CREDENTIAL = {
  id: "DWLABS_SDR_GOOGLE_CALENDAR_ID",
  name: "DWLABS_SDR_GOOGLE_CALENDAR"
};

const GOOGLE_SHEETS_CREDENTIAL = {
  id: "DWLABS_SDR_GOOGLE_SHEETS_ID",
  name: "DWLABS_SDR_GOOGLE_SHEETS"
};

export const googleAdapterNames = [
  "sdr.google-calendar.availability.adapter",
  "sdr.google-calendar.create.adapter",
  "sdr.google-calendar.update.adapter",
  "sdr.google-calendar.delete.adapter",
  "sdr.google-sheets.pipeline.adapter"
] as const;

const googleCalendarSchedulerOperations = {
  "sdr.google-calendar.create.scheduler": "create",
  "sdr.google-calendar.update.scheduler": "update",
  "sdr.google-calendar.delete.scheduler": "delete"
} as const;

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

const sandboxSafeSha256Code = [
  "const sha256 = (value) => {",
  "  const bytes = new TextEncoder().encode(value);",
  "  const words = [];",
  "  for (let index = 0; index < bytes.length; index += 1) words[index >> 2] = (words[index >> 2] || 0) | (bytes[index] << (24 - (index % 4) * 8));",
  "  words[bytes.length >> 2] = (words[bytes.length >> 2] || 0) | (0x80 << (24 - (bytes.length % 4) * 8));",
  "  const bitLength = bytes.length * 8;",
  "  const lengthIndex = (((bytes.length + 8) >> 6) << 4) + 15;",
  "  words[lengthIndex - 1] = Math.floor(bitLength / 0x100000000);",
  "  words[lengthIndex] = bitLength >>> 0;",
  "  const constants = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];",
  "  const hash = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];",
  "  const rotateRight = (number, bits) => (number >>> bits) | (number << (32 - bits));",
  "  for (let offset = 0; offset < words.length; offset += 16) {",
  "    const schedule = new Array(64);",
  "    for (let index = 0; index < 16; index += 1) schedule[index] = words[offset + index] || 0;",
  "    for (let index = 16; index < 64; index += 1) {",
  "      const s0 = rotateRight(schedule[index - 15], 7) ^ rotateRight(schedule[index - 15], 18) ^ (schedule[index - 15] >>> 3);",
  "      const s1 = rotateRight(schedule[index - 2], 17) ^ rotateRight(schedule[index - 2], 19) ^ (schedule[index - 2] >>> 10);",
  "      schedule[index] = (schedule[index - 16] + s0 + schedule[index - 7] + s1) | 0;",
  "    }",
  "    let [a, b, c, d, e, f, g, h] = hash;",
  "    for (let index = 0; index < 64; index += 1) {",
  "      const upperSigma1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);",
  "      const choice = (e & f) ^ (~e & g);",
  "      const temp1 = (h + upperSigma1 + choice + constants[index] + schedule[index]) | 0;",
  "      const upperSigma0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);",
  "      const majority = (a & b) ^ (a & c) ^ (b & c);",
  "      const temp2 = (upperSigma0 + majority) | 0;",
  "      h = g; g = f; f = e; e = (d + temp1) | 0; d = c; c = b; b = a; a = (temp1 + temp2) | 0;",
  "    }",
  "    hash[0] = (hash[0] + a) | 0; hash[1] = (hash[1] + b) | 0; hash[2] = (hash[2] + c) | 0; hash[3] = (hash[3] + d) | 0;",
  "    hash[4] = (hash[4] + e) | 0; hash[5] = (hash[5] + f) | 0; hash[6] = (hash[6] + g) | 0; hash[7] = (hash[7] + h) | 0;",
  "  }",
  "  return hash.map((part) => (part >>> 0).toString(16).padStart(8, '0')).join('');",
  "};"
];

const prepareRequestCode = (tool: ToolDefinition): string => [
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
  ...sandboxSafeSha256Code,
  "const requestHash = sha256(JSON.stringify(body));",
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
  "  request_hash: requestHash,",
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
    "const enabled = false;",
    "if (!enabled) {",
    "  return [{ json: { ok: false, code: 'FOLLOWUP_DISABLED', action: 'skip', retryable: false } }];",
    "}",
    "return [{ json: { ok: true, scheduler: 'followup', action: 'dispatch_due_followups', mode: 'private_network_only' } }];"
  ].join("\n"),
  "sdr.health.selfcheck": [
    "return [{ json: { ok: true, scheduler: 'healthcheck', checks: ['postgres_credential_bound', 'header_auth_bound', 'public_flag_blocked'], mode: 'readiness' } }];"
  ].join("\n"),
  "sdr.sheets.sync.scheduler": [
    "const enabled = false;",
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

  const sqlExpression = `WITH input AS MATERIALIZED (
  SELECT convert_from(decode($1, 'base64'), 'UTF8')::jsonb AS payload, clock_timestamp() AS started_at
), called AS MATERIALIZED (
  SELECT ${tool.sqlFunction}(input.payload) AS result FROM input
), logged AS (
  INSERT INTO ops.metrics_events(metric_name, metric_value, dimensions)
  SELECT 'tool_call',
         EXTRACT(EPOCH FROM (clock_timestamp() - input.started_at)) * 1000,
         jsonb_build_object(
           'tool', '${tool.toolName}',
           'channel', COALESCE(input.payload ->> 'channel', 'unknown'),
           'ok', COALESCE((called.result ->> 'ok')::BOOLEAN, FALSE),
           'error_code', called.result #>> '{error,code}'
         )
  FROM input, called
  RETURNING metric_event_id
)
SELECT called.result FROM called CROSS JOIN (SELECT count(*) FROM logged) metric_guard;`;

  const nodes: N8nNode[] = [
    {
      id: "",
      webhookId: stableUuid(`${tool.workflowName}:webhook`),
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
          ...HEADER_AUTH_CREDENTIAL
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
          ...POSTGRES_CREDENTIAL
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
    id: stableUuid(`${tool.workflowName}:workflow`),
    name: tool.workflowName,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: {
      executionOrder: "v1"
    },
    pinData: {},
    tags: [],
    active: false,
    versionId: stableUuid(`${tool.workflowName}:version:2`)
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
    id: stableUuid(`${name}:workflow`),
    name,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: {
      executionOrder: "v1"
    },
    pinData: {},
    tags: [],
    active: false,
    versionId: stableUuid(`${name}:version`)
  };
}

export function buildScheduler(name: string): N8nWorkflow {
  if (name in googleCalendarSchedulerOperations) {
    return buildGoogleCalendarScheduler(name as keyof typeof googleCalendarSchedulerOperations);
  }
  if (name === "sdr.sheets.sync.scheduler") {
    return buildGoogleSheetsScheduler();
  }

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
    id: stableUuid(`${name}:workflow`),
    name,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: {
      executionOrder: "v1"
    },
    pinData: {},
    tags: [],
    active: false,
    versionId: stableUuid(`${name}:version`)
  };
}

function buildGoogleCalendarScheduler(name: keyof typeof googleCalendarSchedulerOperations): N8nWorkflow {
  const operation = googleCalendarSchedulerOperations[name];
  const adapterName = `sdr.google-calendar.${operation}.adapter`;
  const nodes: N8nNode[] = [
    {
      id: stableUuid(`${name}:schedule`),
      name: "Schedule Trigger",
      type: "n8n-nodes-base.scheduleTrigger",
      typeVersion: 1.2,
      position: [180, 300],
      parameters: { rule: { interval: [{ field: "minutes", minutesInterval: 2 }] } }
    },
    {
      id: stableUuid(`${name}:claim`),
      name: "Claim Calendar Job",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2.6,
      position: [450, 300],
      parameters: {
        operation: "executeQuery",
        query: `SELECT * FROM ops.claim_calendar_integration('n8n-calendar-${operation}', '${operation}');`,
        options: {}
      },
      credentials: { postgres: { ...POSTGRES_CREDENTIAL } }
    },
    {
      id: stableUuid(`${name}:execute`),
      name: "Execute Google Adapter",
      type: "n8n-nodes-base.executeWorkflow",
      typeVersion: 1.1,
      position: [730, 300],
      parameters: {
        source: "database",
        workflowId: { mode: "id", value: stableUuid(`${adapterName}:workflow`) },
        mode: "once",
        options: { waitForSubWorkflow: true }
      }
    },
    {
      id: stableUuid(`${name}:prepare-completion`),
      name: "Prepare Completion",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [1010, 300],
      parameters: {
        mode: "runOnceForEachItem",
        language: "javaScript",
        jsCode: "if (!$json.job_id) throw new Error('CALENDAR_JOB_ID_MISSING'); return [{ json: { job_id: String($json.job_id), result_base64: Buffer.from(JSON.stringify($json), 'utf8').toString('base64') } }];"
      }
    },
    {
      id: stableUuid(`${name}:complete`),
      name: "Complete Calendar Job",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2.6,
      position: [1290, 300],
      parameters: {
        operation: "executeQuery",
        query: "SELECT ops.complete_calendar_integration($1::uuid, convert_from(decode($2, 'base64'), 'UTF8')::jsonb) AS completed;",
        options: { queryReplacement: "={{[$json.job_id, $json.result_base64]}}" }
      },
      credentials: { postgres: { ...POSTGRES_CREDENTIAL } }
    }
  ];

  return {
    id: stableUuid(`${name}:workflow`),
    name,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: { executionOrder: "v1", timezone: "America/Sao_Paulo" },
    pinData: {},
    tags: [],
    active: false,
    versionId: stableUuid(`${name}:version`)
  };
}

function buildGoogleSheetsScheduler(): N8nWorkflow {
  const name = "sdr.sheets.sync.scheduler";
  const adapterName = "sdr.google-sheets.pipeline.adapter";
  const nodes: N8nNode[] = [
    {
      id: stableUuid(`${name}:schedule`),
      name: "Schedule Trigger",
      type: "n8n-nodes-base.scheduleTrigger",
      typeVersion: 1.2,
      position: [150, 300],
      parameters: { rule: { interval: [{ field: "minutes", minutesInterval: 10 }] } }
    },
    {
      id: stableUuid(`${name}:claim`),
      name: "Claim Sheets Job",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2.6,
      position: [410, 300],
      parameters: {
        operation: "executeQuery",
        query: "SELECT * FROM ops.claim_sheet_sync('n8n-sheets-pipeline');",
        options: {}
      },
      credentials: { postgres: { ...POSTGRES_CREDENTIAL } }
    },
    {
      id: stableUuid(`${name}:prepare`),
      name: "Prepare Sheets Adapter Input",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [680, 300],
      parameters: {
        mode: "runOnceForEachItem",
        language: "javaScript",
        jsCode: "const row = typeof $json.row_payload === 'string' ? JSON.parse($json.row_payload) : $json.row_payload; return [{ json: { sync_job_id: String($json.sync_job_id), document_id: String($json.document_id), sheet_name: String($json.sheet_name), authorized: $json.authorized === true, row } }];"
      }
    },
    {
      id: stableUuid(`${name}:execute`),
      name: "Execute Google Sheets Adapter",
      type: "n8n-nodes-base.executeWorkflow",
      typeVersion: 1.1,
      position: [960, 300],
      parameters: {
        source: "database",
        workflowId: { mode: "id", value: stableUuid(`${adapterName}:workflow`) },
        mode: "once",
        options: { waitForSubWorkflow: true }
      }
    },
    {
      id: stableUuid(`${name}:complete`),
      name: "Complete Sheets Job",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2.6,
      position: [1240, 300],
      parameters: {
        operation: "executeQuery",
        query: "SELECT ops.complete_sheet_sync($1::uuid) AS completed;",
        options: { queryReplacement: "={{[$json.sync_job_id]}}" }
      },
      credentials: { postgres: { ...POSTGRES_CREDENTIAL } }
    }
  ];

  return {
    id: stableUuid(`${name}:workflow`),
    name,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: { executionOrder: "v1", timezone: "America/Sao_Paulo" },
    pinData: {},
    tags: [],
    active: false,
    versionId: stableUuid(`${name}:version`)
  };
}

export function buildInternalMetricsWorkflow(): N8nWorkflow {
  const name = "sdr.agent.metrics";
  const nodes: N8nNode[] = [
    {
      id: stableUuid(`${name}:webhook`),
      webhookId: stableUuid(`${name}:webhook-id`),
      name: "Receive Metric",
      type: "n8n-nodes-base.webhook",
      typeVersion: 2.1,
      position: [220, 300],
      parameters: {
        httpMethod: "POST",
        path: "dwlabs-sdr/agent-metrics",
        authentication: "headerAuth",
        responseMode: "responseNode",
        options: { responseHeaders: { entries: [{ name: "Content-Type", value: "application/json" }] } }
      },
      credentials: { httpHeaderAuth: { ...HEADER_AUTH_CREDENTIAL } }
    },
    {
      id: stableUuid(`${name}:normalize`),
      name: "Validate Metric",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [520, 300],
      parameters: {
        language: "javaScript",
        jsCode: [
          "const headers = Object.fromEntries(Object.entries($json.headers ?? {}).map(([key, value]) => [String(key).toLowerCase(), value]));",
          "const body = $json.body ?? {};",
          "const payload = body.payload ?? {};",
          "const allowedChannels = new Set(['whatsapp', 'instagram', 'site', 'test', 'internal']);",
          "if (headers['x-agent-id'] !== 'comercial') throw new Error('AGENT_FORBIDDEN');",
          "if (!allowedChannels.has(String(body.channel))) throw new Error('CHANNEL_FORBIDDEN');",
          "const allowedMetrics = new Set(['model_call', 'agent_turn']);",
          "if (!allowedMetrics.has(String(payload.metric_name))) throw new Error('METRIC_FORBIDDEN');",
          "const durationMs = Number(payload.duration_ms);",
          "if (!Number.isFinite(durationMs) || durationMs < 0 || durationMs > 900000) throw new Error('METRIC_VALUE_INVALID');",
          "const safe = { metric_name: String(payload.metric_name), duration_ms: durationMs, channel: String(body.channel), provider: String(payload.provider ?? 'unknown').slice(0,80), model: String(payload.model ?? 'unknown').slice(0,120), outcome: payload.outcome === 'completed' ? 'completed' : 'error', error_category: payload.error_category ? String(payload.error_category).slice(0,80) : null, time_to_first_byte_ms: Number.isFinite(Number(payload.time_to_first_byte_ms)) ? Number(payload.time_to_first_byte_ms) : null };",
          "return [{ json: { metric_payload_base64: Buffer.from(JSON.stringify(safe), 'utf8').toString('base64') } }];"
        ].join("\n")
      }
    },
    {
      id: stableUuid(`${name}:insert`),
      name: "Store Metric",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2.6,
      position: [830, 300],
      parameters: {
        operation: "executeQuery",
        query: `WITH input AS (
  SELECT convert_from(decode($1, 'base64'), 'UTF8')::jsonb AS payload
), inserted AS (
  INSERT INTO ops.metrics_events(metric_name, metric_value, dimensions)
  SELECT payload ->> 'metric_name',
         (payload ->> 'duration_ms')::NUMERIC,
         jsonb_build_object(
           'channel', payload ->> 'channel',
           'provider', payload ->> 'provider',
           'model', payload ->> 'model',
           'outcome', payload ->> 'outcome',
           'error_category', payload ->> 'error_category',
           'time_to_first_byte_ms', payload ->> 'time_to_first_byte_ms'
         )
  FROM input
  RETURNING metric_event_id
)
SELECT jsonb_build_object('ok',TRUE,'stored',TRUE) AS result FROM inserted;`,
        options: { queryReplacement: "={{[$json.metric_payload_base64]}}" }
      },
      credentials: { postgres: { ...POSTGRES_CREDENTIAL } }
    },
    {
      id: stableUuid(`${name}:reply`),
      name: "Reply",
      type: "n8n-nodes-base.respondToWebhook",
      typeVersion: 1.4,
      position: [1130, 300],
      parameters: { respondWith: "json", responseBody: "={{ $json.result ?? $json }}", options: { responseCode: 200 } }
    }
  ];

  return {
    id: stableUuid(`${name}:workflow`),
    name,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: { executionOrder: "v1" },
    pinData: {},
    tags: [],
    active: false,
    versionId: stableUuid(`${name}:version`)
  };
}

export function buildGoogleAdapter(name: (typeof googleAdapterNames)[number]): N8nWorkflow {
  const triggerName = "Execute Adapter";
  const validateName = "Validate Adapter Input";
  const googleName = "Google Operation";
  const sanitizeName = "Sanitize Adapter Result";
  const commonRequired = name.includes("google-calendar") ? ["calendar_id"] : ["document_id", "sheet_name", "row"];
  const operationRequired = name.endsWith("availability.adapter")
    ? ["start_at", "end_at"]
    : name.endsWith("create.adapter")
      ? ["start_at", "end_at", "authorized"]
      : name.endsWith("update.adapter")
        ? ["event_id", "start_at", "end_at", "authorized"]
        : name.endsWith("delete.adapter")
          ? ["event_id", "authorized"]
          : ["authorized"];
  const mutating = !name.endsWith("availability.adapter");
  const validateCode = [
    "const input = $json ?? {};",
    `const required = ${JSON.stringify([...commonRequired, ...operationRequired])};`,
    "const missing = required.filter((field) => input[field] === undefined || input[field] === null || input[field] === '');",
    "if (missing.length) throw new Error(`ADAPTER_INPUT_INVALID:${missing.join(',')}`);",
    mutating ? "if (input.authorized !== true) throw new Error('ADAPTER_AUTH_REQUIRED');" : "",
    "if (input.start_at && input.end_at && new Date(input.end_at) <= new Date(input.start_at)) throw new Error('ADAPTER_WINDOW_INVALID');",
    name.includes("google-sheets")
      ? "if (!input.row || typeof input.row !== 'object' || Array.isArray(input.row) || !input.row.lead_id) throw new Error('SHEETS_ROW_INVALID');"
      : "",
    name.includes("google-sheets") ? "return [{ json: { document_id: input.document_id, sheet_name: input.sheet_name, ...input.row } }];" : "return [{ json: input }];"
  ].filter(Boolean).join("\n");

  let parameters: Record<string, unknown>;
  let credentials: Record<string, { id: string; name: string }>;
  let type: string;
  let typeVersion: number;
  let sanitizeCode: string;

  if (name === "sdr.google-calendar.availability.adapter") {
    type = "n8n-nodes-base.googleCalendar";
    typeVersion = 1.3;
    credentials = { googleCalendarOAuth2Api: { ...GOOGLE_CALENDAR_CREDENTIAL } };
    parameters = {
      resource: "calendar",
      operation: "availability",
      calendar: { mode: "id", value: "={{ $json.calendar_id }}" },
      timeMin: "={{ $json.start_at }}",
      timeMax: "={{ $json.end_at }}",
      options: {
        outputFormat: "bookedSlots",
        timezone: { mode: "id", value: "America/Sao_Paulo" }
      }
    };
    sanitizeCode = "const busy = Array.isArray($json.busy) ? $json.busy : (Array.isArray($json) ? $json : []); return [{ json: { ok: true, timezone: 'America/Sao_Paulo', busy_slots: busy.slice(0, 200) } }];";
  } else if (name === "sdr.google-calendar.create.adapter") {
    type = "n8n-nodes-base.googleCalendar";
    typeVersion = 1.3;
    credentials = { googleCalendarOAuth2Api: { ...GOOGLE_CALENDAR_CREDENTIAL } };
    parameters = {
      resource: "event",
      operation: "create",
      calendar: { mode: "id", value: "={{ $json.calendar_id }}" },
      start: "={{ $json.start_at }}",
      end: "={{ $json.end_at }}",
      useDefaultReminders: true,
      additionalFields: {
        attendees: "={{ $json.attendee_email ? [$json.attendee_email] : [] }}",
        conferenceDataUi: { conferenceDataValues: { conferenceSolution: "hangoutsMeet" } },
        description: "={{ $json.description || 'Reuniao comercial agendada pelo atendimento oficial DWLabs.' }}",
        guestsCanInviteOthers: false,
        guestsCanModify: false,
        sendUpdates: "all",
        showMeAs: "opaque",
        summary: "={{ $json.summary || 'Reuniao comercial DWLabs' }}",
        visibility: "private"
      }
    };
    sanitizeCode = "const request = $('Validate Adapter Input').item.json; return [{ json: { ok: true, job_id: request.job_id || null, meeting_id: request.meeting_id || null, external_event_id: String($json.id || ''), meet_url: $json.hangoutLink || $json.conferenceData?.entryPoints?.find((entry) => entry.entryPointType === 'video')?.uri || null, status: String($json.status || 'confirmed') } }];";
  } else if (name === "sdr.google-calendar.update.adapter") {
    type = "n8n-nodes-base.googleCalendar";
    typeVersion = 1.3;
    credentials = { googleCalendarOAuth2Api: { ...GOOGLE_CALENDAR_CREDENTIAL } };
    parameters = {
      resource: "event",
      operation: "update",
      calendar: { mode: "id", value: "={{ $json.calendar_id }}" },
      eventId: "={{ $json.event_id }}",
      modifyTarget: "event",
      useDefaultReminders: true,
      updateFields: {
        start: "={{ $json.start_at }}",
        end: "={{ $json.end_at }}",
        description: "={{ $json.description || 'Reuniao comercial DWLabs reagendada.' }}",
        sendUpdates: "all",
        summary: "={{ $json.summary || 'Reuniao comercial DWLabs' }}"
      }
    };
    sanitizeCode = "const request = $('Validate Adapter Input').item.json; return [{ json: { ok: true, job_id: request.job_id || null, meeting_id: request.meeting_id || null, external_event_id: String($json.id || ''), meet_url: $json.hangoutLink || null, status: String($json.status || 'confirmed') } }];";
  } else if (name === "sdr.google-calendar.delete.adapter") {
    type = "n8n-nodes-base.googleCalendar";
    typeVersion = 1.3;
    credentials = { googleCalendarOAuth2Api: { ...GOOGLE_CALENDAR_CREDENTIAL } };
    parameters = {
      resource: "event",
      operation: "delete",
      calendar: { mode: "id", value: "={{ $json.calendar_id }}" },
      eventId: "={{ $json.event_id }}",
      options: { sendUpdates: "all" }
    };
    sanitizeCode = "const request = $('Validate Adapter Input').item.json; return [{ json: { ok: true, job_id: request.job_id || null, meeting_id: request.meeting_id || null, external_event_id: request.event_id || null, deleted: true, status: 'deleted' } }];";
  } else {
    type = "n8n-nodes-base.googleSheets";
    typeVersion = 4.7;
    credentials = { googleSheetsOAuth2Api: { ...GOOGLE_SHEETS_CREDENTIAL } };
    parameters = {
      authentication: "oAuth2",
      resource: "sheet",
      operation: "appendOrUpdate",
      documentId: { mode: "id", value: "={{ $json.document_id }}" },
      sheetName: { mode: "id", value: "={{ $json.sheet_name }}" },
      columns: {
        mappingMode: "defineBelow",
        value: {
          lead_id: "={{ $json.lead_id }}",
          company: "={{ $json.company || '' }}",
          stage: "={{ $json.stage || '' }}",
          score: "={{ $json.score ?? 0 }}",
          temperature: "={{ $json.temperature || '' }}",
          segment: "={{ $json.segment || '' }}",
          city: "={{ $json.city || '' }}",
          services: "={{ $json.services || '' }}",
          owner: "={{ $json.owner || '' }}",
          updated_at: "={{ $json.updated_at || '' }}"
        },
        matchingColumns: ["lead_id"],
        schema: [
          { id: "lead_id", displayName: "lead_id", required: true, defaultMatch: true, display: true, type: "string", canBeUsedToMatch: true },
          ...["company", "stage", "temperature", "segment", "city", "services", "owner", "updated_at"].map((id) => ({ id, displayName: id, required: false, defaultMatch: false, display: true, type: "string", canBeUsedToMatch: false })),
          { id: "score", displayName: "score", required: false, defaultMatch: false, display: true, type: "number", canBeUsedToMatch: false }
        ],
        attemptToConvertTypes: false,
        convertFieldsToString: true
      },
      options: { handlingExtraData: "ignoreIt" }
    };
    sanitizeCode = "const request = $('Validate Adapter Input').item.json; return [{ json: { ok: true, sync_job_id: request.sync_job_id || null, row_synced: true, lead_id: String(request.lead_id || $json.lead_id || '') } }];";
  }

  const nodes: N8nNode[] = [
    {
      id: stableUuid(`${name}:trigger`),
      name: triggerName,
      type: "n8n-nodes-base.executeWorkflowTrigger",
      typeVersion: 1.1,
      position: [220, 300],
      parameters: { workflowInputs: { values: [] } }
    },
    {
      id: stableUuid(`${name}:validate`),
      name: validateName,
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [500, 300],
      parameters: { mode: "runOnceForEachItem", language: "javaScript", jsCode: validateCode }
    },
    {
      id: stableUuid(`${name}:google`),
      name: googleName,
      type,
      typeVersion,
      position: [800, 300],
      parameters,
      credentials,
      retryOnFail: true,
      maxTries: 3,
      waitBetweenTries: 2000
    },
    {
      id: stableUuid(`${name}:sanitize`),
      name: sanitizeName,
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [1100, 300],
      parameters: { mode: "runOnceForEachItem", language: "javaScript", jsCode: sanitizeCode }
    }
  ];

  return {
    id: stableUuid(`${name}:workflow`),
    name,
    nodes,
    connections: buildConnections(nodes.map((node) => node.name)),
    settings: { executionOrder: "v1", timezone: "America/Sao_Paulo" },
    pinData: {},
    tags: [],
    active: false,
    versionId: stableUuid(`${name}:version`)
  };
}
