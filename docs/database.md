# Database

Banco logico alvo: `dwlabs_sdr` no cluster PostgreSQL ja existente do stack `n8n-postgres`.

## Schemas

- `core`: contatos, empresas, leads, conversas, interacoes, servicos, portfolio, reunioes, followups, consentimentos, handoffs
- `rag`: documentos e chunks FTS
- `ops`: flags de runtime, idempotencia, outboxes e metricas
- `audit`: trilha redigida
- `api`: funcoes SQL que servem os workflows

## Arquivos

- migrations: `database/migrations/001_init.up.sql` ate `006_admin_observability_crm.up.sql`
- rollbacks correspondentes: arquivos `*.down.sql`
- seed: `database/seeds/001_seed_catalog.sql`
- roles template: `database/roles/001_minimum_roles.sql.template`

## Regras importantes

- score `0..100`
- bandas: frio `0-39`, morno `40-69`, quente `70-84`, muito quente `85-100`
- opt-out interrompe follow-up
- idempotencia por inbox dedicado
- regras de score e horario comercial administraveis
- campos estruturados de briefing no lead e link comercial opcional por servico

## Migrations incrementais

O banco logico `dwlabs_sdr` usa migrations incrementais ordenadas por nome. `scripts/migrate.sh`
aplica todos os arquivos `*.up.sql`; cada migration nova deve ter um `*.down.sql` correspondente.

## Hardening operacional (`002`)

- `ops.rate_limit_windows`: contadores atomicos sem PII em claro
- `ops.delivery_outbox`: entrega idempotente, claim, retry e falha definitiva
- `ops.privacy_requests`: exportacao, anonimizacao e exclusao
- `ops.optout_suppression`: hash minimo para impedir novo contato
- `audit.admin_change_log`: mutacoes do painel

Roles:

- `dwlabs_sdr_app`: n8n e funcoes publicas
- `dwlabs_sdr_admin`: leitura operacional e mutacoes allowlisted do painel
- `dwlabs_sdr_dispatcher`: flags e funcoes `SECURITY DEFINER` de entrega apenas

Retencao default: interacoes por 90 dias; leads inativos, auditoria e metricas por 12 meses. A
funcao `ops.apply_retention(TRUE)` faz somente a simulacao; a execucao real exige `FALSE` explicito.

## Administracao e observabilidade (`006`)

- completa os campos de briefing de empresa, contato e lead
- adiciona `core.score_rules`, `core.business_hours` e `core.calendar_blocks`
- permite editar catalogo, portfolio, conhecimento e regras sem acesso direto ao banco
- registra latencia/resultado das ferramentas e chamadas do modelo em `ops.metrics_events`
- inclui rollback funcional que restaura as funcoes anteriores antes de remover tabelas/colunas
