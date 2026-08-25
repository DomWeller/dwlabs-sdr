import { createHash, randomUUID } from "node:crypto";
import { Type } from "typebox";
import { defineToolPlugin } from "openclaw/plugin-sdk/tool-plugin";

const channelSchema = Type.Union([
  Type.Literal("whatsapp"),
  Type.Literal("instagram"),
  Type.Literal("site"),
  Type.Literal("test")
]);

const actorSchema = Type.Object(
  {
    contact_name: Type.Optional(Type.String()),
    phone: Type.Optional(Type.String()),
    email: Type.Optional(Type.String()),
    company_name: Type.Optional(Type.String()),
    role: Type.Optional(Type.String())
  },
  { additionalProperties: false }
);

const contextSchema = Type.Object(
  {
    conversation_id: Type.Optional(Type.String()),
    lead_id: Type.Optional(Type.String()),
    message_id: Type.Optional(Type.String()),
    fragments: Type.Optional(Type.Array(Type.String())),
    locale: Type.Optional(Type.String())
  },
  { additionalProperties: false }
);

const secretRefSchema = Type.Union([
  Type.Object(
    {
      source: Type.Literal("env"),
      provider: Type.String({ pattern: "^[a-z][a-z0-9_-]{0,63}$" }),
      id: Type.String({ pattern: "^[A-Z][A-Z0-9_]{0,127}$" })
    },
    { additionalProperties: false }
  ),
  Type.Object(
    {
      source: Type.Literal("file"),
      provider: Type.String({ pattern: "^[a-z][a-z0-9_-]{0,63}$" }),
      id: Type.String({ minLength: 1 })
    },
    { additionalProperties: false }
  ),
  Type.Object(
    {
      source: Type.Literal("exec"),
      provider: Type.String({ pattern: "^[a-z][a-z0-9_-]{0,63}$" }),
      id: Type.String({ minLength: 1 })
    },
    { additionalProperties: false }
  )
]);

const baseToolInput = (payload: ReturnType<typeof Type.Object>) =>
  Type.Object(
    {
      request_id: Type.String(),
      idempotency_key: Type.String(),
      channel: channelSchema,
      actor: actorSchema,
      context: contextSchema,
      payload
    },
    { additionalProperties: false }
  );

type PluginConfig = {
  baseUrl?: string;
  bearerToken?: string;
  timeoutMs?: number;
  allowlist?: string[];
};

type ToolSpec = {
  name: string;
  path: string;
  description: string;
  parameters: ReturnType<typeof baseToolInput>;
};

const rateWindows = new Map<string, { startedAt: number; count: number }>();
const RATE_WINDOW_MS = 60_000;
const RATE_LIMIT = 12;
const activeHandoffCache = new Map<string, number>();
const ACTIVE_HANDOFF_FAILURE_GRACE_MS = 15 * 60_000;

function enforceRateLimit(relativePath: string, params: Record<string, unknown>): void {
  const actor = (params.actor ?? {}) as Record<string, unknown>;
  const context = (params.context ?? {}) as Record<string, unknown>;
  const subject = String(actor.phone ?? actor.email ?? context.conversation_id ?? "anonymous");
  const key = createHash("sha256").update(`${relativePath}:${subject}`).digest("hex");
  const now = Date.now();
  const current = rateWindows.get(key);

  if (!current || now - current.startedAt >= RATE_WINDOW_MS) {
    rateWindows.set(key, { startedAt: now, count: 1 });
  } else {
    current.count += 1;
    if (current.count > RATE_LIMIT) {
      const retryAfter = Math.max(1, Math.ceil((current.startedAt + RATE_WINDOW_MS - now) / 1000));
      throw new Error(`RATE_LIMITED:${retryAfter}`);
    }
  }

  if (rateWindows.size > 10_000) {
    for (const [entryKey, entry] of rateWindows) {
      if (now - entry.startedAt >= RATE_WINDOW_MS) rateWindows.delete(entryKey);
    }
  }
}

