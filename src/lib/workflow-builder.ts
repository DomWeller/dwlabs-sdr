import { randomUUID } from "node:crypto";
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

export function buildPublicWorkflow(tool: ToolDefinition): N8nWorkflow {
  const webhookName = "Receive Request";
  const guardName = "Validate Headers";
  const queryName = "Run SQL Function";
  const responseName = "Reply";

  const sqlExpression = [
    "={{ `SELECT ",
    tool.sqlFunction,
    "('",
    "${JSON.stringify($json.body).replace(/'/g, \"''\")}",
    "'::jsonb) AS result;` }}"
  ].join("");

  const nodes: N8nNode[] = [
    {
      id: randomUUID(),
      name: webhookName,
      type: "n8n-nodes-base.webhook",
      typeVersion: 2,
      position: [260, 300],
      parameters: {
        httpMethod: "POST",
        path: tool.endpointPath,
        responseMode: "responseNode",
        options: {
          responseHeaders: {
            entries: [
              { name: "Content-Type", value: "application/json" }
            ]
          }
        }
      }
    },
    {
      id: randomUUID(),
      name: guardName,
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [560, 300],
      parameters: {
        language: "javaScript",
        jsCode: [
          "const headers = $json.headers ?? {};",
          "const body = $json.body ?? {};",
          "if (!headers.authorization) {",
          "  throw new Error(JSON.stringify({ ok: false, error: { code: 'UNAUTHORIZED', message: 'Bearer ausente', retryable: false } }));",
          "}",
          "if (!headers['x-idempotency-key'] && !body.idempotency_key) {",
          "  throw new Error(JSON.stringify({ ok: false, error: { code: 'IDEMPOTENCY_REQUIRED', message: 'Chave de idempotencia obrigatoria', retryable: false } }));",
          "}",
          "return [{ json: { ...$json, tool_name: '" + tool.toolName + "' } }];"
        ].join("\n")
      }
    },
    {
      id: randomUUID(),
      name: queryName,
      type: "n8n-nodes-base.postgres",
      typeVersion: 2.6,
      position: [860, 300],
      parameters: {
        operation: "executeQuery",
        query: sqlExpression,
        options: {}
      },
      credentials: {
        postgres: {
          id: envExpression("N8N_WORKFLOW_PG_CREDENTIAL_ID", "DWLABS_SDR_POSTGRES_ID"),
          name: envExpression("N8N_WORKFLOW_PG_CREDENTIAL_NAME", "DWLABS_SDR_POSTGRES")
        }
      }
    },
    {
      id: randomUUID(),
      name: responseName,
      type: "n8n-nodes-base.respondToWebhook",
      typeVersion: 1.4,
      position: [1160, 300],
      parameters: {
        respondWith: "json",
        responseBody: "={{ $json.result || $json }}",
        options: {
          responseCode: 200
        }
      }
    }
  ];

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
    versionId: randomUUID()
  };
}

export function buildSubworkflow(name: string): N8nWorkflow {
  const nodes: N8nNode[] = [
    {
      id: randomUUID(),
      name: "Execute Trigger",
      type: "n8n-nodes-base.executeWorkflowTrigger",
      typeVersion: 1.1,
      position: [260, 260],
      parameters: {}
    },
    {
      id: randomUUID(),
      name: "Subworkflow Handler",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [560, 260],
      parameters: {
        language: "javaScript",
        jsCode: [
          "return [{",
          "  json: {",
          "    ok: true,",
          "    subworkflow: '" + name + "',",
          "    note: 'Executar regras compartilhadas aqui apos importar no n8n.',",
          "  },",
          "}];"
        ].join("\n")
      }
    }
  ];

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
    versionId: randomUUID()
  };
}

export function buildScheduler(name: string): N8nWorkflow {
  const nodes: N8nNode[] = [
    {
      id: randomUUID(),
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
      id: randomUUID(),
      name: "Scheduler Logic",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [560, 260],
      parameters: {
        language: "javaScript",
        jsCode: [
          "return [{",
          "  json: {",
          "    scheduler: '" + name + "',",
          "    status: 'ready',",
          "    mode: 'safe',",
          "  },",
          "}];"
        ].join("\n")
      }
    }
  ];

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
    versionId: randomUUID()
  };
}
