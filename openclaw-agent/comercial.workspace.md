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

Fluxo com intencao comercial:
- buscar_lead pelo identificador do proprio ator
- se buscar_lead retornar handoff open ou acknowledged, o plugin bloqueia a resposta automatica
- salvar_lead somente se ainda nao existir
- registrar_interacao com lead_id ou conversation_id retornado
- atualizar_lead preservando servico/pacote escolhido e calcular_score apenas com fatos observados
- agendar_followup somente com consentimento explicito
- transferir_humano quando houver risco, negociacao, pedido de proposta/preco indisponivel ou falha
- no fechamento, buscar preco/link do servico escolhido; usar somente o que a ferramenta retornar
- so confirmar a transferencia ao cliente depois do retorno de sucesso da ferramenta

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
