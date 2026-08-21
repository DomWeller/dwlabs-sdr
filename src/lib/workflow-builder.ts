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
      id: "",
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
      id: "",
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
      id: "",
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
      id: "",
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

  nodes[0].id = stableUuid(`${tool.workflowName}:webhook`);
  nodes[1].id = stableUuid(`${tool.workflowName}:guard`);
  nodes[2].id = stableUuid(`${tool.workflowName}:postgres`);
  nodes[3].id = stableUuid(`${tool.workflowName}:response`);

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
