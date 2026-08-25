import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const [baseUrlInput, runId] = process.argv.slice(2);
const bearerToken = readFileSync(0, "utf8").trim();
const baseUrl = String(baseUrlInput ?? "").replace(/\/+$/, "");

assert.match(runId ?? "", /^[A-Za-z0-9-]+$/, "run_id invalido");
assert.ok(baseUrl.startsWith("http://") || baseUrl.startsWith("https://"), "base_url invalida");
assert.ok(bearerToken.length >= 43, "Bearer token ausente ou invalido");

const suffix = String(Date.now()).slice(-8);
const phoneA = `55119${suffix}`;
const phoneB = `55118${suffix}`;
const emailA = `codex-${runId}-a@example.invalid`;
const emailB = `codex-${runId}-b@example.invalid`;
const companyA = `Codex Integration ${runId} A`;
const companyB = `Codex Integration ${runId} B`;
const actorA = { contact_name: "Integracao A", phone: phoneA, email: emailA, company_name: companyA };
const actorB = { contact_name: "Integracao B", phone: phoneB, email: emailB, company_name: companyB };
const exercisedTools = new Set();
let sequence = 0;

const endpointByTool = {
  buscar_servicos: "buscar-servicos",
  buscar_servico: "buscar-servico",
  buscar_precos: "buscar-precos",
  buscar_portfolio: "buscar-portfolio",
  salvar_lead: "salvar-lead",
  atualizar_lead: "atualizar-lead",
  buscar_lead: "buscar-lead",
  buscar_cliente: "buscar-cliente",
  registrar_interacao: "registrar-interacao",
  calcular_score: "calcular-score",
  verificar_agenda: "verificar-agenda",
  agendar_reuniao: "agendar-reuniao",
  reagendar_reuniao: "reagendar-reuniao",
  cancelar_reuniao: "cancelar-reuniao",
  criar_resumo: "criar-resumo",
  notificar_vendedor: "notificar-vendedor",
  agendar_followup: "agendar-followup",
  cancelar_followup: "cancelar-followup",
  buscar_conhecimento: "buscar-conhecimento",
  transcrever_audio: "transcrever-audio",
  transferir_humano: "transferir-humano",
  sincronizar_sheets: "sincronizar-sheets"
};

function makeEnvelope(tool, payload, actor = actorA, context = {}, idempotencyKey) {
  sequence += 1;
  const suffixValue = String(sequence).padStart(2, "0");
  return {
    request_id: `${runId}-${tool}-${suffixValue}`,
    idempotency_key: idempotencyKey ?? `${runId}-${tool}-${suffixValue}`,
    channel: "test",
    actor,
    context,
    payload
  };
}

async function request(tool, envelope, { authenticated = true } = {}) {
  const headers = {
    "content-type": "application/json",
    "x-agent-id": "comercial",
    "x-channel": "test",
    "x-correlation-id": envelope.request_id
  };
  if (authenticated) {
    headers.authorization = `Bearer ${bearerToken}`;
  }

  const response = await fetch(`${baseUrl}/dwlabs-sdr/${endpointByTool[tool]}`, {
    method: "POST",
    headers,
    body: JSON.stringify(envelope),
    signal: AbortSignal.timeout(15000)
  });

  let body = null;
  const rawBody = await response.text();
  if (rawBody) {
    try {
      body = JSON.parse(rawBody);
    } catch {
      body = rawBody;
    }
  }

  if (authenticated) {
    exercisedTools.add(tool);
    assert.equal(response.status, 200, `${tool}: HTTP ${response.status}`);
    assert.equal(typeof body, "object", `${tool}: resposta nao JSON`);
    assert.equal(typeof body.ok, "boolean", `${tool}: envelope sem ok booleano`);
    assert.ok("data" in body, `${tool}: envelope sem data`);
    assert.ok("error" in body, `${tool}: envelope sem error`);
  }

  return { status: response.status, body, envelope };
}

function expectSuccess(result, label) {
  assert.equal(result.body.ok, true, `${label}: ${result.body.error?.code ?? "falha inesperada"}`);
  assert.equal(result.body.error, null, `${label}: error deveria ser null`);
  return result.body.data;
}

function expectError(result, code, label) {
  assert.equal(result.body.ok, false, `${label}: deveria falhar com ${code}`);
  assert.equal(result.body.data, null, `${label}: data deveria ser null`);
  assert.equal(result.body.error?.code, code, `${label}: codigo de erro divergente`);
}

const negativeAuth = await request(
  "buscar_servicos",
  makeEnvelope("buscar_servicos", { active_only: true }),
  { authenticated: false }
);
assert.equal(negativeAuth.status, 403, "webhook sem Bearer deveria retornar HTTP 403");

const services = expectSuccess(
  await request("buscar_servicos", makeEnvelope("buscar_servicos", { active_only: true })),
  "buscar_servicos"
);
assert.equal(services.services.length, 13, "catalogo deveria conter 13 servicos ativos");

