# n8n Workflows

Os workflows foram gerados a partir de `src/generators/generate-workflows.ts` e saem desativados por padrao.

## Pastas

- `workflows/public-tools/`: 22 ferramentas publicas
- `workflows/subworkflows/`: utilitarios reutilizaveis
- `workflows/schedulers/`: follow-up, sync de Sheets e selfcheck

## Importacao

```bash
bash scripts/import-workflows.sh
```

## Credenciais placeholder

- PostgreSQL: `DWLABS_SDR_POSTGRES`
- Google Calendar: `DWLABS_SDR_GOOGLE_CALENDAR`
- Google Sheets: `DWLABS_SDR_GOOGLE_SHEETS`

Nenhum export contem token real.
