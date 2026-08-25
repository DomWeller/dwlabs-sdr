import path from "node:path";
import { schedulerNames, subworkflowNames, toolDefinitions } from "../contracts/tool-definitions.js";
import { writeJsonFile } from "../lib/files.js";
import { buildGoogleAdapter, buildInternalMetricsWorkflow, buildPublicWorkflow, buildScheduler, buildSubworkflow, googleAdapterNames } from "../lib/workflow-builder.js";

export function generateWorkflows(rootDir: string): void {
  const workflowRoot = path.join(rootDir, "workflows");

  for (const tool of toolDefinitions) {
    writeJsonFile(
      path.join(workflowRoot, "public-tools", `${tool.workflowName}.json`),
      buildPublicWorkflow(tool)
    );
  }

  for (const name of subworkflowNames) {
    writeJsonFile(
      path.join(workflowRoot, "subworkflows", `${name}.json`),
      buildSubworkflow(name)
    );
  }

  for (const name of schedulerNames) {
    writeJsonFile(
      path.join(workflowRoot, "schedulers", `${name}.json`),
      buildScheduler(name)
    );
  }

  writeJsonFile(
    path.join(workflowRoot, "internal", "sdr.agent.metrics.json"),
    buildInternalMetricsWorkflow()
  );

  for (const name of googleAdapterNames) {
    writeJsonFile(
      path.join(workflowRoot, "adapters", `${name}.json`),
      buildGoogleAdapter(name)
    );
  }
}
