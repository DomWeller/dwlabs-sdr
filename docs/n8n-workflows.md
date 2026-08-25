# n8n Workflows

Os workflows sao gerados por `src/generators/generate-workflows.ts` e importados por
`scripts/import-workflows.sh`. A importacao nao deixa mais tudo desativado: ela publica
o conjunto operacional e mantem inativos apenas os schedulers que dependem de
integracoes externas ainda nao configuradas.

## Pastas

- `workflows/public-tools/`: 22 ferramentas publicas (um webhook por ferramenta)
- `workflows/subworkflows/`: 8 utilitarios reutilizaveis
- `workflows/internal/`: `sdr.agent.metrics`, webhook autenticado de telemetria sem conteudo de conversa
- `workflows/adapters/`: disponibilidade/criacao/reagendamento/cancelamento no Calendar/Meet e
  upsert da visao de pipeline no Sheets, todos com nodes Google nativos
- `workflows/schedulers/`: healthcheck, follow-up, Sheets e quatro dispatchers Calendar

## Estado esperado depois da importacao

```text
workflows presentes = 43
workflows ativos    = 32
webhooks registrados = 22
```

Composicao dos 32 ativos: 22 ferramentas publicas + 8 subworkflows + `sdr.agent.metrics` +
`sdr.health.selfcheck`.

Ficam **inativos de proposito**:

- `sdr.followup.scheduler` — envio real continua separado e owner-only
- `sdr.sheets.sync.scheduler` — depende de OAuth, `document_id` e teste controlado
- quatro schedulers Calendar — dependem de OAuth, `calendar_id` e teste controlado
- os 5 workflows de `workflows/adapters/` — dependem de OAuth e IDs reais de calendario/planilha

Nao reativar esses onze workflows apenas trocando a flag interna. Antes e preciso ter credenciais,
consentimento, IDs externos e teste controlado. Os dispatchers Google ja possuem claim com lease,
retry limitado e conclusao idempotente; permanecem despublicados por seguranca.

## Importacao

```bash
bash scripts/import-workflows.sh
```

O script importa os 43, publica 32, despublica os 6 schedulers opcionais e os 5 adaptadores, e reinicia o n8n para
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

Os adaptadores usam os tipos e versoes confirmados no n8n `2.34.5`: Google Calendar `1.3` e
Google Sheets `4.7`. Cada chamada mutante exige `authorized=true`, usa tres tentativas e devolve
somente metadados minimizados. Importar nao executa nem publica esses workflows.

## Outras particularidades dos exports

- cada webhook tem `webhookId` deterministico, para a publicacao ser reproduzivel
- os exports nao carregam tags: a importacao via CLI falha se a tag nao existir no n8n
- o SHA-256 usado nos Code nodes e uma implementacao pura em JavaScript, porque o sandbox do
  n8n nao expoe `crypto` nem `require('node:crypto')`
- cada workflow publico grava duracao, resultado e codigo de erro em `ops.metrics_events`
- `sdr.agent.metrics` aceita `model_call` e o fallback `agent_turn`, recebendo somente provedor,
  modelo, duracao, resultado e TTFB; nunca recebe prompt, resposta, telefone ou e-mail

Nenhum export contem token real.
