export type JsonSchema = Record<string, unknown>;

export interface ToolDefinition {
  toolName: string;
  workflowName: string;
  endpointPath: string;
  sqlFunction: string;
  description: string;
  payloadSchema: JsonSchema;
  dataSchema: JsonSchema;
}

const uuidPattern = "^[0-9a-fA-F-]{36}$";

const stringArray = (description: string): JsonSchema => ({
  type: "array",
  description,
  items: { type: "string" }
});

const strictObject = (
  properties: Record<string, JsonSchema>,
  required: string[] = []
): JsonSchema => ({
  type: "object",
  additionalProperties: false,
  properties,
  required
});

export const actorSchema = strictObject(
  {
    contact_name: { type: "string" },
    phone: { type: "string" },
    email: { type: "string", format: "email" },
    company_name: { type: "string" },
    role: { type: "string" }
  }
);

export const contextSchema = strictObject({
  conversation_id: { type: "string" },
  lead_id: { type: "string" },
  message_id: { type: "string" },
  fragments: stringArray("Mensagens segmentadas ja recebidas"),
  locale: { type: "string", default: "pt-BR" }
});

export const errorSchema = strictObject(
  {
    code: { type: "string" },
    message: { type: "string" },
    retryable: { type: "boolean" }
  },
  ["code", "message", "retryable"]
);

export const auditSchema = strictObject(
  {
    correlation_id: { type: "string", pattern: uuidPattern },
    redactions_applied: {
      type: "array",
      items: { type: "string" }
    }
  },
  ["correlation_id", "redactions_applied"]
);

export const buildToolInputSchema = (payloadSchema: JsonSchema): JsonSchema =>
  strictObject(
    {
      request_id: { type: "string", pattern: uuidPattern },
      idempotency_key: { type: "string", minLength: 8 },
      channel: {
        type: "string",
        enum: ["whatsapp", "instagram", "site", "test"]
      },
      actor: actorSchema,
      context: contextSchema,
      payload: payloadSchema
    },
    ["request_id", "idempotency_key", "channel", "actor", "context", "payload"]
  );

export const buildToolOutputSchema = (dataSchema: JsonSchema): JsonSchema =>
  strictObject(
    {
      ok: { type: "boolean" },
      data: {
        anyOf: [dataSchema, { type: "null" }]
      },
      error: {
        anyOf: [errorSchema, { type: "null" }]
      },
      audit: auditSchema
    },
    ["ok", "data", "error", "audit"]
  );

