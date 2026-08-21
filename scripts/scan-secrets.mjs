import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

const rootDir = path.resolve(process.argv[2] ?? process.cwd());
const ignoreDirs = new Set([".git", "node_modules", "dist"]);
const ignoreFiles = new Set(["package-lock.json"]);
const secretPattern = /(sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----)/;

function* walk(currentDir) {
  for (const entry of readdirSync(currentDir, { withFileTypes: true })) {
    if (ignoreDirs.has(entry.name)) {
      continue;
    }

    const fullPath = path.join(currentDir, entry.name);
    if (entry.isDirectory()) {
      yield* walk(fullPath);
      continue;
    }

    if (!entry.isFile() || ignoreFiles.has(entry.name)) {
      continue;
    }

    yield fullPath;
  }
}

const findings = [];

for (const filePath of walk(rootDir)) {
  let stat;
  try {
    stat = statSync(filePath);
  } catch {
    continue;
  }

  if (stat.size > 2 * 1024 * 1024) {
    continue;
  }

  const contents = readFileSync(filePath, "utf8");
  const lines = contents.split(/\r?\n/u);
  lines.forEach((line, index) => {
    if (secretPattern.test(line)) {
      findings.push(`${path.relative(rootDir, filePath)}:${index + 1}`);
    }
  });
}

if (findings.length > 0) {
  console.error("Padrao de segredo encontrado:");
  findings.forEach((finding) => console.error(finding));
  process.exit(1);
}

console.log("Nenhum padrao de segredo encontrado.");
