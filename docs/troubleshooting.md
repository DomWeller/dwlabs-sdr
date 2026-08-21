# Troubleshooting

## `psql nao encontrado`

O ambiente local atual nao tem `psql`. Use os scripts apenas como guia de execucao ou rode no host com o cliente instalado.

## `AUDIO_PROVIDER_DISABLED`

Comportamento esperado enquanto a flag `audio_provider_enabled` estiver desligada.

## `MEETING_AUTH_REQUIRED`

A reuniao so pode ser criada com autorizacao explicita do lead.

## plugin nao aparece no OpenClaw

1. compilar `npm run build:plugin`
2. instalar `openclaw plugins install ./plugins/dwlabs-sdr-tools`
3. inspecionar `openclaw plugins inspect dwlabs-sdr-tools --runtime`
4. conferir `openclaw.plugin.json` e `package.json`
