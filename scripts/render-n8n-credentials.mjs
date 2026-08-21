import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

const targetDir = path.resolve(process.argv[2] ?? "tmp/n8n-credentials");
const sharedToken = process.env.N8N_SDR_SHARED_TOKEN;
const headerAuthId = process.env.N8N_SDR_HEADER_AUTH_ID ?? "DWLABS_SDR_HEADER_AUTH";
const headerAuthName = process.env.N8N_SDR_HEADER_AUTH_NAME ?? "DWLabs SDR Header Auth";
const pgCredentialId = process.env.N8N_WORKFLOW_PG_CREDENTIAL_ID ?? "DWLABS_SDR_POSTGRES_ID";
const pgCredentialName = process.env.N8N_WORKFLOW_PG_CREDENTIAL_NAME ?? "DWLABS_SDR_POSTGRES";
const postgresHost = process.env.POSTGRES_HOST;
const postgresPort = Number(process.env.POSTGRES_PORT ?? "5432");
const postgresDatabase = process.env.POSTGRES_DB;
const postgresUser = process.env.POSTGRES_USER;
const postgresPassword = process.env.POSTGRES_PASSWORD;

const required = [
  ["N8N_SDR_SHARED_TOKEN", sharedToken],
  ["POSTGRES_HOST", postgresHost],
  ["POSTGRES_DB", postgresDatabase],
  ["POSTGRES_USER", postgresUser],
  ["POSTGRES_PASSWORD", postgresPassword]
];

for (const [name, value] of required) {
  if (!value || value === "__PLACEHOLDER_ONLY__") {
    throw new Error(`Variavel obrigatoria ausente: ${name}`);
  }
}

mkdirSync(targetDir, { recursive: true });

const credentials = [
  {
    id: headerAuthId,
    name: headerAuthName,
    type: "httpHeaderAuth",
    data: {
      name: "Authorization",
      value: `Bearer ${sharedToken}`
    }
  },
  {
    id: pgCredentialId,
    name: pgCredentialName,
    type: "postgres",
    data: {
      host: postgresHost,
      port: postgresPort,
      database: postgresDatabase,
      user: postgresUser,
      password: postgresPassword,
      ssl: "disable"
    }
  }
];

for (const credential of credentials) {
  writeFileSync(
    path.join(targetDir, `${credential.id}.json`),
    `${JSON.stringify(credential, null, 2)}\n`,
    "utf8"
  );
}

console.log(targetDir);
