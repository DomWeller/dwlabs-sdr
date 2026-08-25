# Operations

## Gates

1. build e validacao local
2. importacao de workflows (34 importados, 32 publicados, 2 schedulers opcionais inativos)
3. migrations e seed
4. instalacao do plugin e configuracao do agente `comercial`
5. testes owner-only
6. piloto controlado
7. exposicao publica apenas com `SDR_PUBLIC_FLAG=true`

O gate 7 e o ultimo, nunca uma etapa automatica do deploy.

## Runtime administrativo

```bash
bash scripts/deploy-runtime.sh
bash scripts/publish-admin-tailnet.sh
```

O deploy gera segredos ausentes sem imprimi-los. A senha inicial fica em
`.admin-initial-password` com modo `600`; deve ser lida pelo proprietario, trocada e removida depois.
O painel escuta em `127.0.0.1:5680` e o Tailscale Serve usa HTTPS `:8445`.
Em `Atendimento humano`, `Assumir` muda o handoff para `acknowledged` e `Encerrar` libera novamente
as respostas automaticas daquele contato. O encerramento nao recria follow-ups cancelados.
O painel tambem permite manter catalogo, preco/faixa, link comercial HTTPS, portfolio, conhecimento,
perguntas, score, horario comercial, pipeline e fila LGPD. Toda mutacao usa CSRF, transacao e log
administrativo redigido.

## Piloto owner-only

```bash
bash scripts/pilot-status.sh
CONFIRM_PILOT_OWNER_ONLY=YES bash scripts/pilot-start.sh
bash scripts/pilot-stop.sh
```

`pilot-start` e o unico comando que altera o binding. `deploy.sh`, `deploy-runtime.sh` e migrations
nao ligam o WhatsApp comercial. `pilot-stop` desliga automacoes, cancela a fila ainda nao enviada e
remove o binding comercial.

## Estado operacional de referencia

```text
OpenClaw    2026.7.1-2   container openclaw-openclaw-gateway-1
n8n         2.34.5       container n8n
PostgreSQL               container n8n-postgres, banco dwlabs_sdr

servicos=13  portfolio=3  leads=0  contatos=0  conversas=0
schemas: core, rag, ops, audit, api

workflows presentes=34  ativos=32  webhooks publicos=22  webhook interno=1
ferramentas do agente comercial=22
SDR_PUBLIC_FLAG=false  SDR_BIND_WHATSAPP=false
```

## Scripts

- `scripts/backup.sh` — tolera banco ou n8n inicialmente vazios
- `scripts/deploy.sh` — build, bootstrap-env, backup, banco, migration, seed, workflows,
  OpenClaw e healthcheck; nao ativa WhatsApp publico
- `scripts/rollback.sh`
- `scripts/migrate.sh`
- `scripts/seed.sh`
- `scripts/import-workflows.sh` — importa 34, publica 32, despublica 2, reinicia o n8n
- `scripts/export-workflows.sh`
- `scripts/install-openclaw.sh` — idempotente; pula reinstalacao se o plugin for identico
- `scripts/bootstrap-env.sh` — recarrega o `.env` depois de preservar/gerar valores
- `scripts/healthcheck.sh`
- `scripts/integration-test.sh` — exercita as 22 ferramentas com dois contatos sinteticos e
  remove os dados do teste mesmo quando a execucao falha
- `scripts/test.sh`

## Rotina rapida

```bash
cd /home/dominique/docker/dwlabs-sdr
bash scripts/healthcheck.sh
```

## Integracoes ainda desligadas

Estes codigos sao comportamento esperado e seguro, nao falhas:

```text
CALENDAR_DISABLED       GOOGLE_SHEETS_DISABLED   AUDIO_PROVIDER_DISABLED
NOTIFICATION_DISABLED   FOLLOWUP_DISABLED
```

## Backups

```text
backups/20260822-231016
backups/20260822-232758
backups/20260823-144409
backups/20260823-144518
/home/dominique/backups/dwlabs-sdr/20260821-171043
```

`backups/` esta no `.gitignore` e nao deve ser versionado. Nao apagar backups antes de criar e
validar um novo ponto de restauracao.

## Observacao critica

Este repositorio nao toca no servidor remoto automaticamente. A abertura publica do WhatsApp
nao deve ser executada agora. Nao alterar os stacks vizinhos (Odoo/Petshop, Fazer.AI/Chatwoot,
Portainer, Jellyfin) nem seus bancos.
