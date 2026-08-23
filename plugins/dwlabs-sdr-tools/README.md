# DWLabs SDR Tools

Plugin nativo para OpenClaw `2026.7.1` com ferramentas estritamente allowlisted para o agente comercial publico da DWLabs.

## O que este plugin faz

- expone apenas ferramentas aprovadas do SDR
- chama endpoints internos do n8n por `Authorization` validado pelo `httpHeaderAuth` nativo
- impede URL arbitraria, shell, filesystem e HTTP generico
- devolve respostas estruturadas e sem segredos
- recebe o Bearer token por SecretRef oficial do OpenClaw; o valor resolvido nao e persistido no config

## Build local

```bash
npm install
npm run build:plugin
```

## Instalacao posterior no host

```bash
openclaw plugins install ./plugins/dwlabs-sdr-tools
openclaw plugins inspect dwlabs-sdr-tools --runtime
```
