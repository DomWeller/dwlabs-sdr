# OpenClaw Agent

O agente `comercial` foi preparado como identidade separada, com memoria curta, prompt proprio e binding `owner-only`.

## Entradas principais

- prompt: `openclaw-agent/comercial.prompt.md`
- workspace: `openclaw-agent/comercial.workspace.md`
- config: `openclaw-agent/comercial.agent.config.json`

## Politicas

- `tools.allow`: apenas as 22 ferramentas do SDR
- `tools.deny`: shell, filesystem generico, `gateway`, `cron`, `sessions_spawn`, `sessions_send`, `config`, `plugins_admin`, `debug`, `http_generic`
- `allowPublicActivation=false`
- `publicActivationFlag=SDR_PUBLIC_FLAG`

## Instalacao posterior no host

1. instalar o plugin `plugins/dwlabs-sdr-tools`
2. criar o agente `comercial`
3. aplicar prompt/workspace
4. manter binding do WhatsApp restrito ao owner ate o gate final
