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
});
