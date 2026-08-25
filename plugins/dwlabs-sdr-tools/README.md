# DWLabs SDR Tools

Plugin nativo para OpenClaw `2026.7.1` com ferramentas estritamente allowlisted para o agente comercial publico da DWLabs.

## O que este plugin faz

- expone apenas ferramentas aprovadas do SDR
- chama endpoints internos do n8n por `Authorization` validado pelo `httpHeaderAuth` nativo
- impede URL arbitraria, shell, filesystem e HTTP generico
- devolve respostas estruturadas e sem segredos
- recebe o Bearer token por SecretRef oficial do OpenClaw; o valor resolvido nao e persistido no config
- assume silenciosamente mensagens de contatos com handoff aberto ou assumido, antes do modelo responder

O bloqueio de handoff consulta `buscar_lead` com o identificador do proprio remetente. Se a consulta
falhar, somente um contato ja conhecido como bloqueado permanece silenciado por ate 15 minutos;
demais contatos seguem normalmente. Nenhum telefone e escrito em log ou cache persistente.

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
