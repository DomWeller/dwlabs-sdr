# DWLabs SDR Comercial 24/7

Implementacao local versionavel do SDR comercial da DWLabs sobre `OpenClaw 2026.7.1` + `n8n 2.34.5`, preparada para usar PostgreSQL `dwlabs_sdr` separado no cluster existente e manter o WhatsApp em `owner-only` por padrao.

## O que este repositorio entrega

- migrations SQL com rollback e seed inicial de catalogo
- contratos JSON por ferramenta
- gerador/export de workflows n8n pequenos, public tools, subworkflows e schedulers
- plugin OpenClaw tipado com `Authorization` via `httpHeaderAuth` nativo do n8n e allowlist de endpoints
- prompt, workspace e config do agente `comercial`
- scripts idempotentes de backup, deploy, rollback, migrate, seed, import/export, healthcheck e teste
- dispatchers fail-safe para Calendar, audio, Sheets e notificacao quando a credencial estiver ausente
- observabilidade redigida e 20 cenarios automatizados

## Fluxo recomendado

```bash
npm install
npm run build
npm run validate
npm run test
npm run scan:secrets
```

## Estrutura principal

- `database/`: migrations, rollback, seed e template de roles
- `contracts/`: schemas JSON das ferramentas
- `workflows/`: exports importaveis para n8n
- `plugins/dwlabs-sdr-tools/`: plugin OpenClaw nativo
- `openclaw-agent/`: prompt, workspace e config isolada do agente comercial
- `scripts/`: operacao idempotente para rodar dentro do host remoto com Docker
- `docs/`: arquitetura, integracoes, seguranca, operacao e troubleshooting

## Limites e seguranca

- sem segredos versionados; `.env.example` usa placeholders
- WhatsApp permanece `owner-only`; exposicao publica exige `SDR_PUBLIC_FLAG=true` em etapa manual separada
- agente comercial nao recebe shell, filesystem generico, admin, HTTP generico nem dados de terceiros
- Google Calendar, Google Sheets e audio real ficam desativados ate configuracao manual externa
