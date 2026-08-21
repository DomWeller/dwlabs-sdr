import path from "node:path";
import { fileURLToPath } from "node:url";
import { generateAgentArtifacts } from "./generate-agent.js";
import { generateContracts } from "./generate-contracts.js";
import { generateWorkflows } from "./generate-workflows.js";

const currentFile = fileURLToPath(import.meta.url);
const rootDir = path.resolve(path.dirname(currentFile), "..", "..");

generateContracts(rootDir);
generateWorkflows(rootDir);
generateAgentArtifacts(rootDir);