export const toolDefinitions: ToolDefinition[] = [
  {
    toolName: "buscar_servicos",
    workflowName: "sdr.buscar_servicos",
    endpointPath: "dwlabs-sdr/buscar-servicos",
    sqlFunction: "api.buscar_servicos",
    description: "Lista servicos ativos com resumo, modo de preco e upsells.",
    payloadSchema: strictObject({
      service_ids: stringArray("Lista opcional de IDs ou slugs"),
      category: { type: "string" },
      active_only: { type: "boolean", default: true }
    }),
    dataSchema: strictObject({
      services: {
        type: "array",
        items: strictObject(
          {
            service_id: { type: "string" },
            slug: { type: "string" },
            name: { type: "string" },
            summary: { type: "string" },
            pricing_mode: { type: "string" },
            upsells: stringArray("Upsells possiveis")
          },
          ["service_id", "slug", "name", "summary", "pricing_mode", "upsells"]
        )
      }
    })
  },
  {
    toolName: "buscar_servico",
    workflowName: "sdr.buscar_servico",
    endpointPath: "dwlabs-sdr/buscar-servico",
    sqlFunction: "api.buscar_servico",
    description: "Busca um servico por slug, id ou nome.",
    payloadSchema: strictObject({
      service_id: { type: "string" },
      slug: { type: "string" },
      name: { type: "string" }
    }),
    dataSchema: strictObject({
      service: strictObject({
        service_id: { type: "string" },
        slug: { type: "string" },
        name: { type: "string" },
        summary: { type: "string" },
        qualification_hint: { type: "string" },
        pricing_mode: { type: "string" }
      })
    })
  },
  {
    toolName: "buscar_precos",
    workflowName: "sdr.buscar_precos",
    endpointPath: "dwlabs-sdr/buscar-precos",
    sqlFunction: "api.buscar_precos",
    description: "Consulta faixa de precos sem inventar valores.",
    payloadSchema: strictObject({
      service_ids: stringArray("IDs ou slugs de servico")
    }, ["service_ids"]),
    dataSchema: strictObject({
      prices: {
        type: "array",
        items: strictObject(
          {
            service_id: { type: "string" },
            pricing_mode: { type: "string" },
            price_from: { type: ["number", "null"] },
            price_to: { type: ["number", "null"] },
            currency: { type: "string" },
            sob_consulta: { type: "boolean" }
          },
          ["service_id", "pricing_mode", "price_from", "price_to", "currency", "sob_consulta"]
        )
      }
    })
  },
  {
    toolName: "buscar_portfolio",
    workflowName: "sdr.buscar_portfolio",
    endpointPath: "dwlabs-sdr/buscar-portfolio",
    sqlFunction: "api.buscar_portfolio",
    description: "Lista cases publicos resumidos.",
    payloadSchema: strictObject({
      service_id: { type: "string" },
      segment: { type: "string" },
      limit: { type: "integer", minimum: 1, maximum: 5, default: 3 }
    }),
    dataSchema: strictObject({
      items: {
        type: "array",
        items: strictObject(
          {
            title: { type: "string" },
            segment: { type: "string" },
            summary: { type: "string" },
            proof: { type: "string" }
          },
          ["title", "segment", "summary", "proof"]
        )
      }
    })
  },
  {
    toolName: "salvar_lead",
    workflowName: "sdr.salvar_lead",
    endpointPath: "dwlabs-sdr/salvar-lead",
    sqlFunction: "api.salvar_lead",
    description: "Cria ou atualiza contato, empresa, lead e conversa.",
    payloadSchema: strictObject(
      {
        source: { type: "string" },
        contact_name: { type: "string" },
        company_name: { type: "string" },
        phone: { type: "string" },
        email: { type: "string", format: "email" },
        need_summary: { type: "string" },
        consent_status: { type: "string", enum: ["granted", "unknown", "opted_out"] }
      },
      ["source", "contact_name"]
    ),
    dataSchema: strictObject({
      lead_id: { type: "string" },
      contact_id: { type: "string" },
      conversation_id: { type: "string" },
      created: { type: "boolean" },
      merged: { type: "boolean" }
    }, ["lead_id", "contact_id", "conversation_id", "created", "merged"])
  },
  {
    toolName: "atualizar_lead",
    workflowName: "sdr.atualizar_lead",
    endpointPath: "dwlabs-sdr/atualizar-lead",
    sqlFunction: "api.atualizar_lead",
    description: "Aplica patch allowlisted ao lead.",
    payloadSchema: strictObject(
      {
        lead_id: { type: "string" },
        stage: { type: "string" },
        needs: stringArray("Necessidades conhecidas"),
        indicative_budget: { type: "string" },
        urgency: { type: "string" },
        origin: { type: "string" },
        tags: stringArray("Tags do lead"),
        owner: { type: "string" }
      },
      ["lead_id"]
    ),
    dataSchema: strictObject({
      lead_id: { type: "string" },
      updated: { type: "boolean" }
    }, ["lead_id", "updated"])
  },
  {
    toolName: "buscar_lead",
    workflowName: "sdr.buscar_lead",
    endpointPath: "dwlabs-sdr/buscar-lead",
    sqlFunction: "api.buscar_lead",
    description: "Busca lead minimizado por id, telefone ou email.",
    payloadSchema: strictObject({
      lead_id: { type: "string" },
      phone: { type: "string" },
      email: { type: "string", format: "email" }
    }),
    dataSchema: strictObject({
      lead: strictObject({
        lead_id: { type: "string" },
        stage: { type: "string" },
        score: { type: "integer" },
        temperature_band: { type: "string" },
        needs: stringArray("Necessidades resumidas"),
        handoff: {
          anyOf: [
            strictObject(
              {
                handoff_id: { type: "string" },
                status: { type: "string", enum: ["open", "acknowledged"] },
                priority: { type: "string" }
              },
              ["handoff_id", "status", "priority"]
            ),
            { type: "null" }
          ]
        }
      })
    })
  },
  {
    toolName: "buscar_cliente",
    workflowName: "sdr.buscar_cliente",
    endpointPath: "dwlabs-sdr/buscar-cliente",
    sqlFunction: "api.buscar_cliente",
    description: "Retorna apenas o proprio contato vinculado a conversa.",
    payloadSchema: strictObject({
      contact_ref: { type: "string" }
    }, ["contact_ref"]),
    dataSchema: strictObject({
      customer: strictObject({
        contact_id: { type: "string" },
        display_name: { type: "string" },
        company_name: { type: "string" },
        stage: { type: "string" }
      })
    })
  },
  {
    toolName: "registrar_interacao",
    workflowName: "sdr.registrar_interacao",
    endpointPath: "dwlabs-sdr/registrar-interacao",
    sqlFunction: "api.registrar_interacao",
    description: "Persiste interacao redigida no historico.",
    payloadSchema: strictObject(
      {
        lead_id: { type: "string" },
        conversation_id: { type: "string" },
        interaction_type: {
          type: "string",
          enum: ["inbound", "outbound", "note", "system", "handoff", "followup"]
        },
        content: { type: "string" },
        source_message_id: { type: "string" }
      },
      ["interaction_type", "content"]
    ),
    dataSchema: strictObject({
      interaction_id: { type: "string" },
      stored: { type: "boolean" }
    }, ["interaction_id", "stored"])
  },
  {
    toolName: "calcular_score",
    workflowName: "sdr.calcular_score",
    endpointPath: "dwlabs-sdr/calcular-score",
    sqlFunction: "api.calcular_score",
    description: "Calcula score deterministico e explicavel.",
    payloadSchema: strictObject({
      lead_id: { type: "string" },
      facts: strictObject({
        has_defined_offer: { type: "boolean" },
        urgency_level: { type: "string" },
        budget_signal: { type: "string" },
        authority_level: { type: "string" },
        inbound_intent: { type: "string" },
        existing_channels: { type: "string" },
        wants_meeting: { type: "boolean" },
        asks_for_proposal: { type: "boolean" }
      })
    }),
    dataSchema: strictObject({
      score: { type: "integer" },
      temperature_band: { type: "string" },
      factors: {
        type: "array",
        items: strictObject(
          {
            label: { type: "string" },
            delta: { type: "integer" }
          },
          ["label", "delta"]
        )
      }
    }, ["score", "temperature_band", "factors"])
  },
  {
    toolName: "verificar_agenda",
    workflowName: "sdr.verificar_agenda",
    endpointPath: "dwlabs-sdr/verificar-agenda",
    sqlFunction: "api.verificar_agenda",
    description: "Retorna slots reais respeitando politicas de agenda.",
    payloadSchema: strictObject({
      start_at: { type: "string", format: "date-time" },
      end_at: { type: "string", format: "date-time" },
      duration_minutes: { type: "integer", minimum: 15, maximum: 180 },
      service_type: { type: "string" }
    }, ["start_at", "end_at", "duration_minutes"]),
    dataSchema: strictObject({
      slots: {
        type: "array",
        items: strictObject(
          {
            starts_at: { type: "string", format: "date-time" },
            ends_at: { type: "string", format: "date-time" },
            channel: { type: "string" }
          },
          ["starts_at", "ends_at", "channel"]
        )
      },
      integration_status: { type: "string" }
    }, ["slots", "integration_status"])
  },
  {
    toolName: "agendar_reuniao",
    workflowName: "sdr.agendar_reuniao",
    endpointPath: "dwlabs-sdr/agendar-reuniao",
    sqlFunction: "api.agendar_reuniao",
    description: "Cria agendamento local e prepara integracao externa autorizada.",
    payloadSchema: strictObject(
      {
        lead_id: { type: "string" },
        authorized: { type: "boolean" },
        starts_at: { type: "string", format: "date-time" },
        ends_at: { type: "string", format: "date-time" },
        attendee_name: { type: "string" },
        attendee_email: { type: "string", format: "email" },
        notes: { type: "string" }
      },
      ["lead_id", "authorized", "starts_at", "ends_at"]
    ),
    dataSchema: strictObject({
      meeting_id: { type: "string" },
      status: { type: "string" },
      external_sync: { type: "string" }
    }, ["meeting_id", "status", "external_sync"])
  },
  {
    toolName: "reagendar_reuniao",
    workflowName: "sdr.reagendar_reuniao",
    endpointPath: "dwlabs-sdr/reagendar-reuniao",
    sqlFunction: "api.reagendar_reuniao",
    description: "Reagenda reuniao de forma idempotente.",
    payloadSchema: strictObject(
      {
        meeting_id: { type: "string" },
        target_start_at: { type: "string", format: "date-time" },
        target_end_at: { type: "string", format: "date-time" }
      },
      ["meeting_id", "target_start_at", "target_end_at"]
    ),
    dataSchema: strictObject({
      meeting_id: { type: "string" },
      rescheduled: { type: "boolean" }
    }, ["meeting_id", "rescheduled"])
  },
  {
    toolName: "cancelar_reuniao",
    workflowName: "sdr.cancelar_reuniao",
    endpointPath: "dwlabs-sdr/cancelar-reuniao",
    sqlFunction: "api.cancelar_reuniao",
    description: "Cancela reuniao local e externa quando autorizado.",
    payloadSchema: strictObject(
      {
        meeting_id: { type: "string" },
        reason: { type: "string" }
      },
      ["meeting_id"]
    ),
    dataSchema: strictObject({
      meeting_id: { type: "string" },
      cancelled: { type: "boolean" }
    }, ["meeting_id", "cancelled"])
  },
  {
    toolName: "criar_resumo",
    workflowName: "sdr.criar_resumo",
    endpointPath: "dwlabs-sdr/criar-resumo",
    sqlFunction: "api.criar_resumo",
    description: "Cria resumo operacional minimizado.",
    payloadSchema: strictObject({
      lead_id: { type: "string" },
      conversation_id: { type: "string" }
    }),
    dataSchema: strictObject({
      summary: { type: "string" }
    }, ["summary"])
  },
  {
    toolName: "notificar_vendedor",
    workflowName: "sdr.notificar_vendedor",
    endpointPath: "dwlabs-sdr/notificar-vendedor",
    sqlFunction: "api.notificar_vendedor",
    description: "Enfileira notificacao interna mockavel.",
    payloadSchema: strictObject(
      {
        lead_id: { type: "string" },
        priority: { type: "string", enum: ["baixa", "media", "alta"] },
        summary: { type: "string" }
      },
      ["summary"]
    ),
    dataSchema: strictObject({
      notification_id: { type: "string" },
      mode: { type: "string" }
    }, ["notification_id", "mode"])
  },
  {
    toolName: "agendar_followup",
    workflowName: "sdr.agendar_followup",
    endpointPath: "dwlabs-sdr/agendar-followup",
    sqlFunction: "api.agendar_followup",
    description: "Cria regra de follow-up elegivel e segura.",
    payloadSchema: strictObject(
      {
        lead_id: { type: "string" },
        run_at: { type: "string", format: "date-time" },
        policy_code: { type: "string" }
      },
      ["lead_id", "run_at", "policy_code"]
    ),
    dataSchema: strictObject({
      followup_id: { type: "string" },
      scheduled: { type: "boolean" }
    }, ["followup_id", "scheduled"])
  },
  {
    toolName: "cancelar_followup",
    workflowName: "sdr.cancelar_followup",
    endpointPath: "dwlabs-sdr/cancelar-followup",
    sqlFunction: "api.cancelar_followup",
    description: "Cancela follow-up por lead ou id.",
    payloadSchema: strictObject({
      followup_id: { type: "string" },
      lead_id: { type: "string" }
    }),
    dataSchema: strictObject({
      cancelled: { type: "boolean" }
    }, ["cancelled"])
  },
  {
    toolName: "buscar_conhecimento",
    workflowName: "sdr.buscar_conhecimento",
    endpointPath: "dwlabs-sdr/buscar-conhecimento",
    sqlFunction: "api.buscar_conhecimento",
    description: "Consulta base de conhecimento via FTS.",
    payloadSchema: strictObject(
      {
        query: { type: "string" },
        service_id: { type: "string" }
      },
      ["query"]
    ),
    dataSchema: strictObject({
      matches: {
        type: "array",
        items: strictObject(
          {
            title: { type: "string" },
            snippet: { type: "string" },
            source: { type: "string" },
            score: { type: "number" }
          },
          ["title", "snippet", "source", "score"]
        )
      }
    })
  },
  {
    toolName: "transcrever_audio",
    workflowName: "sdr.transcrever_audio",
    endpointPath: "dwlabs-sdr/transcrever-audio",
    sqlFunction: "api.transcrever_audio",
    description: "Transcreve audio via provider fail-safe.",
    payloadSchema: strictObject(
      {
        audio_ref: { type: "string" },
        mime_type: { type: "string" }
      },
      ["audio_ref"]
    ),
    dataSchema: strictObject({
      transcript: { type: ["string", "null"] },
      provider_status: { type: "string" }
    }, ["transcript", "provider_status"])
  },
  {
    toolName: "transferir_humano",
    workflowName: "sdr.transferir_humano",
    endpointPath: "dwlabs-sdr/transferir-humano",
    sqlFunction: "api.transferir_humano",
    description: "Abre handoff e bloqueia automacoes indevidas.",
    payloadSchema: strictObject(
      {
        lead_id: { type: "string" },
        reason: { type: "string" },
        priority: { type: "string", enum: ["normal", "alta", "urgente"] }
      },
      ["lead_id", "reason", "priority"]
    ),
    dataSchema: strictObject({
      handoff_id: { type: "string" },
      status: { type: "string", enum: ["open", "acknowledged"] },
      reused: { type: "boolean" },
      blocked_automation: { type: "boolean" }
    }, ["handoff_id", "status", "reused", "blocked_automation"])
  },
  {
    toolName: "sincronizar_sheets",
    workflowName: "sdr.sincronizar_sheets",
    endpointPath: "dwlabs-sdr/sincronizar-sheets",
    sqlFunction: "api.sincronizar_sheets",
    description: "Enfileira exportacao operacional para Google Sheets.",
    payloadSchema: strictObject({
      scope: { type: "string", enum: ["pipeline", "followups", "meetings", "full"] }
    }, ["scope"]),
    dataSchema: strictObject({
      sync_job_id: { type: "string" },
      integration_status: { type: "string" }
    }, ["sync_job_id", "integration_status"])
  }
];

export const subworkflowNames = [
  "sdr._validate_request",
  "sdr._enforce_idempotency",
  "sdr._normalize_contact",
  "sdr._upsert_lead_bundle",
  "sdr._score_rules",
  "sdr._meeting_policy",
  "sdr._redact_log",
  "sdr._metric_emit"
] as const;

export const schedulerNames = [
  "sdr.followup.scheduler",
  "sdr.sheets.sync.scheduler",
  "sdr.health.selfcheck"
] as const;