const defaultAllowlist = [
  "dwlabs-sdr/buscar-servicos",
  "dwlabs-sdr/buscar-servico",
  "dwlabs-sdr/buscar-precos",
  "dwlabs-sdr/buscar-portfolio",
  "dwlabs-sdr/salvar-lead",
  "dwlabs-sdr/atualizar-lead",
  "dwlabs-sdr/buscar-lead",
  "dwlabs-sdr/buscar-cliente",
  "dwlabs-sdr/registrar-interacao",
  "dwlabs-sdr/calcular-score",
  "dwlabs-sdr/verificar-agenda",
  "dwlabs-sdr/agendar-reuniao",
  "dwlabs-sdr/reagendar-reuniao",
  "dwlabs-sdr/cancelar-reuniao",
  "dwlabs-sdr/criar-resumo",
  "dwlabs-sdr/notificar-vendedor",
  "dwlabs-sdr/agendar-followup",
  "dwlabs-sdr/cancelar-followup",
  "dwlabs-sdr/buscar-conhecimento",
  "dwlabs-sdr/transcrever-audio",
  "dwlabs-sdr/transferir-humano",
  "dwlabs-sdr/sincronizar-sheets"
];

const payloadSchemas = {
  buscar_servicos: Type.Object(
    {
      service_ids: Type.Optional(Type.Array(Type.String())),
      category: Type.Optional(Type.String()),
      active_only: Type.Optional(Type.Boolean())
    },
    { additionalProperties: false }
  ),
  buscar_servico: Type.Object(
    {
      service_id: Type.Optional(Type.String()),
      slug: Type.Optional(Type.String()),
      name: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  buscar_precos: Type.Object({ service_ids: Type.Array(Type.String()) }, { additionalProperties: false }),
  buscar_portfolio: Type.Object(
    {
      service_id: Type.Optional(Type.String()),
      segment: Type.Optional(Type.String()),
      limit: Type.Optional(Type.Integer())
    },
    { additionalProperties: false }
  ),
  salvar_lead: Type.Object(
    {
      source: Type.String(),
      contact_name: Type.String(),
      company_name: Type.Optional(Type.String()),
      phone: Type.Optional(Type.String()),
      email: Type.Optional(Type.String()),
      need_summary: Type.Optional(Type.String()),
      consent_status: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  atualizar_lead: Type.Object(
    {
      lead_id: Type.String(),
      stage: Type.Optional(Type.String()),
      needs: Type.Optional(Type.Array(Type.String())),
      indicative_budget: Type.Optional(Type.String()),
      urgency: Type.Optional(Type.String()),
      origin: Type.Optional(Type.String()),
      tags: Type.Optional(Type.Array(Type.String())),
      owner: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  buscar_lead: Type.Object(
    {
      lead_id: Type.Optional(Type.String()),
      phone: Type.Optional(Type.String()),
      email: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  buscar_cliente: Type.Object({ contact_ref: Type.String() }, { additionalProperties: false }),
  registrar_interacao: Type.Object(
    {
      lead_id: Type.Optional(Type.String()),
      conversation_id: Type.Optional(Type.String()),
      interaction_type: Type.String(),
      content: Type.String(),
      source_message_id: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  calcular_score: Type.Object(
    {
      lead_id: Type.Optional(Type.String()),
      facts: Type.Object({}, { additionalProperties: true })
    },
    { additionalProperties: false }
  ),
  verificar_agenda: Type.Object(
    {
      start_at: Type.String(),
      end_at: Type.String(),
      duration_minutes: Type.Integer(),
      service_type: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  agendar_reuniao: Type.Object(
    {
      lead_id: Type.String(),
      authorized: Type.Boolean(),
      starts_at: Type.String(),
      ends_at: Type.String(),
      attendee_name: Type.Optional(Type.String()),
      attendee_email: Type.Optional(Type.String()),
      notes: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  reagendar_reuniao: Type.Object(
    {
      meeting_id: Type.String(),
      target_start_at: Type.String(),
      target_end_at: Type.String()
    },
    { additionalProperties: false }
  ),
  cancelar_reuniao: Type.Object(
    {
      meeting_id: Type.String(),
      reason: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  criar_resumo: Type.Object(
    {
      lead_id: Type.Optional(Type.String()),
      conversation_id: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  notificar_vendedor: Type.Object(
    {
      lead_id: Type.Optional(Type.String()),
      priority: Type.Optional(Type.String()),
      summary: Type.String()
    },
    { additionalProperties: false }
  ),
  agendar_followup: Type.Object(
    {
      lead_id: Type.String(),
      run_at: Type.String(),
      policy_code: Type.String()
    },
    { additionalProperties: false }
  ),
  cancelar_followup: Type.Object(
    {
      followup_id: Type.Optional(Type.String()),
      lead_id: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  buscar_conhecimento: Type.Object(
    {
      query: Type.String(),
      service_id: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  transcrever_audio: Type.Object(
    {
      audio_ref: Type.String(),
      mime_type: Type.Optional(Type.String())
    },
    { additionalProperties: false }
  ),
  transferir_humano: Type.Object(
    {
      lead_id: Type.String(),
      reason: Type.String(),
      priority: Type.String()
    },
    { additionalProperties: false }
  ),
  sincronizar_sheets: Type.Object(
    {
      scope: Type.String()
    },
    { additionalProperties: false }
  )
} as const;

const toolSpecs: ToolSpec[] = [
  ["buscar_servicos", "dwlabs-sdr/buscar-servicos", "Lista servicos ativos e upsells."],
  ["buscar_servico", "dwlabs-sdr/buscar-servico", "Busca um servico especifico."],
  ["buscar_precos", "dwlabs-sdr/buscar-precos", "Consulta modo de preco sem inventar valor."],
  ["buscar_portfolio", "dwlabs-sdr/buscar-portfolio", "Retorna portfolio publico resumido."],
  ["salvar_lead", "dwlabs-sdr/salvar-lead", "Cria ou atualiza lead e conversa."],
  ["atualizar_lead", "dwlabs-sdr/atualizar-lead", "Atualiza campos allowlisted do lead."],
  ["buscar_lead", "dwlabs-sdr/buscar-lead", "Busca lead minimizado."],
  ["buscar_cliente", "dwlabs-sdr/buscar-cliente", "Consulta o proprio cliente vinculado."],
  ["registrar_interacao", "dwlabs-sdr/registrar-interacao", "Registra interacao redigida."],
  ["calcular_score", "dwlabs-sdr/calcular-score", "Calcula score deterministico."],
  ["verificar_agenda", "dwlabs-sdr/verificar-agenda", "Consulta agenda real com politica comercial."],
  ["agendar_reuniao", "dwlabs-sdr/agendar-reuniao", "Cria reuniao com autorizacao explicita."],
  ["reagendar_reuniao", "dwlabs-sdr/reagendar-reuniao", "Reagenda reuniao existente."],
  ["cancelar_reuniao", "dwlabs-sdr/cancelar-reuniao", "Cancela reuniao existente."],
  ["criar_resumo", "dwlabs-sdr/criar-resumo", "Gera resumo operacional minimizado."],
  ["notificar_vendedor", "dwlabs-sdr/notificar-vendedor", "Enfileira notificacao interna."],
  ["agendar_followup", "dwlabs-sdr/agendar-followup", "Agenda follow-up contextual."],
  ["cancelar_followup", "dwlabs-sdr/cancelar-followup", "Cancela follow-up imediatamente."],
  ["buscar_conhecimento", "dwlabs-sdr/buscar-conhecimento", "Consulta conhecimento versionado."],
  ["transcrever_audio", "dwlabs-sdr/transcrever-audio", "Transcreve audio com fail-safe."],
  ["transferir_humano", "dwlabs-sdr/transferir-humano", "Abre handoff para humano."],
  ["sincronizar_sheets", "dwlabs-sdr/sincronizar-sheets", "Sincroniza painel operacional para Sheets."]
].map(([name, endpointPath, description]) => ({
  name,
  path: endpointPath,
  description,
  parameters: baseToolInput(payloadSchemas[name as keyof typeof payloadSchemas])
}));

function buildUrl(baseUrl: string, relativePath: string): string {
  const normalizedBase = baseUrl.replace(/\/+$/, "");
  return `${normalizedBase}/${relativePath}`;
}

function assertAllowedPath(config: PluginConfig, relativePath: string): void {
  const allowlist = config.allowlist?.length ? config.allowlist : defaultAllowlist;
  if (!allowlist.includes(relativePath)) {
    throw new Error(`Endpoint nao allowlisted: ${relativePath}`);
  }
}

async function callWorkflow(
  relativePath: string,
  params: Record<string, unknown>,
  config: PluginConfig
): Promise<unknown> {
  const baseUrl = config.baseUrl;
  if (!baseUrl) {
    throw new Error("baseUrl ausente na configuracao do plugin.");
  }

  const bearerToken = config.bearerToken;
  if (!bearerToken || bearerToken.length < 43) {
    throw new Error("Bearer token SecretRef ausente ou invalido na configuracao do plugin.");
  }

  assertAllowedPath(config, relativePath);
  enforceRateLimit(relativePath, params);

  const body = JSON.stringify(params);
  const correlationId = randomUUID();
  const response = await fetch(buildUrl(baseUrl, relativePath), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${bearerToken}`,
      "x-idempotency-key": String(params.idempotency_key ?? correlationId),
      "x-correlation-id": correlationId,
      "x-agent-id": "comercial",
      "x-channel": String(params.channel ?? "test")
    },
    body,
    signal: AbortSignal.timeout(config.timeoutMs ?? 8000)
  });

  if (!response.ok) {
    throw new Error(`Falha ao chamar workflow ${relativePath}: HTTP ${response.status}`);
  }

  return response.json();
}

function senderCacheKey(senderId: string): string {
  return createHash("sha256").update(senderId).digest("hex");
}

export function normalizeWhatsAppSenderId(senderId: string): string | null {
  const digits = senderId.split("@")[0].split(":")[0].replace(/\D+/g, "");
  return digits.length >= 10 && digits.length <= 15 ? digits : null;
}

export function hasActiveHandoff(response: unknown): boolean {
  if (!response || typeof response !== "object") return false;
  const root = response as Record<string, unknown>;
  if (root.ok !== true || !root.data || typeof root.data !== "object") return false;
  const lead = (root.data as Record<string, unknown>).lead;
  if (!lead || typeof lead !== "object") return false;
  const handoff = (lead as Record<string, unknown>).handoff;
  if (!handoff || typeof handoff !== "object") return false;
  return ["open", "acknowledged"].includes(String((handoff as Record<string, unknown>).status));
}

async function shouldClaimForHumanHandoff(
  senderId: string,
  messageId: string | undefined,
  config: PluginConfig
): Promise<boolean> {
  const phone = normalizeWhatsAppSenderId(senderId);
  if (!phone) return false;
  const cacheKey = senderCacheKey(phone);
  const requestId = randomUUID();
  const envelope = {
    request_id: requestId,
    idempotency_key: `handoff-guard:${createHash("sha256").update(`${messageId ?? requestId}:${phone}`).digest("hex")}`,
    channel: "whatsapp",
    actor: { phone },
    context: { message_id: messageId ?? requestId },
    payload: { phone }
  };

  try {
    const response = await callWorkflow(
      "dwlabs-sdr/buscar-lead",
      envelope,
      { ...config, timeoutMs: Math.min(config.timeoutMs ?? 8000, 5000) }
    );
    const active = hasActiveHandoff(response);
    if (active) activeHandoffCache.set(cacheKey, Date.now());
    else activeHandoffCache.delete(cacheKey);
    return active;
  } catch {
    const lastActiveAt = activeHandoffCache.get(cacheKey);
    return typeof lastActiveAt === "number" && Date.now() - lastActiveAt <= ACTIVE_HANDOFF_FAILURE_GRACE_MS;
  }
}

const configSchema = Type.Object(
  {
    baseUrl: Type.Optional(Type.String()),
    bearerToken: Type.Optional(Type.Union([Type.String({ minLength: 43 }), secretRefSchema])),
    timeoutMs: Type.Optional(Type.Integer({ minimum: 1000, maximum: 30000 })),
    allowlist: Type.Optional(Type.Array(Type.String()))
  },
  { additionalProperties: false }
);

const plugin = defineToolPlugin({
  id: "dwlabs-sdr-tools",
  name: "DWLabs SDR Tools",
  description: "Ferramentas tipadas e allowlisted do SDR comercial da DWLabs.",
  configSchema,
  tools: (tool) =>
    toolSpecs.map((spec) =>
      tool({
        name: spec.name,
        description: spec.description,
        parameters: spec.parameters,
        execute: async (params, config) => callWorkflow(spec.path, params as Record<string, unknown>, config as PluginConfig)
      })
    )
});

const registerTools = plugin.register;
plugin.register = (api) => {
  registerTools(api);
  const config = api.pluginConfig as PluginConfig;
  api.on(
    "inbound_claim",
    async (_event, context) => {
      if (context.agentId !== "comercial" || context.channelId !== "whatsapp" || !context.senderId) return;
      if (await shouldClaimForHumanHandoff(context.senderId, context.messageId, config)) {
        return { handled: true };
      }
    },
    { priority: 100, timeoutMs: 6000 }
  );
};

export default plugin;
