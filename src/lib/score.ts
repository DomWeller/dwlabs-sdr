export interface ScoreFacts {
  hasDefinedOffer?: boolean;
  urgencyLevel?: "baixa" | "media" | "alta";
  budgetSignal?: "nenhum" | "baixo" | "medio" | "alto";
  authorityLevel?: "incerto" | "influenciador" | "decisor";
  inboundIntent?: "fraca" | "moderada" | "forte";
  existingChannels?: "nenhum" | "organico" | "pago" | "misto";
  wantsMeeting?: boolean;
  asksForProposal?: boolean;
}

export interface ScoreResult {
  score: number;
  temperatureBand: "frio" | "morno" | "quente" | "muito_quente";
  factors: Array<{ label: string; delta: number }>;
}

const clamp = (value: number, min: number, max: number): number => Math.max(min, Math.min(max, value));

export function getTemperatureBand(score: number): ScoreResult["temperatureBand"] {
  if (score >= 85) {
    return "muito_quente";
  }

  if (score >= 70) {
    return "quente";
  }

  if (score >= 40) {
    return "morno";
  }

  return "frio";
}

export function calculateScore(facts: ScoreFacts): ScoreResult {
  let total = 0;
  const factors: ScoreResult["factors"] = [];

  const add = (label: string, delta: number): void => {
    total += delta;
    factors.push({ label, delta });
  };

  add("base", 10);

  if (facts.hasDefinedOffer) {
    add("oferta_definida", 15);
  }

  switch (facts.urgencyLevel) {
    case "media":
      add("urgencia_media", 12);
      break;
    case "alta":
      add("urgencia_alta", 22);
      break;
    default:
      add("urgencia_baixa", 4);
  }

  switch (facts.budgetSignal) {
    case "baixo":
      add("orcamento_baixo", 6);
      break;
    case "medio":
      add("orcamento_medio", 12);
      break;
    case "alto":
      add("orcamento_alto", 18);
      break;
    default:
      add("orcamento_indefinido", 2);
  }

  switch (facts.authorityLevel) {
    case "influenciador":
      add("autoridade_influenciador", 8);
      break;
    case "decisor":
      add("autoridade_decisor", 14);
      break;
    default:
      add("autoridade_incerta", 2);
  }

  switch (facts.inboundIntent) {
    case "moderada":
      add("intencao_moderada", 10);
      break;
    case "forte":
      add("intencao_forte", 18);
      break;
    default:
      add("intencao_fraca", 3);
  }

  switch (facts.existingChannels) {
    case "organico":
      add("canais_organicos", 6);
      break;
    case "pago":
      add("canais_pagos", 8);
      break;
    case "misto":
      add("canais_mistos", 10);
      break;
    default:
      add("sem_canais", 2);
  }

  if (facts.wantsMeeting) {
    add("quer_reuniao", 14);
  }

  if (facts.asksForProposal) {
    add("pede_proposta", 18);
  }

  const score = clamp(total, 0, 100);

  return {
    score,
    temperatureBand: getTemperatureBand(score),
    factors
  };
}
