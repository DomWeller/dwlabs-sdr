# Database

Banco logico alvo: `dwlabs_sdr` no cluster PostgreSQL ja existente do stack `n8n-postgres`.

## Schemas

- `core`: contatos, empresas, leads, conversas, interacoes, servicos, portfolio, reunioes, followups, consentimentos, handoffs
- `rag`: documentos e chunks FTS
- `ops`: flags de runtime, idempotencia, outboxes e metricas
- `audit`: trilha redigida
- `api`: funcoes SQL que servem os workflows

## Arquivos

- migration: `database/migrations/001_init.up.sql`
- rollback: `database/migrations/001_init.down.sql`
- seed: `database/seeds/001_seed_catalog.sql`
- roles template: `database/roles/001_minimum_roles.sql.template`

## Regras importantes

- score `0..100`
- bandas: frio `0-39`, morno `40-69`, quente `70-84`, muito quente `85-100`
- opt-out interrompe follow-up
- idempotencia por inbox dedicado
