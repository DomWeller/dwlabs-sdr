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

## Caminhos de fixture executaveis

- audio: `audio_ref=fixture://audio-ptbr-comercial`, somente com `channel=test`
- Calendar: `fixture_mode=true`, somente com `channel=test`; usa horario comercial, bloqueios,
  reunioes locais e o slot ocupado do mock

As fixtures nunca sao aceitas no WhatsApp real. Habilitar uma flag sem configurar o adaptador nao
cria um sucesso falso: audio retorna `AUDIO_ADAPTER_NOT_CONFIGURED` e Calendar continua declarando
que o despacho OAuth e necessario.

## Acoes manuais restantes

1. criar as credenciais OAuth no n8n usando os IDs placeholder documentados
2. conceder escopos apenas para o calendario e planilha operacionais da DWLabs
3. testar em owner-only e conferir conflito, criacao, reagendamento, cancelamento e sync
4. somente depois ativar `google_calendar_enabled` ou `google_sheets_enabled`
5. escolher e autorizar um provider de audio antes de adicionar chave ou custo
