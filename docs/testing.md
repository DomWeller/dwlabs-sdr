# Testing

## Cobertura local automatizada

```text
2 arquivos de teste, 30 testes, 0 falhas
```

- 20 cenarios comerciais obrigatorios em `tests/scenarios.test.ts`
- 10 salvaguardas de artefatos e configuracao em `tests/artifacts.test.ts`
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

## Lacuna conhecida

Os 30 testes sao majoritariamente unitarios e estruturais. **Ainda nao existe suite
automatizada de integracao real cobrindo as 22 ferramentas.** Quando for criada, ela deve:

- usar `channel=test` e IDs unicos
- nunca imprimir o Bearer token
- validar status HTTP e o envelope `ok/data/error`
- executar leituras antes das mutacoes
- marcar claramente os dados de teste e remove-los so com alvo exato e verificacao previa
- conferir banco e trilha de auditoria depois de cada mutacao
