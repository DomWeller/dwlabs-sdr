# Testing

## Cobertura local automatizada

```text
2 arquivos de teste, 31 testes, 0 falhas
```

- 20 cenarios comerciais obrigatorios em `tests/scenarios.test.ts`
- 11 salvaguardas de artefatos e configuracao em `tests/artifacts.test.ts`
  (inclui comparar o SHA-256 puro em JavaScript gerado nos Code nodes com o SHA-256 oficial
  do Node)
- validacao estrutural em `src/cli/validate-artifacts.ts`
- sintaxe shell em `scripts/lint-shell.sh`
- varredura de segredos em `scripts/scan-secrets.sh`

## Execucao

```bash
npm run build
npm run validate
npm run test
npm run scan:secrets
```

## Healthcheck de ambiente

```bash
bash scripts/healthcheck.sh
```

Ele valida containers, banco, catalogo, OpenClaw, plugin e agente, exige 33 workflows
presentes e 31 ativos, e checa os dois comportamentos do webhook:

- chamada sem autenticacao deve retornar HTTP `403` (comportamento nativo do Header Auth)
- chamada autenticada, com `x-agent-id: comercial` e `x-channel: test`, deve retornar JSON valido

Saida esperada no fim: `Healthcheck local/remoto concluido.` com `exit=0`.

## Teste manual ponta a ponta ja executado

Caminho de leitura completo, sem entrega a canal externo:

```text
OpenClaw comercial -> plugin dwlabs-sdr-tools -> webhook n8n -> funcao SQL -> 13 servicos
```

```bash
docker exec openclaw-openclaw-gateway-1 \
  openclaw agent --agent comercial \
  --session-key agent:comercial:codex-healthcheck-5 \
  --message 'Teste interno: use a ferramenta buscar_servicos ...' \
  --thinking low --timeout 180 --json
```

Resultado observado: resposta `13`, 1 tool call (`buscar_servicos`), 0 falhas.

## Suite de integracao real

```bash
bash scripts/integration-test.sh
```

A suite usa `channel=test`, IDs unicos e dois contatos sinteticos. Ela nunca imprime o Bearer
token, valida HTTP e o envelope `ok/data/error`, exercita exatamente as 22 ferramentas, confere
o banco e a trilha de auditoria, testa replay e colisao de idempotencia e bloqueia consultas
cruzadas entre os dois contatos. Um `trap` remove apenas os dados marcados pelo `run_id`, mesmo
quando o teste falha.

Resultado remoto confirmado em 2026-08-23:

```text
tools_exercised=22
services_found=13
idempotency_replay=true
idempotency_collision_blocked=true
cross_contact_reads_blocked=2
external_integrations_remained_disabled=7
cleanup=ok
```

Os 7 casos de integracao externa validam o fail-safe desativado. Os caminhos de sucesso de
Calendar, notificacao, audio e Sheets continuam pendentes de credenciais e autorizacao.

## Testes reais de politica do agente

- prompt injection: recusado, 0 tool calls e nenhum padrao de segredo na resposta
- agente `main`: 0 ferramentas SDR visiveis e 0 chamadas SDR
