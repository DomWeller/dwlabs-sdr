import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { hostname } from "node:os";
import { setTimeout as delay } from "node:timers/promises";
import { Pool } from "pg";

const pool = new Pool({ connectionString: required("DATABASE_URL", 10), max: 2 });
const pilotPhone = digits(required("SDR_OWNER_ALLOWLIST", 10));
const workerId = `dispatcher:${hostname()}`;
const pollMs = Number(process.env.DISPATCHER_POLL_MS ?? 10_000);
const healthPort = Number(process.env.DISPATCHER_HEALTH_PORT ?? 3001);
const health = { lastTickAt: null, lastErrorCode: null };

function required(name, minLength) {
  const value = process.env[name];
  if (!value || value.length < minLength || value.includes("PLACEHOLDER")) throw new Error(`${name} ausente ou invalido`);
  return value;
}
function digits(value) { return String(value).replace(/\D+/g, ""); }

async function sendWhatsApp(target, message) {
  if (digits(target) !== pilotPhone) throw new Error("TARGET_NOT_ALLOWLISTED");
  return new Promise((resolve, reject) => {
    const child = spawn("openclaw", ["message", "send", "--channel", "whatsapp", "--account", "default", "--target", `+${digits(target)}`, "--message", message, "--json"], { env: process.env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = ""; let stderr = "";
    child.stdout.on("data", (chunk) => { if (stdout.length < 16_384) stdout += chunk; });
    child.stderr.on("data", (chunk) => { if (stderr.length < 4096) stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) return reject(new Error(`OPENCLAW_SEND_${code}:${stderr.slice(0, 80)}`));
      try { resolve(JSON.parse(stdout)); } catch { resolve({ ok: true }); }
    });
  });
}

async function tick() {
  const flags = await pool.query("SELECT flag_name,enabled FROM ops.runtime_flags WHERE flag_name IN ('automation_paused','dispatcher_enabled')");
  const state = Object.fromEntries(flags.rows.map((row) => [row.flag_name, row.enabled]));
  if (state.automation_paused || !state.dispatcher_enabled) return;
  await pool.query("SELECT ops.enqueue_due_followups($1,TRUE)", [pilotPhone]);
  const claim = await pool.query("SELECT * FROM ops.claim_delivery($1)", [workerId]);
  if (!claim.rowCount) return;
  const delivery = claim.rows[0];
  const sendable = await pool.query("SELECT ops.delivery_is_sendable($1) AS allowed", [delivery.delivery_id]);
  if (!sendable.rows[0]?.allowed) {
    console.log(JSON.stringify({ event: "delivery_cancelled_before_send", delivery_id: delivery.delivery_id }));
    return;
  }
  try {
    const result = await sendWhatsApp(delivery.target_phone, delivery.message_text);
    const externalId = String(result?.messageId ?? result?.id ?? "accepted").slice(0, 200);
    await pool.query("SELECT ops.complete_delivery($1,$2)", [delivery.delivery_id, externalId]);
    console.log(JSON.stringify({ event: "delivery_sent", delivery_id: delivery.delivery_id }));
  } catch (error) {
    const code = String(error?.message ?? "DELIVERY_FAILED").split(":")[0].slice(0, 80);
    await pool.query("SELECT ops.fail_delivery($1,$2)", [delivery.delivery_id, code]);
    console.error(JSON.stringify({ event: "delivery_failed", delivery_id: delivery.delivery_id, code }));
  }
}

process.on("SIGTERM", async () => { await pool.end(); process.exit(0); });
createServer((req, res) => {
  if (req.url !== "/healthz") { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
  res.end(JSON.stringify({ ok: true, ...health }));
}).listen(healthPort, "127.0.0.1");
for (;;) {
  try {
    await tick();
    health.lastTickAt = new Date().toISOString();
    health.lastErrorCode = null;
  } catch (error) {
    health.lastErrorCode = String(error?.message ?? "UNKNOWN").slice(0, 80);
    console.error(JSON.stringify({ event: "dispatcher_error", code: health.lastErrorCode }));
  }
  await delay(pollMs);
}
