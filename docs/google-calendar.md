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
- adaptadores nativos inativos:
  - `workflows/adapters/sdr.google-calendar.availability.adapter.json`
  - `workflows/adapters/sdr.google-calendar.create.adapter.json`
  - `workflows/adapters/sdr.google-calendar.update.adapter.json`
  - `workflows/adapters/sdr.google-calendar.delete.adapter.json`
- dispatchers inativos: `sdr.google-calendar.create.scheduler`,
  `sdr.google-calendar.update.scheduler` e `sdr.google-calendar.delete.scheduler`
- fila transacional: `ops.calendar_integration_jobs`, criada pela migration `007`

Os adaptadores usam o node Google Calendar `1.3` presente no n8n instalado, timezone
`America/Sao_Paulo`, Google Meet na criacao, atualizacoes enviadas aos convidados e tres
tentativas. Criar, atualizar e excluir exigem `authorized=true`. Eles sao importados sempre
inativos e nao sao publicados apenas por mudar uma flag.

Os dispatchers reservam um job com `FOR UPDATE SKIP LOCKED`, usam lease de cinco minutos,
limitam a tres tentativas e concluem apenas o job reservado. IDs externos, URL do Meet e codigo
de erro sanitizado ficam no banco; o outbox nao persiste telefone nem e-mail. Se a execucao do
Google parar, o lease expirado torna o job elegivel novamente, sem publicar automaticamente.

## Teste sem OAuth

Use `channel=test` e `fixture_mode=true` em `verificar_agenda`. O resultado e calculado sobre a
janela solicitada e exclui horario fechado, `core.calendar_blocks`, reunioes locais e o periodo
ocupado da fixture. Fora desse modo, a ausencia de OAuth retorna `CALENDAR_DISABLED`.

## Ativacao manual exata

1. no n8n, criar uma credencial Google Calendar OAuth2 com ID
   `DWLABS_SDR_GOOGLE_CALENDAR_ID` e nome `DWLABS_SDR_GOOGLE_CALENDAR`
2. concluir o consentimento OAuth na conta e calendario aprovados pelo proprietario
3. atualizar `ops.runtime_flags.metadata.calendar_id` da flag `google_calendar_enabled`
4. executar disponibilidade/criacao/alteracao/exclusao com dados sinteticos owner-only e remover
   os eventos de teste no Google
5. somente apos conferir os resultados, definir a flag como `true` e publicar os quatro
   adaptadores mais os tres schedulers Calendar

Importar ou mudar a flag isoladamente nao publica nenhum workflow Google.
