import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
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
    ) as {
      nodes: Array<{
        name: string;
        parameters: Record<string, unknown>;
        credentials?: Record<string, { id: string; name: string }>;
      }>;
    };

    const webhook = workflow.nodes.find((node) => node.name === "Receive Request");
    const postgres = workflow.nodes.find((node) => node.name === "Run SQL Function");

    expect(webhook?.parameters.authentication).toBe("headerAuth");
    expect(webhook?.credentials?.httpHeaderAuth?.id).toBe("DWLABS_SDR_HEADER_AUTH");
    expect(postgres?.credentials?.postgres?.id).toBe("DWLABS_SDR_POSTGRES_ID");
    expect(String(postgres?.parameters.query)).toContain("convert_from(decode($1, 'base64'), 'UTF8')::jsonb");
    expect(JSON.stringify(postgres?.parameters)).toContain("queryReplacement");
    expect(JSON.stringify(workflow)).not.toContain("$env.");
    expect(JSON.stringify(workflow)).not.toContain("crypto.subtle");
    expect(JSON.stringify(workflow)).not.toContain("require('node:crypto')");
    expect(JSON.stringify(workflow)).toContain("const sha256 = (value)");
  });

  it("computes the request SHA-256 without sandbox crypto access", async () => {
    const workflow = JSON.parse(
      readFileSync(path.join(rootDir, "workflows/public-tools/sdr.buscar_servicos.json"), "utf8")
    ) as { nodes: Array<{ name: string; parameters: { jsCode?: string } }> };
    const jsCode = workflow.nodes.find((node) => node.name === "Normalize Envelope")?.parameters.jsCode;
    expect(jsCode).toBeTruthy();

    const body = {
      request_id: "hash-test",
      idempotency_key: "hash-test",
      channel: "test",
      actor: { contact_name: "Dominique" },
      context: { conversation_id: "hash-test" },
      payload: { query: "automacao comercial" }
    };
    const execute = new Function("$json", `return (async () => {${jsCode}})();`) as (
      input: unknown
    ) => Promise<Array<{ json: { request_hash: string } }>>;
    const result = await execute({ headers: { "x-agent-id": "comercial", "x-channel": "test" }, body });
    const expected = createHash("sha256").update(JSON.stringify(body)).digest("hex");

    expect(result[0].json.request_hash).toBe(expected);
  });

  it("removes placeholder subworkflow text and enables explicit disabled codes", () => {
    const subworkflow = readFileSync(path.join(rootDir, "workflows/subworkflows/sdr._validate_request.json"), "utf8");
    const scheduler = readFileSync(path.join(rootDir, "workflows/schedulers/sdr.sheets.sync.scheduler.json"), "utf8");

    expect(subworkflow).not.toContain("Executar regras compartilhadas aqui");
    expect(scheduler).toContain("GOOGLE_SHEETS_DISABLED");
    expect(scheduler).toContain("const enabled = false");
    expect(scheduler).not.toContain("$env.");
  });

  it("ships transactional idempotency metadata and disabled integration codes in SQL", () => {
    const migration = readFileSync(path.join(rootDir, "database/migrations/001_init.up.sql"), "utf8");

    expect(migration).toContain("pg_advisory_xact_lock");
    expect(migration).toContain("IDEMPOTENCY_HASH_MISMATCH");
    expect(migration).toContain("CALENDAR_DISABLED");
    expect(migration).toContain("NOTIFICATION_DISABLED");
    expect(migration).toContain("GOOGLE_SHEETS_DISABLED");
    expect(migration).toContain("[email-redigido]");
    expect(migration).not.toContain("\\b[A-Za-z0-9._%+-]+@");
  });

  it("enforces actor scope and keeps real integration tests self-cleaning", () => {
    const migration = readFileSync(path.join(rootDir, "database/migrations/001_init.up.sql"), "utf8");
    const integrationScript = readFileSync(path.join(rootDir, "scripts/integration-test.sh"), "utf8");
    const remoteTest = readFileSync(path.join(rootDir, "tests/remote-integration.mjs"), "utf8");

    expect(migration).toContain("ops.is_lead_in_actor_scope");
    expect(migration).toContain("LEAD_SCOPE_FORBIDDEN");
    expect(migration).toContain("CUSTOMER_SCOPE_FORBIDDEN");
    expect(integrationScript).toContain("trap cleanup_test_data EXIT INT TERM");
    expect(integrationScript).toContain("DELETE FROM core.contacts");
    expect(integrationScript).toContain("DELETE FROM ops.idempotency_inbox");
    expect(remoteTest).toContain("a suite precisa exercitar exatamente as 22 ferramentas");
    expect(remoteTest).not.toContain("process.env.N8N_SDR_SHARED_TOKEN");
  });

  it("uses portable secret scanning fallback and real import commands", () => {
    const scanScript = readFileSync(path.join(rootDir, "scripts/scan-secrets.sh"), "utf8");
    const importScript = readFileSync(path.join(rootDir, "scripts/import-workflows.sh"), "utf8");

    expect(scanScript).toContain("scan-secrets.mjs");
    expect(scanScript).toContain("python3");
    expect(importScript).toContain("n8n import:credentials");
    expect(importScript).toContain("n8n import:workflow");
    expect(importScript).toContain("active_workflow_json_files");
    expect(importScript).toContain("optional_scheduler_json_files");
  });

  it("configures OpenClaw via CLI instead of writing compose override or config files", () => {
    const installScript = readFileSync(path.join(rootDir, "scripts/install-openclaw.sh"), "utf8");
    const pluginSource = readFileSync(path.join(rootDir, "plugins/dwlabs-sdr-tools/src/index.ts"), "utf8");
    const pluginManifest = JSON.parse(
      readFileSync(path.join(rootDir, "plugins/dwlabs-sdr-tools/openclaw.plugin.json"), "utf8")
    ) as { configContracts?: { secretInputs?: { paths?: Array<{ path: string }> } } };

    expect(installScript).not.toContain("write_compose_override");
    expect(installScript).not.toContain("fs.writeFileSync");
    expect(installScript).toContain("openclaw config set plugins.entries.dwlabs-sdr-tools.config");
    expect(installScript).toContain("openclaw config set tools.allow");
    expect(installScript).toContain("openclaw config set \"agents.list[${main_agent_index}].tools.deny\"");
    expect(installScript).toContain("openclaw config set \"agents.list[${agent_index}].tools.profile\"");
    expect(installScript).toContain("openclaw config set \"agents.list[${agent_index}].tools.allow\"");
    expect(installScript).toContain("codexDynamicToolsLoading");
    expect(installScript).toContain('"source":"env","provider":"default","id":"SDR_N8N_TOKEN"');
    expect(installScript).toContain('"group:web","group:ui","group:messaging","group:memory"');
    expect(installScript).toContain("openclaw agents set-identity");
    expect(pluginSource).not.toContain("process.env.SDR_N8N_TOKEN");
    expect(pluginSource).toContain("config.bearerToken");
    expect(pluginManifest.configContracts?.secretInputs?.paths).toContainEqual({
      path: "bearerToken",
      expected: "string"
    });
  });
});
