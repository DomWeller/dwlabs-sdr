# Security

## Controles implementados

- `.env.example` com placeholders apenas
- `.gitignore` forte
- plugin OpenClaw com allowlist de endpoints
- `Webhook Header Auth` nativo do n8n com credencial `httpHeaderAuth` fixa/importavel
- token compartilhado de 256 bits apenas em rede privada/Tailscale
- sem shell, filesystem generico, admin, HTTP generico ou dados de terceiros para o agente comercial
- logs redigidos via `ops.redact_text`
- audit trail em `audit.redacted_event_log`

## Auditoria de seguranca do OpenClaw

```bash
docker exec openclaw-openclaw-gateway-1 openclaw security audit --deep
```

Resultado atual conhecido: `1 critical`, `1 warn`, `1 info`.

### critical `plugins.code_safety`

O auditor classifica `dwlabs-sdr-tools` como possivel `env-harvesting` porque o mesmo codigo
le `process.env.SDR_N8N_TOKEN` e faz uma chamada de rede com `fetch`.

Revisao do codigo: le somente `SDR_N8N_TOKEN`, usa o valor apenas como Bearer token, chama
somente a `baseUrl` configurada e paths da allowlist, nao aceita endpoint arbitrario do usuario
final e nao registra o token em log.

O alerta continuara aparecendo enquanto o segredo for lido direto do ambiente no mesmo codigo
que faz a chamada de rede. Melhoria pendente: migrar para o mecanismo oficial de
`SecretRef`/secret store do OpenClaw `2026.7.1-2`, validar a forma suportada nessa versao e
remover a leitura direta de `process.env`. Nao improvisar sem testar plugin e deploy.

### warn `gateway.probe_failed`

```text
missing scope: operator.read
```

Aviso preexistente: falta de escopo para a probe profunda, nao vulnerabilidade confirmada.
Verificar com `openclaw status --all`.

## Ativacao publica

Nao executar agora. A mudanca para publico exige flag manual `SDR_PUBLIC_FLAG=true` e gate separado.
