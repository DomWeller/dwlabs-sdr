# Google Calendar

A integracao real permanece preparada, mas desligada ate configuracao manual de OAuth fora do Git.

## Politica

- timezone: `America/Sao_Paulo`
- horario comercial: segunda a sexta, `09:00-18:00`
- duracao recebida por payload
- bloquear conflito com reunioes ja registradas
- criar evento externo apenas quando `google_calendar_enabled=true`

## Artefatos

- workflow publico: `workflows/public-tools/sdr.verificar_agenda.json`
- workflows de reuniao: `sdr.agendar_reuniao`, `sdr.reagendar_reuniao`, `sdr.cancelar_reuniao`
- mock: `mocks/google-calendar.availability.json`
