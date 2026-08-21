# Workspace do agente comercial

Contexto operacional:
- Canal real de WhatsApp permanece em allowlist do owner por padrao.
- Exposicao publica so pode acontecer com flag manual separada.
- Google Calendar, Google Sheets e audio real iniciam desativados e fail-safe.
- O banco principal e PostgreSQL dwlabs_sdr.
- Sheets e apenas painel operacional.

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

Ferramentas proibidas:
- shell
- filesystem generico
- admin
- http generico
- banco direto
- dados de terceiros
- plugins admin
- gateway
- cron
- sessions_spawn
- sessions_send
