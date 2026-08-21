# current-state-audit.md

## Fase 0

Este documento registra apenas o estado atual inferido a partir de `AUDIT_INPUT.md`.

Escopo desta fase:

- compilar evidências da coleta já fornecida;
- identificar restrições operacionais;
- separar fatos de inferências;
- não propor aqui nenhuma mudança já executada.

## Fonte única desta fase

- `AUDIT_INPUT.md`

## Método

- leitura documental apenas;
- sem assumir validação independente adicional dentro desta Fase 0;
- sem registrar segredos.

## Evidências factuais

### Host e capacidade

- Data da coleta: `2026-08-21` em `America/Sao_Paulo`.
- Host alvo: `dominique@100.94.57.43` via Tailscale.
- Sistema: Ubuntu 26.04 LTS, kernel `7.0.0-29-generic`, `x86_64`.
- Recursos: 4 CPUs, 7,1 GiB RAM, swap 4 GiB, 232 GiB de disco raiz com 187 GiB livres.
- Docker `29.7.2`, Docker Compose `5.4.0`, Python `3.14.4`, Git `2.53.0`.

Leitura da evidência:

- o host tem capacidade suficiente para ampliar a automação sem nova VM;
- a margem de RAM existe, mas não é folgada a ponto de justificar novos componentes pesados por padrão.

### Exposição de serviços

- Tailscale ativo.
- Tailscale Serve:
  - `https://domlabs.tail3ae912.ts.net` para OpenClaw em `127.0.0.1:18789`
  - `8443` para Chatwoot em `127.0.0.1:3200`
  - `8444` para Fazer.AI em `127.0.0.1:3100`
- n8n exposto apenas em `100.94.57.43:5678`.

Leitura da evidência:

- OpenClaw não está publicado diretamente em interface pública ampla;
- n8n já está acessível apenas pela malha Tailscale, o que favorece chamadas internas controladas.

### Containers existentes e restrição de não interferência

- OpenClaw:
  - container `openclaw-openclaw-gateway-1`
  - imagem `ghcr.io/openclaw/openclaw:2026.7.1-2`
  - saudável
  - bind host `127.0.0.1:18789`
- n8n:
  - container `n8n`
  - imagem `docker.n8n.io/n8nio/n8n:2.34.5`
  - bind host `100.94.57.43:5678`
  - limites `2 GiB / 1.5 CPU`
- PostgreSQL do n8n:
  - container `n8n-postgres`
  - imagem `postgres:16.11-bookworm`
  - saudável
  - volume persistente
  - rede `n8n_n8n_internal`
- Outros stacks ativos:
  - Fazer.AI/Chatwoot com bancos próprios
  - Odoo/Petshop
  - Portainer

Leitura da evidência:

- a nova solução precisa coexistir com workloads já em produção ou laboratório;
- o banco do n8n é o único PostgreSQL explicitamente recomendado como base reutilizável;
- os bancos do Chatwoot/Fazer.AI foram explicitamente excluídos para o SDR.

### Estado do n8n

- Versão `2.34.5`.
- Banco PostgreSQL existente e saudável.
- `0 workflows`, `0 credenciais`, `0 execuções`, `0 community packages`.
- Compose em `/home/dominique/docker/n8n/compose.yaml`.
- `.env` existe com modo `600`.
- Diagnóstico e personalização desabilitados.
- Runners habilitados.
- `no-new-privileges`.
- Timezone `America/Sao_Paulo`.

Conclusão factual já presente na entrada:

- o n8n pode ser usado como base limpa;
- a preferência é criar banco separado `dwlabs_sdr` no mesmo cluster PostgreSQL;
- Google Sheets não deve ser fonte principal.

### Estado do OpenClaw

- Runtime `2026.7.1`.
- Config em `/home/dominique/docker/openclaw/data/config/openclaw.json`.
- Compose em `/home/dominique/docker/openclaw/`.
- Gateway publicado por Tailscale Serve no host.
- Plugins habilitados: WhatsApp, OpenAI, Codex, memory-core, browser, document-extract.
- Canal WhatsApp Business `default`:
  - instalado
  - configurado
  - vinculado
  - `running/connected/healthy`
  - `dmPolicy=allowlist`
  - somente o número do proprietário permitido
  - grupos desabilitados
  - `selfChatMode=false`
- Agente existente `main`, identidade `DW`, com papel privado de engenharia/operações.
- Ferramentas atuais do agente privado:
  - `browser`
  - `web_fetch`
  - `memory_search`
  - `memory_get`
  - `message`
- Restrições atuais:
  - `fs.workspaceOnly=true`
  - bash desligado
  - config desligado
  - mcp desligado
  - plugins desligados
  - debug desligado
- Nenhum MCP, webhook ou cron configurado.

