# Auditoria factual do servidor domlabs — entrada para planejamento

Data da coleta: 2026-08-21 (America/Sao_Paulo)
Host alvo: `dominique@100.94.57.43` via Tailscale. Não registrar nem copiar segredos.

## Sistema
- Ubuntu 26.04 LTS, kernel 7.0.0-29-generic, x86_64.
- 4 CPUs, 7,1 GiB RAM (aprox. 4,1 GiB disponíveis na coleta), swap 4 GiB, disco raiz 232 GiB com 187 GiB livres.
- Docker 29.7.2; Docker Compose 5.4.0; Python 3.14.4; Git 2.53.0.
- Tailscale ativo. Tailscale Serve:
  - `https://domlabs.tail3ae912.ts.net` -> OpenClaw em 127.0.0.1:18789
  - porta 8443 -> Chatwoot 127.0.0.1:3200
  - porta 8444 -> Fazer.AI 127.0.0.1:3100
- n8n exposto apenas no IP Tailscale `100.94.57.43:5678`.

## Containers existentes (não quebrar)
- `openclaw-openclaw-gateway-1`: `ghcr.io/openclaw/openclaw:2026.7.1-2`, saudável, bind host 127.0.0.1:18789.
- `n8n`: `docker.n8n.io/n8nio/n8n:2.34.5`, bind host Tailscale 100.94.57.43:5678, limite 2 GiB/1.5 CPU.
- `n8n-postgres`: `postgres:16.11-bookworm`, saudável, volume persistente; rede `n8n_n8n_internal`.
- Fazer.AI/Chatwoot com dois PostgreSQL pgvector e Redis próprios: laboratório separado, não acoplar o novo SDR a seus bancos.
- Odoo/Petshop e Portainer também ativos; não alterar.

## n8n
- Versão 2.34.5.
- Banco PostgreSQL existente e saudável.
- 0 workflows, 0 credenciais, 0 execuções, 0 community packages.
- Compose em `/home/dominique/docker/n8n/compose.yaml`; `.env` existe com modo 600.
- Diagnóstico e personalização desabilitados; runners habilitados; `no-new-privileges`; fuso America/Sao_Paulo.
- Conclusão: pode ser usado como base limpa. Preferir banco separado `dwlabs_sdr` no mesmo cluster PostgreSQL para reaproveitar infraestrutura e manter isolamento lógico. Não usar Sheets como fonte principal.

## OpenClaw
- Runtime 2026.7.1, container saudável.
- Config em `/home/dominique/docker/openclaw/data/config/openclaw.json`; compose em `/home/dominique/docker/openclaw/`.
- Gateway publicado apenas por Tailscale Serve no host, embora dentro do container a config use `gateway.bind=lan`; porta Docker está presa a 127.0.0.1.
- Plugins habilitados: WhatsApp, OpenAI, Codex, memory-core, browser, document-extract (6/70).
- Canal WhatsApp Business `default`: instalado, configurado, vinculado, running/connected/healthy. DM policy `allowlist`, permitindo somente o número do proprietário; grupos desabilitados; `selfChatMode=false`.
- Agente existente `main`, identidade `DW`: assistente privado de engenharia/operações de Dominique. Não reutilizar como agente público. Criar agente separado `comercial` com workspace, identidade, memória e ferramentas próprios, e binding explícito do canal quando tudo estiver testado.
- Ferramentas atuais do agente privado: allow browser, web_fetch, memory_search, memory_get, message; `fs.workspaceOnly=true`; comandos bash/config/mcp/plugins/debug desligados. Não relaxar permissões globais para o agente comercial.
- Nenhum MCP, webhook ou cron do OpenClaw configurado.
- Modelo atual: `openai/gpt-5.6-sol` via OAuth/Codex. Catálogo autenticado inclui gpt-5.4-mini/nano, gpt-5.5, gpt-5.6 e variantes. OAuth estava utilizável, mas o login reportou expiração em ~22 horas na coleta. Essa renovação pode exigir ação manual do proprietário.
- `openclaw config validate` passou. `openclaw security audit` sem crítico; deep audit teve um aviso de probe por falta do escopo `operator.read`, não vulnerabilidade confirmada.
- OpenClaw possui suporte/plugin de WhatsApp e pode manter sessões por peer. Suporte de áudio ainda não está configurado: Whisper local/API e Deepgram aparecem como não preparados/desabilitados.

## Repositórios e ferramentas
- Fonte do OpenClaw em `/home/dominique/docker/openclaw`, checkout detached na tag `v2026.7.1-2`; não modificar o core. Dados/config/backup aparecem untracked e devem permanecer fora do versionamento.
- Diretório n8n não é Git.
- Claude Code não está instalado no servidor. No Mac, Claude Code 2.1.223 existe, mas não está autenticado.
- Codex CLI 0.146.0 no Mac, autenticado via ChatGPT. Pode ser usado como executor temporário.
- Hermes remoto 0.20.0.

## Backups já feitos e verificados
- Backup pré-implementação: `/home/dominique/backups/dwlabs-sdr/20260821-171043`.
- Contém archive OpenClaw verificado, dump custom-format do PostgreSQL n8n validado com `pg_restore -l`, composes e SHA256SUMS; permissões restritas.

## Pesquisa de templates (usar só como referência, não importar cegamente)
- n8n 4508: Multi-platform AI sales agent with RAG, CRM logging & appointment booking.
- n8n 4083: WhatsApp/FB/IG, áudio, CRM, Supabase e subworkflow de calendário; dependências Airtable/Supabase/OpenAI devem ser removidas na nossa versão.
- n8n 5387/3131/8635: disponibilidade, horário comercial, booking no Google Calendar.
- n8n 15751/6212 e docs oficiais PGVector: padrões de ingestão e recuperação RAG.
- n8n 8773: qualificação BANT/follow-up multicanal.
- Decisão preliminar: implementar subworkflows determinísticos próprios, com PostgreSQL principal e integração OpenClaw estritamente allowlisted; reaproveitar padrões, não dependências externas.
