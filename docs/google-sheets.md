# Google Sheets

Sheets e painel operacional, nunca a fonte principal de verdade.

## Estado atual

- exportacao preparada para `ops.sheet_sync_outbox`
- sincronizacao real fica desativada enquanto `google_sheets_enabled=false`
- workflow publico: `workflows/public-tools/sdr.sincronizar_sheets.json`
- adaptador nativo inativo: `workflows/adapters/sdr.google-sheets.pipeline.adapter.json`
- dispatcher inativo: `workflows/schedulers/sdr.sheets.sync.scheduler.json`
- lease/retry transacional em `ops.sheet_sync_outbox`, endurecido pela migration `007`

O adaptador usa o node Google Sheets `4.7` e faz `appendOrUpdate` pela coluna `lead_id`. A linha
operacional contem empresa, etapa, score, temperatura, segmento, cidade, servicos, owner e
`updated_at`; telefone e e-mail nao fazem parte do schema exportado.

## Quando habilitar

1. no n8n, criar a credencial Google Sheets OAuth2 com ID
   `DWLABS_SDR_GOOGLE_SHEETS_ID` e nome `DWLABS_SDR_GOOGLE_SHEETS`
2. concluir o consentimento OAuth na planilha aprovada pelo proprietario
3. criar os cabecalhos `lead_id`, `company`, `stage`, `score`, `temperature`, `segment`, `city`,
   `services`, `owner` e `updated_at`
4. preencher `document_id` e `sheet_name` em `ops.runtime_flags.metadata`
5. testar `appendOrUpdate` owner-only, conferir que telefone/e-mail nao foram exportados e so
   entao habilitar a flag e publicar o adaptador e `sdr.sheets.sync.scheduler`

A credencial esperada e `DWLABS_SDR_GOOGLE_SHEETS_ID`. O workflow permanece importado e
despublicado ate existirem `document_id`, `sheet_name`, cabecalhos aprovados e teste controlado.
O dispatcher sincroniza uma visao lead-centrica; os escopos `meetings` e `followups` apenas
filtram leads que possuam essas entidades. PostgreSQL continua sendo a fonte principal.
