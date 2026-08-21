import path from "node:path";
import { commercialAgentPrompt, commercialAgentWorkspace } from "../config/agent.js";
import { toolDefinitions } from "../contracts/tool-definitions.js";
import { writeJsonFile, writeTextFile } from "../lib/files.js";

export function generateAgentArtifacts(rootDir: string): void {
  const agentRoot = path.join(rootDir, "openclaw-agent");

  writeTextFile(path.join(agentRoot, "comercial.prompt.md"), commercialAgentPrompt);
  writeTextFile(path.join(agentRoot, "comercial.workspace.md"), commercialAgentWorkspace);
  writeJsonFile(path.join(agentRoot, "comercial.agent.config.json"), {
    agentId: "comercial",
    identity: "DWLabs Comercial",
    channelBindingMode: "owner-only",
    allowPublicActivation: false,
    publicActivationFlag: "SDR_PUBLIC_FLAG",
    tools: {
      allow: toolDefinitions.map((tool) => tool.toolName),
      deny: [
        "gateway",
        "cron",
        "sessions_spawn",
        "sessions_send",
        "shell",
        "filesystem",
        "config",
        "plugins_admin",
        "debug",
        "http_generic"
      ]
    },
    memory: {
      mode: "isolated",
      retention: "short"
    },
    safety: {
      ownerAllowlistRequired: true,
      requiresManualPublicFlag: true
    }
  });
}
