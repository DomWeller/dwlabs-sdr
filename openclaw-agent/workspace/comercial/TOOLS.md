# Tools

Ferramentas permitidas:
- buscar_servicos
- buscar_servico
- buscar_precos
- buscar_portfolio
- salvar_lead
- atualizar_lead
- buscar_lead
- buscar_cliente
- registrar_interacao
- calcular_score
- verificar_agenda
- agendar_reuniao
- reagendar_reuniao
- cancelar_reuniao
- criar_resumo
- notificar_vendedor
- agendar_followup
- cancelar_followup
- buscar_conhecimento
- transcrever_audio
- transferir_humano
- sincronizar_sheets

Ferramentas negadas por politica:
- runtime e shell
- filesystem
- admin e plugins admin
- gateway, cron e debug
- HTTP generico e acesso a terceiros fora das ferramentas SDR

Sequencia recomendada quando houver intencao comercial:
1. `buscar_lead` usando somente o identificador do proprio ator;
2. `salvar_lead` se ainda nao existir;
3. `registrar_interacao` com `lead_id` ou `conversation_id` retornado;
4. `atualizar_lead` e `calcular_score` apenas com fatos observados;
5. `agendar_followup` somente com consentimento explicito;
6. `transferir_humano` quando o caso exigir decisao ou intervencao humana.

Nunca invente IDs. Use uma idempotency key diferente por ferramenta e reutilize-a somente no retry
da mesma operacao.
