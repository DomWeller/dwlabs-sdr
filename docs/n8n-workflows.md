# n8n Workflows

Os workflows sao gerados por `src/generators/generate-workflows.ts` e importados por
`scripts/import-workflows.sh`. A importacao nao deixa mais tudo desativado: ela publica
o conjunto operacional e mantem inativos apenas os schedulers que dependem de
integracoes externas ainda nao configuradas.

## Pastas

- `workflows/public-tools/`: 22 ferramentas publicas (um webhook por ferramenta)
- `workflows/subworkflows/`: 8 utilitarios reutilizaveis
- `workflows/schedulers/`: `sdr.health.selfcheck`, `sdr.followup.scheduler`, `sdr.sheets.sync.scheduler`

## Estado esperado depois da importacao

```text
workflows presentes = 33
workflows ativos    = 31
webhooks registrados = 22
```

Composicao dos 31 ativos: 22 ferramentas publicas + 8 subworkflows + `sdr.health.selfcheck`.

Ficam **inativos de proposito**:

- `sdr.followup.scheduler` — responde `FOLLOWUP_DISABLED`
- `sdr.sheets.sync.scheduler` — responde `GOOGLE_SHEETS_DISABLED`

Nao reativar esses dois apenas trocando a flag interna. Antes e preciso ter dispatcher real,
credenciais, opt-out, retry e teste controlado.

## Importacao

```bash
bash scripts/import-workflows.sh
```

O script importa os 33, publica 31, despublica os 2 opcionais e reinicia o n8n para
consolidar os webhooks.

## Credenciais fixas

Os exports **nao usam expressoes `$env`**: o ambiente do n8n bloqueia acesso a variaveis de
ambiente dentro de expressoes (`ExpressionError: access to env vars denied`). Por isso os IDs
de credencial sao fixos e precisam existir no n8n antes da importacao:

- Header Auth: `DWLABS_SDR_HEADER_AUTH`
- PostgreSQL: `DWLABS_SDR_POSTGRES_ID`

`scripts/import-workflows.sh` falha cedo se encontrar IDs diferentes desses.

Google Calendar (`DWLABS_SDR_GOOGLE_CALENDAR`) e Google Sheets (`DWLABS_SDR_GOOGLE_SHEETS`)
seguem como placeholders, sem OAuth configurado.

## Outras particularidades dos exports

- cada webhook tem `webhookId` deterministico, para a publicacao ser reproduzivel
- os exports nao carregam tags: a importacao via CLI falha se a tag nao existir no n8n
- o SHA-256 usado nos Code nodes e uma implementacao pura em JavaScript, porque o sandbox do
  n8n nao expoe `crypto` nem `require('node:crypto')`

Nenhum export contem token real.
