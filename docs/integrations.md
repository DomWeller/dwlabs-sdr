# Integrations

## Ativas no design

- OpenClaw plugin nativo -> n8n interno
- n8n -> PostgreSQL `dwlabs_sdr`

## Preparadas mas desativadas por padrao

- Google Calendar
- Google Sheets
- provider real de audio
- notificacao interna via webhook

## Mocks versionados

- `mocks/google-calendar.availability.json`
- `mocks/audio-transcription.json`
- `mocks/notification-dispatch.json`

Sem OAuth valido, o sistema deve responder com erro seguro ou modo `mock`, nunca inventando sucesso.
