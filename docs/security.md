# Security

## Controles implementados

- `.env.example` com placeholders apenas
- `.gitignore` forte
- plugin OpenClaw com allowlist de endpoints
- `Webhook Header Auth` nativo do n8n com credencial `httpHeaderAuth` fixa/importavel
- token compartilhado de 256 bits apenas em rede privada/Tailscale
- sem shell, filesystem generico, admin, HTTP generico ou dados de terceiros para o agente comercial
- logs redigidos via `ops.redact_text`
- audit trail em `audit.redacted_event_log`

## Ativacao publica

Nao executar agora. A mudanca para publico exige flag manual `SDR_PUBLIC_FLAG=true` e gate separado.
