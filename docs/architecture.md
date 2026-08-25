# Arquitetura

Fluxo alvo:

`WhatsApp / Instagram / site -> OpenClaw agente comercial isolado -> plugin dwlabs-sdr-tools -> n8n 2.34.5 -> PostgreSQL dwlabs_sdr`

## Principios

- agente publico separado de `main/DW`
- n8n pequeno e deterministico, um workflow por ferramenta
- banco como fonte principal; Sheets apenas painel
- logs redigidos e sem PII aberta
- falha segura quando OAuth, audio ou notificacao real nao estiverem habilitados
- contexto comercial minimo e recuperado do PostgreSQL a cada turno de WhatsApp, reduzindo perda
  intermitente de contexto apos compactacao de sessao
- handoff ativo e verificado no canal real antes do roteamento; o bot nao recebe o turno enquanto
  o atendimento humano estiver aberto ou assumido

## Componentes versionados

- `database/migrations/*.up.sql`: schemas `core`, `rag`, `ops`, `audit`, `api` e evolucoes incrementais
- `workflows/public-tools/*.json`: endpoints importaveis do n8n
- `workflows/internal/sdr.agent.metrics.json`: telemetria autenticada sem conteudo de conversa
- `plugins/dwlabs-sdr-tools/`: cliente autenticado para OpenClaw
- `openclaw-agent/comercial.agent.config.json`: politicas e isolamento do agente
