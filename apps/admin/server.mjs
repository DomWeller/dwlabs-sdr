import { createHash, randomBytes, scryptSync, timingSafeEqual } from "node:crypto";
import http from "node:http";
import { Pool } from "pg";

const port = Number(process.env.ADMIN_PORT ?? 3000);
const sessionSecret = required("ADMIN_SESSION_SECRET", 43);
const passwordHash = required("ADMIN_PASSWORD_HASH", 65);
const adminUser = process.env.ADMIN_USER ?? "admin";
const pool = new Pool({ connectionString: required("DATABASE_URL", 10), max: 4 });
const sessions = new Map();
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function required(name, minLength) {
  const value = process.env[name];
  if (!value || value.length < minLength || value.includes("PLACEHOLDER")) throw new Error(`${name} ausente ou invalido`);
  return value;
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

function parseCookies(req) {
  return Object.fromEntries(String(req.headers.cookie ?? "").split(";").filter(Boolean).map((item) => item.trim().split(/=(.*)/s).slice(0, 2)));
}

function sessionFor(req) {
  const raw = parseCookies(req).sdr_admin;
  if (!raw) return null;
  const [id, signature] = raw.split(".");
  const expected = createHash("sha256").update(`${id}:${sessionSecret}`).digest("hex");
  if (!signature || signature.length !== expected.length || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
  const session = sessions.get(id);
  if (!session || session.expiresAt < Date.now()) return null;
  return session;
}

function verifyPassword(password) {
  const [salt, expectedHex] = passwordHash.split(":");
  if (!salt || !expectedHex) return false;
  const actual = scryptSync(password, salt, 32);
  const expected = Buffer.from(expectedHex, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function body(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 32_768) throw new Error("PAYLOAD_TOO_LARGE");
    chunks.push(chunk);
  }
  return new URLSearchParams(Buffer.concat(chunks).toString("utf8"));
}

function page(title, content, csrf = "") {
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escapeHtml(title)} · DWLabs SDR</title><style>
  :root{font-family:system-ui,sans-serif;color:#172033;background:#f5f7fb}body{margin:0}header{background:#111827;color:white;padding:16px 24px}nav a{color:#dbeafe;margin-right:18px}main{max-width:1180px;margin:24px auto;padding:0 18px}.card{background:white;border:1px solid #dbe2ea;border-radius:12px;padding:18px;margin-bottom:16px;overflow:auto}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:10px;border-bottom:1px solid #e5e7eb;vertical-align:top}input,select,textarea,button{padding:9px;border:1px solid #cbd5e1;border-radius:7px}textarea{min-width:220px}button{background:#1d4ed8;color:white;cursor:pointer}.danger{background:#b91c1c}.muted{color:#64748b}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.metric{font-size:28px;font-weight:700}.actions{display:flex;gap:8px;align-items:flex-start;flex-wrap:wrap}</style></head><body><header><strong>DWLabs SDR</strong><nav><a href="/">Visão geral</a><a href="/services">Serviços</a><a href="/leads">Pipeline</a><a href="/handoffs">Atendimento humano</a><a href="/followups">Follow-ups</a><a href="/settings">Controles</a><a href="/logout">Sair</a></nav></header><main>${content}</main></body></html>`;
}

function send(res, status, content, headers = {}) {
  res.writeHead(status, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "content-security-policy": "default-src 'self'; style-src 'unsafe-inline'; frame-ancestors 'none'", ...headers });
  res.end(content);
}

async function audit(client, action, entityType, entityId, diff) {
  await client.query("INSERT INTO audit.admin_change_log(admin_subject,action,entity_type,entity_id,diff_redacted) VALUES($1,$2,$3,$4,$5)", [adminUser, action, entityType, entityId, diff]);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");
    if (url.pathname === "/healthz") {
      await pool.query("SELECT 1");
      res.writeHead(200, { "content-type": "application/json" });
      return res.end('{"ok":true}');
    }
    if (url.pathname === "/login" && req.method === "GET") return send(res, 200, page("Login", '<div class="card"><h1>Entrar</h1><form method="post"><label>Usuário <input name="user" autocomplete="username"></label><label>Senha <input type="password" name="password" autocomplete="current-password"></label><button>Entrar</button></form></div>'));
    if (url.pathname === "/login" && req.method === "POST") {
      const form = await body(req);
      if (form.get("user") !== adminUser || !verifyPassword(String(form.get("password") ?? ""))) return send(res, 403, page("Login", "<div class=\"card\"><h1>Acesso recusado</h1></div>"));
      const id = randomBytes(32).toString("hex");
      const csrf = randomBytes(24).toString("hex");
      sessions.set(id, { csrf, expiresAt: Date.now() + 8 * 60 * 60 * 1000 });
      const signature = createHash("sha256").update(`${id}:${sessionSecret}`).digest("hex");
      return send(res, 303, "", { location: "/", "set-cookie": `sdr_admin=${id}.${signature}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=28800` });
    }
    if (url.pathname === "/logout") return send(res, 303, "", { location: "/login", "set-cookie": "sdr_admin=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0" });

    const session = sessionFor(req);
    if (!session) return send(res, 303, "", { location: "/login" });
    if (req.method === "POST") {
      const form = await body(req);
      if (form.get("csrf") !== session.csrf) return send(res, 403, page("Erro", "<div class=\"card\">CSRF inválido.</div>"));
      if (url.pathname === "/services/toggle") {
        const client = await pool.connect();
        try {
          await client.query("BEGIN");
          const result = await client.query("UPDATE core.services SET active=NOT active WHERE service_id=$1 RETURNING service_id,active", [form.get("id")]);
          if (!result.rowCount) throw new Error("SERVICE_NOT_FOUND");
          await audit(client, "toggle", "service", result.rows[0].service_id, { active: result.rows[0].active });
          await client.query("COMMIT");
        } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
        return send(res, 303, "", { location: "/services" });
      }
      if (url.pathname === "/flags/set") {
        const allowed = new Set(["automation_paused", "followup_enabled", "dispatcher_enabled", "retention_enabled"]);
        const flag = String(form.get("flag"));
        if (!allowed.has(flag)) throw new Error("FLAG_FORBIDDEN");
        const enabled = form.get("enabled") === "true";
        await pool.query("UPDATE ops.runtime_flags SET enabled=$2,updated_at=NOW() WHERE flag_name=$1", [flag, enabled]);
        await pool.query("INSERT INTO audit.admin_change_log(admin_subject,action,entity_type,entity_id,diff_redacted) VALUES($1,'set','runtime_flag',$2,$3)", [adminUser, flag, { enabled }]);
        return send(res, 303, "", { location: "/settings" });
      }
      if (url.pathname === "/handoffs/acknowledge" || url.pathname === "/handoffs/close") {
        const handoffId = String(form.get("id") ?? "");
        if (!uuidPattern.test(handoffId)) throw new Error("HANDOFF_ID_INVALID");
        const client = await pool.connect();
        try {
          await client.query("BEGIN");
          if (url.pathname === "/handoffs/acknowledge") {
            const result = await client.query(
              "UPDATE core.handoffs SET status='acknowledged',assigned_to=$2,acknowledged_at=COALESCE(acknowledged_at,NOW()),updated_at=NOW() WHERE handoff_id=$1 AND status='open' RETURNING handoff_id,status",
              [handoffId, adminUser]
            );
            if (!result.rowCount) throw new Error("HANDOFF_NOT_OPEN");
            await audit(client, "acknowledge", "handoff", handoffId, { status: "acknowledged" });
          } else {
            const resolutionNote = String(form.get("resolution_note") ?? "").trim();
            if (resolutionNote.length > 1000) throw new Error("RESOLUTION_NOTE_TOO_LONG");
            const result = await client.query(
              "UPDATE core.handoffs SET status='closed',assigned_to=COALESCE(assigned_to,$2),acknowledged_at=COALESCE(acknowledged_at,NOW()),closed_at=NOW(),resolution_note=NULLIF($3,''),updated_at=NOW() WHERE handoff_id=$1 AND status IN ('open','acknowledged') RETURNING handoff_id,status",
              [handoffId, adminUser, resolutionNote]
            );
            if (!result.rowCount) throw new Error("HANDOFF_NOT_ACTIVE");
            await audit(client, "close", "handoff", handoffId, { status: "closed", resolution_note_provided: Boolean(resolutionNote) });
          }
          await client.query("COMMIT");
        } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
        return send(res, 303, "", { location: "/handoffs" });
      }
    }

    if (url.pathname === "/") {
      const { rows } = await pool.query("SELECT (SELECT count(*) FROM core.leads) leads,(SELECT count(*) FROM core.handoffs WHERE status IN ('open','acknowledged')) handoffs,(SELECT count(*) FROM core.followups WHERE status='scheduled') followups,(SELECT count(*) FROM ops.delivery_outbox WHERE status='failed') failures");
      const cards = Object.entries(rows[0]).map(([key, value]) => `<div class="card"><div class="muted">${escapeHtml(key)}</div><div class="metric">${escapeHtml(value)}</div></div>`).join("");
      return send(res, 200, page("Visão geral", `<h1>Visão geral</h1><div class="grid">${cards}</div>`));
    }
    if (url.pathname === "/services") {
      const { rows } = await pool.query("SELECT service_id,name,category,pricing_mode,active FROM core.services ORDER BY name");
      const data = rows.map((row) => `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.category)}</td><td>${escapeHtml(row.pricing_mode)}</td><td>${row.active ? "Ativo" : "Inativo"}</td><td><form method="post" action="/services/toggle"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="id" value="${row.service_id}"><button>Alternar</button></form></td></tr>`).join("");
      return send(res, 200, page("Serviços", `<h1>Serviços</h1><div class="card"><table><tr><th>Nome</th><th>Categoria</th><th>Preço</th><th>Estado</th><th></th></tr>${data}</table></div>`));
    }
    if (url.pathname === "/leads") {
      const { rows } = await pool.query("SELECT l.lead_id,c.full_name,co.name company,l.stage,l.score,l.temperature_band,l.updated_at FROM core.leads l JOIN core.contacts c ON c.contact_id=l.contact_id LEFT JOIN core.companies co ON co.company_id=l.company_id ORDER BY l.updated_at DESC LIMIT 200");
      const data = rows.map((row) => `<tr><td>${escapeHtml(row.full_name)}</td><td>${escapeHtml(row.company)}</td><td>${escapeHtml(row.stage)}</td><td>${row.score}</td><td>${escapeHtml(row.temperature_band)}</td></tr>`).join("");
      return send(res, 200, page("Pipeline", `<h1>Pipeline</h1><div class="card"><table><tr><th>Contato</th><th>Empresa</th><th>Etapa</th><th>Score</th><th>Temperatura</th></tr>${data}</table></div>`));
    }
    if (url.pathname === "/handoffs") {
      const { rows } = await pool.query("SELECT h.handoff_id,c.full_name,co.name company,h.reason,h.priority,h.status,h.assigned_to,h.created_at,h.acknowledged_at,h.closed_at,h.resolution_note FROM core.handoffs h JOIN core.leads l ON l.lead_id=h.lead_id JOIN core.contacts c ON c.contact_id=l.contact_id LEFT JOIN core.companies co ON co.company_id=l.company_id ORDER BY CASE WHEN h.status='open' THEN 0 WHEN h.status='acknowledged' THEN 1 ELSE 2 END,h.created_at DESC LIMIT 300");
      const data = rows.map((row) => {
        const acknowledge = row.status === "open" ? `<form method="post" action="/handoffs/acknowledge"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="id" value="${row.handoff_id}"><button>Assumir</button></form>` : "";
        const close = ["open", "acknowledged"].includes(row.status) ? `<form method="post" action="/handoffs/close" class="actions"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="id" value="${row.handoff_id}"><textarea name="resolution_note" maxlength="1000" placeholder="Resumo opcional"></textarea><button class="danger">Encerrar</button></form>` : "";
        return `<tr><td>${escapeHtml(row.full_name)}</td><td>${escapeHtml(row.company ?? "-")}</td><td>${escapeHtml(row.reason)}</td><td>${escapeHtml(row.priority)}</td><td>${escapeHtml(row.status)}</td><td>${escapeHtml(row.assigned_to ?? "-")}</td><td>${escapeHtml(row.created_at)}</td><td><div class="actions">${acknowledge}${close}</div>${row.resolution_note ? `<div class="muted">${escapeHtml(row.resolution_note)}</div>` : ""}</td></tr>`;
      }).join("");
      return send(res, 200, page("Atendimento humano", `<h1>Atendimento humano</h1><p class="muted">Enquanto o estado estiver aberto ou assumido, o agente não responde ao contato.</p><div class="card"><table><tr><th>Contato</th><th>Empresa</th><th>Motivo</th><th>Prioridade</th><th>Estado</th><th>Responsável</th><th>Criado</th><th>Ações</th></tr>${data}</table></div>`));
    }
    if (url.pathname === "/followups") {
      const { rows } = await pool.query("SELECT f.followup_id,c.full_name,f.sequence_number,f.scheduled_for,f.status,o.status delivery_status,o.attempt_count,o.last_error_code FROM core.followups f JOIN core.leads l ON l.lead_id=f.lead_id JOIN core.contacts c ON c.contact_id=l.contact_id LEFT JOIN ops.delivery_outbox o ON o.followup_id=f.followup_id ORDER BY f.created_at DESC LIMIT 200");
      const data = rows.map((row) => `<tr><td>${escapeHtml(row.full_name)}</td><td>${row.sequence_number}</td><td>${escapeHtml(row.scheduled_for)}</td><td>${escapeHtml(row.status)}</td><td>${escapeHtml(row.delivery_status ?? "-")}</td><td>${row.attempt_count ?? 0}</td><td>${escapeHtml(row.last_error_code ?? "-")}</td></tr>`).join("");
      return send(res, 200, page("Follow-ups", `<h1>Follow-ups</h1><div class="card"><table><tr><th>Contato</th><th>#</th><th>Agendado</th><th>Estado</th><th>Entrega</th><th>Tentativas</th><th>Erro</th></tr>${data}</table></div>`));
    }
    if (url.pathname === "/settings") {
      const { rows } = await pool.query("SELECT flag_name,enabled,metadata FROM ops.runtime_flags ORDER BY flag_name");
      const data = rows.map((row) => `<tr><td>${escapeHtml(row.flag_name)}</td><td>${row.enabled ? "Ligado" : "Desligado"}</td><td>${escapeHtml(JSON.stringify(row.metadata))}</td><td>${["automation_paused","followup_enabled","dispatcher_enabled","retention_enabled"].includes(row.flag_name) ? `<form method="post" action="/flags/set"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="flag" value="${row.flag_name}"><input type="hidden" name="enabled" value="${!row.enabled}"><button class="${row.enabled ? "danger" : ""}">${row.enabled ? "Desligar" : "Ligar"}</button></form>` : ""}</td></tr>`).join("");
      return send(res, 200, page("Controles", `<h1>Controles</h1><div class="card"><table><tr><th>Flag</th><th>Estado</th><th>Metadados</th><th></th></tr>${data}</table></div>`));
    }
    return send(res, 404, page("Não encontrado", "<div class=\"card\">Página não encontrada.</div>"));
  } catch (error) {
    console.error(JSON.stringify({ event: "admin_error", code: String(error?.message ?? "UNKNOWN").slice(0, 100) }));
    send(res, 500, page("Erro", "<div class=\"card\">Falha interna redigida.</div>"));
  }
});

server.listen(port, "0.0.0.0", () => console.log(JSON.stringify({ event: "admin_started", port })));
