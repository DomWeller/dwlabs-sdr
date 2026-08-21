import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentFile = fileURLToPath(import.meta.url);
const rootDir = path.resolve(path.dirname(currentFile), "..", "..");

const requiredDocs = [
  "docs/architecture.md",
  "docs/openclaw-agent.md",
  "docs/n8n-workflows.md",
  "docs/database.md",
  "docs/integrations.md",
  "docs/google-calendar.md",
  "docs/google-sheets.md",
  "docs/portfolio.md",
  "docs/rag.md",
  "docs/followups.md",
  "docs/security.md",
  "docs/testing.md",
  "docs/operations.md",
  "docs/troubleshooting.md"
];

function assertJsonDirectory(relativeDir: string): void {
  const absoluteDir = path.join(rootDir, relativeDir);
  const files = readdirSync(absoluteDir);

  if (files.length === 0) {
    throw new Error(`Diretorio vazio: ${relativeDir}`);
  }

  for (const file of files) {
    const contents = readFileSync(path.join(absoluteDir, file), "utf8");
    JSON.parse(contents);
  }
}

for (const relativePath of requiredDocs) {
  readFileSync(path.join(rootDir, relativePath), "utf8");
}

assertJsonDirectory("contracts/tools");
assertJsonDirectory("workflows/public-tools");
assertJsonDirectory("workflows/subworkflows");
assertJsonDirectory("workflows/schedulers");

const envExample = readFileSync(path.join(rootDir, ".env.example"), "utf8");
if (!envExample.includes("__PLACEHOLDER_ONLY__")) {
  throw new Error(".env.example deve usar placeholders sem segredos reais");
}

const agentConfig = JSON.parse(readFileSync(path.join(rootDir, "openclaw-agent/comercial.agent.config.json"), "utf8")) as {
  safety?: { ownerAllowlistRequired?: boolean };
};

if (!agentConfig.safety?.ownerAllowlistRequired) {
  throw new Error("Config do agente deve exigir allowlist do owner");
}