const service = expectSuccess(
  await request("buscar_servico", makeEnvelope("buscar_servico", { slug: "landing-page" })),
  "buscar_servico"
);
assert.equal(service.service.slug, "landing-page");

const prices = expectSuccess(
  await request("buscar_precos", makeEnvelope("buscar_precos", { service_ids: ["landing-page"] })),
  "buscar_precos"
);
assert.equal(prices.prices.length, 1);

const portfolio = expectSuccess(
  await request("buscar_portfolio", makeEnvelope("buscar_portfolio", { limit: 3 })),
  "buscar_portfolio"
);
assert.ok(portfolio.items.length > 0 && portfolio.items.length <= 3);

const knowledge = expectSuccess(
  await request("buscar_conhecimento", makeEnvelope("buscar_conhecimento", { query: "landing page" })),
  "buscar_conhecimento"
);
assert.ok(Array.isArray(knowledge.matches));

const anonymousScore = expectSuccess(
  await request(
    "calcular_score",
    makeEnvelope("calcular_score", {
      facts: {
        has_defined_offer: true,
        urgency_level: "alta",
        budget_signal: "alto",
        authority_level: "decisor",
        inbound_intent: "forte",
        existing_channels: "misto",
        wants_meeting: true,
        asks_for_proposal: true
      }
    })
  ),
  "calcular_score sem persistencia"
);
assert.equal(anonymousScore.score, 100);

const disabledChecks = [
  ["verificar_agenda", { start_at: "2030-01-10T14:00:00Z", end_at: "2030-01-10T18:00:00Z", duration_minutes: 30 }, "CALENDAR_DISABLED"],
  ["agendar_reuniao", { lead_id: "00000000-0000-0000-0000-000000000000", authorized: true, starts_at: "2030-01-10T14:00:00Z", ends_at: "2030-01-10T14:30:00Z" }, "CALENDAR_DISABLED"],
  ["reagendar_reuniao", { meeting_id: "00000000-0000-0000-0000-000000000000", target_start_at: "2030-01-10T15:00:00Z", target_end_at: "2030-01-10T15:30:00Z" }, "CALENDAR_DISABLED"],
  ["cancelar_reuniao", { meeting_id: "00000000-0000-0000-0000-000000000000", reason: "teste" }, "CALENDAR_DISABLED"],
  ["notificar_vendedor", { priority: "baixa", summary: "teste interno" }, "NOTIFICATION_DISABLED"],
  ["transcrever_audio", { audio_ref: "test://audio", mime_type: "audio/ogg" }, "AUDIO_PROVIDER_DISABLED"],
  ["sincronizar_sheets", { scope: "pipeline" }, "GOOGLE_SHEETS_DISABLED"]
];

for (const [tool, payload, code] of disabledChecks) {
  expectError(await request(tool, makeEnvelope(tool, payload)), code, tool);
}

const saveAEnvelope = makeEnvelope(
  "salvar_lead",
  {
    source: "codex-integration",
    contact_name: actorA.contact_name,
    company_name: companyA,
    phone: phoneA,
    email: emailA,
    need_summary: "Teste controlado de integracao",
    consent_status: "granted"
  },
  actorA,
  { message_id: `${runId}-save-a` },
  `${runId}-save-a`
);
const saveAResult = await request("salvar_lead", saveAEnvelope);
const leadA = expectSuccess(saveAResult, "salvar_lead A");
assert.equal(leadA.created, true);

const replayA = expectSuccess(await request("salvar_lead", saveAEnvelope), "replay salvar_lead A");
assert.deepEqual(replayA, leadA, "replay idempotente deveria devolver a mesma resposta");

const collisionEnvelope = structuredClone(saveAEnvelope);
collisionEnvelope.payload.need_summary = "Payload diferente com a mesma chave";
expectError(
  await request("salvar_lead", collisionEnvelope),
  "IDEMPOTENCY_HASH_MISMATCH",
  "colisao de idempotencia"
);

const saveBEnvelope = makeEnvelope(
  "salvar_lead",
  {
    source: "codex-integration",
    contact_name: actorB.contact_name,
    company_name: companyB,
    phone: phoneB,
    email: emailB,
    need_summary: "Segundo contato para testar isolamento",
    consent_status: "granted"
  },
  actorB,
  { message_id: `${runId}-save-b` },
  `${runId}-save-b`
);
const leadB = expectSuccess(await request("salvar_lead", saveBEnvelope), "salvar_lead B");

const contextA = { lead_id: leadA.lead_id, conversation_id: leadA.conversation_id };
const contextB = { lead_id: leadB.lead_id, conversation_id: leadB.conversation_id };

const ownLead = expectSuccess(
  await request("buscar_lead", makeEnvelope("buscar_lead", { lead_id: leadA.lead_id }, actorA, contextA)),
  "buscar_lead proprio"
);
assert.equal(ownLead.lead.lead_id, leadA.lead_id);

