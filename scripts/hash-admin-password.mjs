import { randomBytes, scryptSync } from "node:crypto";
const password = process.argv[2];
if (!password || password.length < 14) {
  console.error("Uso: npm run admin:hash-password -- '<senha com pelo menos 14 caracteres>'");
  process.exit(1);
}
const salt = randomBytes(16).toString("hex");
process.stdout.write(`${salt}:${scryptSync(password, salt, 32).toString("hex")}\n`);

