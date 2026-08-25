# Testing

## Cobertura local automatizada

```text
3 arquivos de teste, 45 testes, 0 falhas
```

- 20 cenarios comerciais obrigatorios em `tests/scenarios.test.ts`
- 21 salvaguardas de artefatos e configuracao em `tests/artifacts.test.ts`
  (inclui comparar o SHA-256 puro em JavaScript gerado nos Code nodes com o SHA-256 oficial
  do Node)
- validacao estrutural em `src/cli/validate-artifacts.ts`
- 4 testes do bloqueio de handoff, recuperacao de contexto e telemetria em
  `tests/handoff-guard.test.ts`
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

Ele valida containers, banco, catalogo, OpenClaw, plugin e agente, exige 43 workflows
presentes e 32 ativos, e checa os dois comportamentos do webhook:

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

Em 2026-08-25, um novo turno interno apos o deploy confirmou a telemetria de latencia percebida:
`agent_turn_delta=1`, resultado `completed` e duracao `20810 ms`. O harness Codex/OpenClaw usado
nao emitiu `model_call_ended`; por isso o painel usa `agent_turn` como fallback honesto para o
turno completo, mantendo `model_call` disponivel quando o runtime fornecer o evento sanitizado.

## Suite de integracao real

```bash
bash scripts/integration-test.sh
```

A suite usa `channel=test`, IDs unicos e dois contatos sinteticos. Ela nunca imprime o Bearer
token, valida HTTP e o envelope `ok/data/error`, exercita exatamente as 22 ferramentas, confere
o banco e a trilha de auditoria, testa replay e colisao de idempotencia e bloqueia consultas
cruzadas entre os dois contatos. Um `trap` remove apenas os dados marcados pelo `run_id`, mesmo
quando o teste falha.

Resultado remoto reconfirmado em 2026-08-25:

```text
tools_exercised=22
services_found=13
idempotency_replay=true
idempotency_collision_blocked=true
cross_contact_reads_blocked=2
active_handoff_reused=true
external_integrations_remained_disabled=7
```

Os 7 casos de integracao externa validam o fail-safe desativado. Audio e Calendar tambem possuem
fixtures deterministicas em `channel=test`; os caminhos OAuth reais de Calendar, notificacao e
Sheets continuam pendentes de credenciais e autorizacao.

As migrations `001..007` foram aplicadas em banco temporario. A `006` foi reaplicada, revertida e
aplicada novamente, confirmando score padrao `23` e 21 regras. A `007` foi exercitada com enqueue,
claim `SKIP LOCKED`, falha/retry, conclusao Calendar/Meet, claim Sheets, preservacao da configuracao
OAuth num novo seed, cache real com busy slot excluido, rejeicao de cache vencido e rollback funcional.
Antes da ativacao OAuth real, ainda e obrigatorio testar
os nodes Google com dados sinteticos e remover os artefatos externos criados.

## Regressao do relatorio de WhatsApp de 2026-08-25

- fechamento: catalogo aceita valor/faixa e `commercial_url`; sem ambos, o agente cria resumo e handoff
- contexto: `before_prompt_build` recupera o CRM minimizado do proprio contato a cada turno
- handoff: `inbound_claim` usa o canal real do evento e silencia `open`/`acknowledged`
- identidade: prompt proibe apresentar a DWLabs como plataforma externa
- latencia: ferramentas e chamadas do modelo geram metricas sem conteudo da conversa

## Testes reais de politica do agente

- prompt injection: recusado, 0 tool calls e nenhum padrao de segredo na resposta
- agente `main`: 0 ferramentas SDR visiveis e 0 chamadas SDR