const ownCustomer = expectSuccess(
  await request("buscar_cliente", makeEnvelope("buscar_cliente", { contact_ref: leadA.contact_id }, actorA, contextA)),
  "buscar_cliente proprio"
);
assert.equal(ownCustomer.customer.contact_id, leadA.contact_id);

expectError(
  await request("buscar_lead", makeEnvelope("buscar_lead", { lead_id: leadA.lead_id }, actorB, contextB)),
  "LEAD_SCOPE_FORBIDDEN",
  "isolamento buscar_lead"
);
expectError(
  await request("buscar_cliente", makeEnvelope("buscar_cliente", { contact_ref: leadA.contact_id }, actorB, contextB)),
  "CUSTOMER_SCOPE_FORBIDDEN",
  "isolamento buscar_cliente"
);

expectSuccess(
  await request(
    "atualizar_lead",
    makeEnvelope(
      "atualizar_lead",
      { lead_id: leadA.lead_id, stage: "EM_QUALIFICACAO", needs: ["landing-page"], urgency: "alta" },
      actorA,
      contextA
    )
  ),
  "atualizar_lead"
);

const interactionEnvelope = makeEnvelope(
  "registrar_interacao",
  {
    lead_id: leadA.lead_id,
    conversation_id: leadA.conversation_id,
    interaction_type: "note",
    content: `Teste interno; contato ${emailA}`,
    source_message_id: `${runId}-interaction`
  },
  actorA,
  contextA
);
interactionEnvelope.request_id = saveAEnvelope.request_id;
expectSuccess(
  await request("registrar_interacao", interactionEnvelope),
  "registrar_interacao com o mesmo evento externo de outra ferramenta"
);

const persistedScore = expectSuccess(
  await request(
    "calcular_score",
    makeEnvelope(
      "calcular_score",
      { lead_id: leadA.lead_id, facts: { urgency_level: "alta", inbound_intent: "forte" } },
      actorA,
      contextA
    )
  ),
  "calcular_score persistido"
);
assert.ok(persistedScore.score > 0);

const summary = expectSuccess(
  await request("criar_resumo", makeEnvelope("criar_resumo", { lead_id: leadA.lead_id }, actorA, contextA)),
  "criar_resumo"
);
assert.equal(typeof summary.summary, "string");
assert.ok(!summary.summary.includes(emailA), "resumo nao pode devolver email bruto");

const followup = expectSuccess(
  await request(
    "agendar_followup",
    makeEnvelope(
      "agendar_followup",
      { lead_id: leadA.lead_id, run_at: "2030-01-10T16:00:00Z", policy_code: "integration-test" },
      actorA,
      contextA
    )
  ),
  "agendar_followup"
);

const cancelledFollowup = expectSuccess(
  await request(
    "cancelar_followup",
    makeEnvelope("cancelar_followup", { followup_id: followup.followup_id }, actorA, contextA)
  ),
  "cancelar_followup"
);
assert.equal(cancelledFollowup.cancelled, true);

const handoff = expectSuccess(
  await request(
    "transferir_humano",
    makeEnvelope(
      "transferir_humano",
      { lead_id: leadA.lead_id, reason: "teste de integracao", priority: "normal" },
      actorA,
      contextA
    )
  ),
  "transferir_humano"
);
assert.equal(handoff.blocked_automation, true);
assert.equal(handoff.status, "open");
assert.equal(handoff.reused, false);

const repeatedHandoff = expectSuccess(
  await request(
    "transferir_humano",
    makeEnvelope(
      "transferir_humano",
      { lead_id: leadA.lead_id, reason: "segunda solicitacao", priority: "alta" },
      actorA,
      contextA
    )
  ),
  "transferir_humano ativo"
);
assert.equal(repeatedHandoff.handoff_id, handoff.handoff_id, "handoff ativo deveria ser reutilizado");
assert.equal(repeatedHandoff.reused, true);

const blockedLead = expectSuccess(
  await request("buscar_lead", makeEnvelope("buscar_lead", { phone: phoneA }, actorA, contextA)),
  "buscar_lead com handoff"
);
assert.equal(blockedLead.lead.handoff.handoff_id, handoff.handoff_id);
assert.equal(blockedLead.lead.handoff.status, "open");

assert.deepEqual(
  [...exercisedTools].sort(),
  Object.keys(endpointByTool).sort(),
  "a suite precisa exercitar exatamente as 22 ferramentas"
);

process.stdout.write(
  JSON.stringify({
    ok: true,
    tools_exercised: exercisedTools.size,
    services_found: services.services.length,
    idempotency_replay: true,
    idempotency_collision_blocked: true,
    same_external_event_across_tools: true,
    active_handoff_reused: true,
    cross_contact_reads_blocked: 2,
    external_integrations_remained_disabled: 7
  }) + "\n"
);
