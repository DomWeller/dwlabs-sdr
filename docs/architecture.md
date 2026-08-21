# Arquitetura

Fluxo alvo:

`WhatsApp / Instagram / site -> OpenClaw agente comercial isolado -> plugin dwlabs-sdr-tools -> n8n 2.34.5 -> PostgreSQL dwlabs_sdr`

## Principios

- agente publico separado de `main/DW`
- n8n pequeno e deterministico, um workflow por ferramenta
- banco como fonte principal; Sheets apenas painel
- logs redigidos e sem PII aberta
- falha segura quando OAuth, audio ou notificacao real nao estiverem habilitados

## Componentes versionados

- `database/migrations/001_init.up.sql`: schemas `core`, `rag`, `ops`, `audit`, `api`
- `workflows/public-tools/*.json`: endpoints importaveis do n8n
- `plugins/dwlabs-sdr-tools/`: cliente autenticado para OpenClaw
- `openclaw-agent/comercial.agent.config.json`: politicas e isolamento do agente
