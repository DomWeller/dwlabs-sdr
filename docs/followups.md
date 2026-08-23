# Followups

Follow-up e deterministico na elegibilidade e pode usar redacao contextual apenas sobre contexto minimizado.

## Regras

- 1o e 2o follow-up contextual
- parada imediata em `opt-out`, handoff, reuniao marcada, proposta fechada ou pedido humano
- sem mensagens identicas em massa
- scheduler: `workflows/schedulers/sdr.followup.scheduler.json`
- 1o envio apos 24 horas e 2o apos 72 horas do primeiro
- somente segunda a sexta, 09:00-18:00, `America/Sao_Paulo`
- exige consentimento `granted` e no maximo duas mensagens
- nova entrada, opt-out ou handoff cancela fila e follow-ups pendentes
- dispatcher valida o destino contra `SDR_OWNER_ALLOWLIST`

## Tabelas

- `core.followups`
- `core.consents`
- `ops.delivery_outbox`
- `ops.optout_suppression`

## Operacao

`apps/dispatcher/worker.mjs` chama `ops.enqueue_due_followups`, faz claim atomico com
`FOR UPDATE SKIP LOCKED` e usa `openclaw message send` sem shell interpolado. Tres falhas deixam a
entrega em `failed`. As flags `followup_enabled` e `dispatcher_enabled` nascem desligadas.
