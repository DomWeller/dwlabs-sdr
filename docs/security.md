# Security

## Controles implementados

- `.env.example` com placeholders apenas
- `.gitignore` forte
- plugin OpenClaw com allowlist de endpoints
- `Webhook Header Auth` nativo do n8n com credencial `httpHeaderAuth` fixa/importavel
- token compartilhado de 256 bits apenas em rede privada/Tailscale
- sem shell, filesystem generico, admin, HTTP generico ou dados de terceiros para o agente comercial
- `ops.is_lead_in_actor_scope` exige correspondencia com o lead, conversa, telefone ou email do ator
- logs redigidos via `ops.redact_text`
- audit trail em `audit.redacted_event_log`
- limite local no plugin e janela atomica disponivel em `ops.check_rate_limit`
- roles separadas para n8n, painel e dispatcher
- painel em loopback/Tailscale com scrypt, cookie seguro e CSRF
- dispatcher sem shell, com destino owner-only e outbox idempotente
- `allowConversationAccess` habilitado somente no plugin SDR para o hook `agent_end`; o handler
  ignora mensagens e persiste apenas metadados sanitizados de duracao/resultado

## Auditoria de seguranca do OpenClaw

```bash
docker exec openclaw-openclaw-gateway-1 openclaw security audit --deep
```

Resultado confirmado depois da migracao para SecretRef: `0 critical`, `1 warn`, `1 info`.

### critical `plugins.code_safety` — resolvido

O auditor classificava `dwlabs-sdr-tools` como possivel `env-harvesting` porque o mesmo codigo
lia `process.env.SDR_N8N_TOKEN` e fazia uma chamada de rede com `fetch`.

O plugin chamava somente a `baseUrl` configurada e paths da allowlist, nao aceitava endpoint
arbitrario do usuario final e nao registrava o token em log, mas a leitura direta do ambiente
ainda acionava a heuristica.

O plugin foi migrado para um campo `bearerToken` declarado em
`configContracts.secretInputs`. A configuracao persiste apenas a referencia estruturada ao
provedor de ambiente (`SDR_N8N_TOKEN`); o runtime entrega o valor resolvido ao plugin. O codigo
do plugin nao le mais `process.env`.

O deploy de 2026-08-23 confirmou que o alerta `env-harvesting` desapareceu. O healthcheck
remoto terminou com exit `0` e um turno interno do agente chamou `buscar_servicos`, recebeu
13 servicos, fez 1 tool call e teve 0 falhas.

`openclaw secrets audit --check` tambem confirmou `plaintext=0`, `unresolved=0` e
`shadowed=0` para os campos suportados. Ele ainda retorna `legacy=1` por uma credencial OAuth
do agente privado `main` armazenada no SQLite; esse residuo e preexistente, fica fora da
migracao estatica de SecretRef e nao pertence ao plugin comercial.

### warn `gateway.probe_failed`

```text
missing scope: operator.read
```

Aviso preexistente: falta de escopo para a probe profunda, nao vulnerabilidade confirmada.
Verificar com `openclaw status --all`.

## Isolamento e redacao validados

- `buscar_lead` e `buscar_cliente` recusaram duas consultas cruzadas com
  `LEAD_SCOPE_FORBIDDEN` e `CUSTOMER_SCOPE_FORBIDDEN`
- mutacoes vinculadas a lead, reuniao, follow-up e handoff usam a mesma verificacao de escopo
- `ops.redact_text` foi corrigida para a sintaxe POSIX do PostgreSQL e confirmou redacao de
  email e telefone em um teste remoto
- um turno real de prompt injection foi recusado sem tool call e sem padrao de segredo
- a allowlist oficial por agente foi fixada em `skills=[]`; o prompt comercial nao herda skills globais

## Ativacao publica

Nao executar agora. A mudanca para publico exige flag manual `SDR_PUBLIC_FLAG=true` e gate separado.

O piloto interno continua com `SDR_PUBLIC_FLAG=false`. O script de inicio exige allowlist com um
unico numero, grupos desativados, backup e healthcheck; o script de parada desliga filas antes de
remover o binding do agente comercial.
