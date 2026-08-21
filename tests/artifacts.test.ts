import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const rootDir = path.resolve(process.cwd());

describe("artifact safeguards", () => {
  it("keeps WhatsApp owner-only by default", () => {
    const agentConfig = JSON.parse(readFileSync(path.join(rootDir, "openclaw-agent/comercial.agent.config.json"), "utf8")) as {
      channelBindingMode: string;
      allowPublicActivation: boolean;
    };

    expect(agentConfig.channelBindingMode).toBe("owner-only");
    expect(agentConfig.allowPublicActivation).toBe(false);
  });

  it("does not ship tokens in workflow exports", () => {
    const workflow = readFileSync(path.join(rootDir, "workflows/public-tools/sdr.buscar_servicos.json"), "utf8");
    expect(workflow).not.toMatch(/sk-[A-Za-z0-9]/);
    expect(workflow).not.toContain("Bearer real-");
  });

  it("keeps .env.example placeholder-only", () => {
    const envExample = readFileSync(path.join(rootDir, ".env.example"), "utf8");
    expect(envExample).toContain("__PLACEHOLDER_ONLY__");
  });

  it("documents manual public activation flag separately", () => {
    const operationsDoc = readFileSync(path.join(rootDir, "docs/operations.md"), "utf8");
    expect(operationsDoc).toContain("SDR_PUBLIC_FLAG");
  });

  it("uses native webhook header auth and parametrized postgres query", () => {
    const workflow = JSON.parse(
      readFileSync(path.join(rootDir, "workflows/public-tools/sdr.salvar_lead.json"), "utf8")
    ) as { nodes: Array<{ name: string; parameters: Record<string, unknown> }> };

    const webhook = workflow.nodes.find((node) => node.name === "Receive Request");
    const postgres = workflow.nodes.find((node) => node.name === "Run SQL Function");

    expect(webhook?.parameters.authentication).toBe("headerAuth");
    expect(String(postgres?.parameters.query)).toContain("convert_from(decode($1, 'base64'), 'UTF8')::jsonb");
    expect(JSON.stringify(postgres?.parameters)).toContain("queryReplacement");
  });

  it("removes placeholder subworkflow text and enables explicit disabled codes", () => {
    const subworkflow = readFileSync(path.join(rootDir, "workflows/subworkflows/sdr._validate_request.json"), "utf8");
    const scheduler = readFileSync(path.join(rootDir, "workflows/schedulers/sdr.sheets.sync.scheduler.json"), "utf8");

    expect(subworkflow).not.toContain("Executar regras compartilhadas aqui");
    expect(scheduler).toContain("GOOGLE_SHEETS_DISABLED");
  });

  it("ships transactional idempotency metadata and disabled integration codes in SQL", () => {
    const migration = readFileSync(path.join(rootDir, "database/migrations/001_init.up.sql"), "utf8");

    expect(migration).toContain("pg_advisory_xact_lock");
    expect(migration).toContain("IDEMPOTENCY_HASH_MISMATCH");
    expect(migration).toContain("CALENDAR_DISABLED");
    expect(migration).toContain("NOTIFICATION_DISABLED");
    expect(migration).toContain("GOOGLE_SHEETS_DISABLED");
  });

  it("uses portable secret scanning fallback and real import commands", () => {
    const scanScript = readFileSync(path.join(rootDir, "scripts/scan-secrets.sh"), "utf8");
    const importScript = readFileSync(path.join(rootDir, "scripts/import-workflows.sh"), "utf8");

    expect(scanScript).toContain("scan-secrets.mjs");
    expect(scanScript).toContain("python3");
    expect(importScript).toContain("n8n import:credentials");
    expect(importScript).toContain("n8n import:workflow");
  });
});
