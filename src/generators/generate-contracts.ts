import path from "node:path";
import { buildToolInputSchema, buildToolOutputSchema, toolDefinitions } from "../contracts/tool-definitions.js";
import { writeJsonFile } from "../lib/files.js";

export function generateContracts(rootDir: string): void {
  const contractsDir = path.join(rootDir, "contracts", "tools");

  for (const tool of toolDefinitions) {
    writeJsonFile(path.join(contractsDir, `${tool.toolName}.input.schema.json`), buildToolInputSchema(tool.payloadSchema));
    writeJsonFile(path.join(contractsDir, `${tool.toolName}.output.schema.json`), buildToolOutputSchema(tool.dataSchema));
  }

  writeJsonFile(
    path.join(rootDir, "contracts", "tool-catalog.json"),
    toolDefinitions.map((tool) => ({
      tool_name: tool.toolName,
      workflow_name: tool.workflowName,
      endpoint_path: tool.endpointPath,
      sql_function: tool.sqlFunction,
      description: tool.description
    }))
  );
}
