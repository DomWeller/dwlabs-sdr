# Google Sheets

Sheets e painel operacional, nunca a fonte principal de verdade.

## Estado atual

- exportacao preparada para `ops.sheet_sync_outbox`
- sincronizacao real fica desativada enquanto `google_sheets_enabled=false`
- workflow publico: `workflows/public-tools/sdr.sincronizar_sheets.json`

## Quando habilitar

1. configurar credencial Google Sheets no n8n
2. trocar a flag de runtime no banco
3. validar sync owner-only antes de qualquer piloto externo
