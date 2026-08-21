# Testing

## Cobertura local automatizada

- 20 cenarios obrigatorios em `tests/scenarios.test.ts`
- salvaguardas de artefatos em `tests/artifacts.test.ts`
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
