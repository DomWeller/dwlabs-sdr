# Troubleshooting

## `psql nao encontrado`

O ambiente local (Mac) nao tem `psql`. Use os scripts apenas como guia ou rode no host com o
cliente instalado.

## `ExpressionError: access to env vars denied`

O n8n desta instalacao bloqueia acesso a variaveis de ambiente dentro de expressoes. Nenhum
export pode usar `$env`. As credenciais sao referenciadas por ID fixo
(`DWLABS_SDR_HEADER_AUTH`, `DWLABS_SDR_POSTGRES_ID`). Se esse erro reaparecer, algum workflow
foi regerado com `$env` — corrigir em `src/lib/workflow-builder.ts` e reimportar.

## `crypto is not defined`

O Code node do n8n nao expoe `crypto` global nem `require('node:crypto')`. O SHA-256 usado nos
workflows e uma implementacao pura em JavaScript com `TextEncoder`. Nao "resolver" isso
liberando modulos nativos no sandbox.

## Webhook retorna HTTP `403`

Sem o header de autenticacao, `403` e o comportamento **correto** do Header Auth nativo do n8n
— o healthcheck depende disso. Com token valido mais `x-agent-id: comercial` e `x-channel`,
o esperado e `200` com `ok=true`.

## Scheduler falhando a cada 10 minutos

Sintoma antigo do `sdr.followup.scheduler` antes das correcoes. Hoje os schedulers de follow-up
e Sheets ficam inativos de proposito e, se executados manualmente, respondem
`FOLLOWUP_DISABLED` / `GOOGLE_SHEETS_DISABLED`.

## plugin nao aparece no OpenClaw

1. compilar `npm run build:plugin`
2. instalar `openclaw plugins install ./plugins/dwlabs-sdr-tools`
3. inspecionar `openclaw plugins inspect dwlabs-sdr-tools --runtime`
4. conferir `openclaw.plugin.json` e `package.json`

## `openclaw plugins install --force` expira com codigo `124`

O `--force` dispara `npm install` dentro do container e estoura o timeout. Use
`scripts/install-openclaw.sh`, que compara os artefatos e pula a reinstalacao quando o build ja
e identico.

## Agente comercial sem ferramentas / com ferramentas de menos

Sintoma nos logs:

```text
tool policy removed 29 tool(s) via tools.profile (coding)
```

Conferir as cinco pecas descritas em `docs/openclaw-agent.md` (allow global, deny no `main`,
`profile: "full"`, allow/deny do `comercial`, `codexDynamicToolsLoading=direct`).

## `AUDIO_PROVIDER_DISABLED`

Comportamento esperado enquanto a flag `audio_provider_enabled` estiver desligada.

## `MEETING_AUTH_REQUIRED`

A reuniao so pode ser criada com autorizacao explicita do lead.

## `npm ci` falha com arquivos de root em `node_modules`

Corrigir apenas o diretorio do projeto, sem `sudo` e sem alvo amplo:

```bash
docker run --rm \
  -v /home/dominique/docker/dwlabs-sdr/node_modules:/target \
  node:22-bookworm chown -R 1000:1000 /target
```
