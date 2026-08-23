# OpenClaw Agent

O agente `comercial` e uma identidade separada do agente privado `main`, com workspace,
prompt e politica de ferramentas proprios.

```text
id        = comercial
workspace = /home/node/.openclaw/workspace-comercial
model     = openai/gpt-5.4-mini
```

## Entradas principais

- prompt: `openclaw-agent/comercial.prompt.md`
- workspace: `openclaw-agent/comercial.workspace.md`
- config: `openclaw-agent/comercial.agent.config.json`

## Politica de ferramentas aplicada

A configuracao final depende de cinco pecas combinadas. Faltando qualquer uma, o agente
recebe zero ferramentas ou perde parte delas.

1. as 22 ferramentas SDR estao em `tools.allow` global (preservando as entradas existentes)
2. o agente privado `main` tem `tools.deny` explicito das mesmas 22 ferramentas
3. `agents.list[comercial].tools.profile = "full"`
4. o agente `comercial` mantem allowlist exata das 22 ferramentas e denylist ampla de grupos
5. `agents.list[comercial].skills = []`, evitando que skills globais entrem no prompt comercial
5. `plugins.entries.codex.config.codexDynamicToolsLoading = "direct"`

`profile: "full"` nao significa acesso amplo: a allowlist exata e a denylist aplicadas depois
do perfil removem shell, filesystem, web generica, browser, mensagens administrativas,
memoria generica, sessoes, automacao, media, nodes, gateway, config, plugins admin e debug.

Grupos negados ao `comercial`:

```text
group:runtime  group:fs        group:automation  group:web
group:ui       group:messaging group:memory      group:sessions
group:media    group:nodes     group:agents
http  gateway  config  plugins_admin  debug
```

Sem o perfil `full`, os logs mostram o sintoma:

```text
tool policy removed 29 tool(s) via tools.profile (coding)
```

## Verificacao

```bash
docker exec openclaw-openclaw-gateway-1 \
  openclaw config get 'agents.list[1].tools' --json

docker exec openclaw-openclaw-gateway-1 \
  openclaw config get 'agents.list[0].tools.deny' --json

docker exec openclaw-openclaw-gateway-1 \
  openclaw plugins inspect dwlabs-sdr-tools --runtime
```

O esperado e: 22 ferramentas permitidas ao `comercial`, as mesmas 22 negadas ao `main`, e o
plugin com `Status: loaded` expondo exatamente 22 ferramentas.

## Canal publico

- `allowPublicActivation=false`
- `publicActivationFlag=SDR_PUBLIC_FLAG`
- `SDR_PUBLIC_FLAG=false` e `SDR_BIND_WHATSAPP=false`

Nao alterar `dmPolicy`, allowlist, grupos ou binding do WhatsApp sem autorizacao explicita do
usuario e um piloto controlado.

## Instalacao / reaplicacao

```bash
bash scripts/install-openclaw.sh
```

O script e idempotente: compara `dist/index.js`, `openclaw.plugin.json` e `package.json` com o
que ja esta instalado e, se forem iguais, evita a reinstalacao lenta (`openclaw plugins install
--force` dispara `npm install` dentro do container e expira com codigo `124`). Mesmo pulando a
reinstalacao, ele reaplica ambiente, workspace, identidade, politicas e reinicia o gateway.

Mensagem esperada nesse caso:

```text
Plugin OpenClaw ja corresponde ao build atual; reinstalacao ignorada.
```
