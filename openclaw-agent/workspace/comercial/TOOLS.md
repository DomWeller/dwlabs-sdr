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
2. se houver handoff `open` ou `acknowledged`, nao continuar nem responder;
3. `salvar_lead` se ainda nao existir;
4. `registrar_interacao` com `lead_id` ou `conversation_id` retornado;
5. `atualizar_lead` preservando o servico/pacote escolhido e `calcular_score` apenas com fatos observados;
6. `agendar_followup` somente com consentimento explicito;
7. `transferir_humano` quando o caso exigir decisao, proposta, preco indisponivel ou intervencao humana.

Nunca invente IDs. Use uma idempotency key diferente por ferramenta e reutilize-a somente no retry
da mesma operacao. So confirme um handoff depois de sucesso da ferramenta. Use no maximo tres
chamadas por mensagem e um unico retry por falha.
