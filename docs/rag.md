# RAG

A primeira entrega usa FTS nativo do PostgreSQL, sem `pgvector`.

## Motivo

- menor custo operacional
- menos memoria no host
- mais previsibilidade para uma base inicial curta

## Estrutura

- `rag.knowledge_documents`
- `rag.knowledge_chunks`
- busca via `plainto_tsquery('portuguese', query)`

O agente recebe apenas `title`, `snippet`, `source` e `score`.
