# Google Calendar

A integracao real permanece preparada, mas desligada ate configuracao manual de OAuth fora do Git.

## Politica

- timezone: `America/Sao_Paulo`
- horario comercial: segunda a sexta, `09:00-18:00`
- horario comercial editavel no painel, sempre em `America/Sao_Paulo`
- duracao recebida por payload
- bloquear conflito com reunioes ja registradas
- criar evento externo apenas quando `google_calendar_enabled=true`

## Artefatos

- workflow publico: `workflows/public-tools/sdr.verificar_agenda.json`
- workflows de reuniao: `sdr.agendar_reuniao`, `sdr.reagendar_reuniao`, `sdr.cancelar_reuniao`
- mock: `mocks/google-calendar.availability.json`

## Teste sem OAuth

Use `channel=test` e `fixture_mode=true` em `verificar_agenda`. O resultado e calculado sobre a
janela solicitada e exclui horario fechado, `core.calendar_blocks`, reunioes locais e o periodo
ocupado da fixture. Fora desse modo, a ausencia de OAuth retorna `CALENDAR_DISABLED`.