Leitura da evidência:

- já existe uma postura de endurecimento que deve ser preservada;
- o agente privado não deve ser reaproveitado;
- o agente comercial precisará nascer com isolamento explícito, sem expandir permissões globais.

### Modelo e autenticação

- Modelo atual: `openai/gpt-5.6-sol` via OAuth/Codex.
- Catálogo autenticado inclui `gpt-5.4-mini/nano`, `gpt-5.5`, `gpt-5.6` e variantes.
- OAuth utilizável no momento da coleta, com expiração reportada em cerca de 22 horas.

Leitura da evidência:

- existe risco operacional de renovação manual do acesso do provedor/modelo;
- esse ponto deve virar gate operacional antes da ativação pública.

### Segurança e validação já executadas

- `openclaw config validate` passou.
- `openclaw security audit` sem crítico.
- deep audit com um aviso de probe por falta do escopo `operator.read`, não vulnerabilidade confirmada.

Leitura da evidência:

- não há sinal factual de bloqueador de segurança crítico no estado atual;
- ainda assim, a trilha de implantação precisa manter o mesmo nível de endurecimento.

### Áudio

- suporte de áudio não configurado;
- Whisper local/API e Deepgram aparecem como não preparados/desabilitados.

Leitura da evidência:

- áudio deve entrar como integração opcional e fail-safe, não como premissa do primeiro corte funcional.

### Repositórios e ferramentas

- Fonte do OpenClaw em `/home/dominique/docker/openclaw`, checkout detached na tag `v2026.7.1-2`.
- Não modificar o core.
- Dados/config/backup aparecem `untracked` e devem ficar fora de versionamento.
- Diretório do n8n não é Git.
- Claude Code não está instalado no servidor.
- No Mac, Claude Code `2.1.223` existe, mas não está autenticado.
- Codex CLI `0.146.0` no Mac, autenticado via ChatGPT.
- Hermes remoto `0.20.0`.

Leitura da evidência:

- a implementação deve versionar artefatos do SDR fora do core do OpenClaw;
- não há base factual para planejar Claude Code no servidor;
- Codex pode ser usado como executor temporário, mas isso não muda o isolamento do agente comercial.

### Backups

- Backup pré-implementação: `/home/dominique/backups/dwlabs-sdr/20260821-171043`.
- Conteúdo informado:
  - archive OpenClaw verificado
  - dump custom-format do PostgreSQL n8n validado com `pg_restore -l`
  - composes
  - `SHA256SUMS`
  - permissões restritas

Leitura da evidência:

- já existe baseline de rollback antes de qualquer mudança;
- o plano pode assumir um ponto de restauração conhecido.

### Templates pesquisados

Referências listadas:

- `n8n 4508`
- `n8n 4083`
- `n8n 5387/3131/8635`
- `n8n 15751/6212`
- `n8n 8773`

Conclusão factual já presente na entrada:

- usar apenas como referência;
- implementar subworkflows determinísticos próprios;
- usar PostgreSQL principal;
- manter integração OpenClaw estritamente allowlisted.

## Restrições obrigatórias derivadas das evidências

- Não quebrar Chatwoot/Fazer.AI, Odoo/Petshop, Portainer, Hermes ou `main/DW`.
- Não reutilizar o agente privado `main`.
- Não acoplar o novo SDR aos bancos do laboratório Fazer.AI/Chatwoot.
- Não transformar Google Sheets em fonte principal.
- Não relaxar permissões globais do OpenClaw por causa do agente comercial.
- Não retirar o WhatsApp do modo `allowlist` antes da fase final de ativação.

## Lacunas ainda não resolvidas por esta Fase 0

Estas lacunas não são fatos ausentes do servidor; são pontos que o `AUDIT_INPUT.md` não fecha sozinho:

- contrato exato das ferramentas tipadas entre OpenClaw e n8n;
- desenho final das migrations e constraints;
- estratégia exata de importação/publicação dos workflows no n8n;
- modelo de autenticação entre agente e workflows;
- decisão final entre FTS e busca vetorial;
- estratégia operacional de Calendar/Meet/Sheets sem OAuth disponível;
- plano de testes automatizados e rollback por gate.

## Conclusão da Fase 0

Com base apenas em `AUDIT_INPUT.md`, o cenário é favorável para implantação incremental de um SDR comercial, desde que:

- o PostgreSQL do n8n seja reutilizado com banco lógico separado;
- o OpenClaw receba um agente comercial distinto do privado;
- o n8n permaneça o executor determinístico de dados e automações;
- o WhatsApp continue em `allowlist` até o último gate;
- integrações ausentes, principalmente áudio e Google OAuth, sejam tratadas como opcionais e fail-safe na primeira entrega.
