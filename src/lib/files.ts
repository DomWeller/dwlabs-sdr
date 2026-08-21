import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

export function ensureDir(dirPath: string): void {
  mkdirSync(dirPath, { recursive: true });
}

export function writeJsonFile(filePath: string, value: unknown): void {
  ensureDir(path.dirname(filePath));
  writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", "utf8");
}

export function writeTextFile(filePath: string, value: string): void {
  ensureDir(path.dirname(filePath));
  writeFileSync(filePath, value.endsWith("\n") ? value : value + "\n", "utf8");
}
