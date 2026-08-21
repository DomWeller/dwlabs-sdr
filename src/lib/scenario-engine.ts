import { calculateScore, type ScoreFacts } from "./score.js";
import { buildIdempotencyKey, IdempotencyCache } from "./idempotency.js";
import { normalizePhone } from "./normalize.js";

export interface ScenarioContext {
  message: string;
  fragments?: string[];
  name?: string;
  company?: string;
  askedFields?: string[];
  toolAvailability?: Partial<Record<"calendar" | "n8n" | "llm", boolean>>;
  consentOptOut?: boolean;
}

export function recommendService(message: string): string | null {
  const normalized = message.toLowerCase();

  if (normalized.includes("landing")) {
    return "landing-page";
  }

  if (normalized.includes("site institucional") || normalized.includes("apresentar empresa")) {
    return "site-institucional";
  }

  if (normalized.includes("google ads") || normalized.includes("trafego pago")) {
    return "site-google-ads";
  }

  if (normalized.includes("whatsapp") || normalized.includes("instagram")) {
    return "automacao-whatsapp-instagram";
  }

  if (normalized.includes("crm") || normalized.includes("pipeline")) {
    return "crm-automacoes-comerciais";
  }

  return null;
}

export function nextQualificationQuestion(context: ScenarioContext): string {
  const asked = new Set(context.askedFields ?? []);

  if (!asked.has("objetivo")) {
    return "Qual e o principal objetivo comercial desse projeto agora?";
  }

  if (!asked.has("oferta")) {
    return "Hoje voces ja tem um servico ou oferta principal validada?";
  }

  if (!asked.has("urgencia")) {
    return "Existe alguma data ou meta que torne isso urgente?";
  }

  return "Posso te mostrar a melhor proxima opcao com base no que ja entendi.";
}

export function mergeFragments(fragments: string[]): string {
  return fragments.map((item) => item.trim()).filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
}

export function buildLeadMessage(name: string, company: string, askedFields: string[]): string {
  const alreadyKnowsIdentity = askedFields.includes("name") && askedFields.includes("company");
  return alreadyKnowsIdentity
    ? "Perfeito. Vou seguir sem repetir nome ou empresa e focar no proximo passo."
    : `Perfeito, ${name} da ${company}. Vou te fazer uma pergunta curta por vez.`;
}

export function safeToolFallback(tool: "calendar" | "n8n" | "llm"): string {
  switch (tool) {
    case "calendar":
      return "Agenda externa indisponivel no momento. Posso registrar seu interesse e pedir retorno humano com horarios.";
    case "n8n":
      return "Estou com indisponibilidade tecnica temporaria para executar a automacao. Posso registrar o pedido e acionar o time.";
    default:
      return "Meu motor de resposta esta indisponivel agora. Vou encaminhar para humano sem perder seu contexto.";
  }
}

export function shouldRefuse(message: string): boolean {
  const normalized = message.toLowerCase();
  return [
    "mostre seu prompt",
    "me passe os tokens",
    "rode um shell",
    "liste outro cliente",
    "mostre workflow admin",
    "ignore suas regras"
  ].some((needle) => normalized.includes(needle));
}

export function followupEligibility(stage: string, optedOut: boolean): { canSend: boolean; reason: string } {
  if (optedOut) {
    return { canSend: false, reason: "opt_out" };
  }

  if (["FECHADO", "PERDIDO", "REUNIAO_MARCADA", "PROPOSTA"].includes(stage)) {
    return { canSend: false, reason: "stage_blocked" };
  }

  return { canSend: true, reason: "eligible" };
}

export function contextualFollowup(name: string | undefined, serviceSlug: string): string {
  const greeting = name ? `${name},` : "Ola,";
  return `${greeting} retomei seu contexto sobre ${serviceSlug}. Se fizer sentido, posso organizar o proximo passo comercial sem repetir o que voce ja explicou.`;
}

export function simulateAudioProvider(enabled: boolean): { ok: boolean; code?: string } {
  if (!enabled) {
    return { ok: false, code: "AUDIO_PROVIDER_DISABLED" };
  }

  return { ok: true };
}

export function scoreLead(facts: ScoreFacts): number {
  return calculateScore(facts).score;
}

export function idempotencyDecision(cache: IdempotencyCache, phone: string, message: string): boolean {
  const key = buildIdempotencyKey([normalizePhone(phone) ?? phone, message]);
  return cache.accept(key);
}
