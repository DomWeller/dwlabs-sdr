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
const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const leadStages = ["NOVO_LEAD", "EM_QUALIFICACAO", "QUALIFICADO", "REUNIAO_MARCADA", "REUNIAO_REALIZADA", "PROPOSTA", "NEGOCIACAO", "FECHADO", "PERDIDO", "FOLLOWUP"];

function required(name, minLength) {
  const value = process.env[name];
  if (!value || value.length < minLength || value.includes("PLACEHOLDER")) throw new Error(`${name} ausente ou invalido`);
  return value;
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

function field(form, name, maxLength, requiredValue = false) {
  const value = String(form.get(name) ?? "").trim();
  if (value.length > maxLength || (requiredValue && !value)) throw new Error(`FIELD_INVALID:${name}`);
  return value;
}

function optionalNumber(form, name) {
  const raw = String(form.get(name) ?? "").trim();
  if (!raw) return null;
  const value = Number(raw.replace(",", "."));
  if (!Number.isFinite(value)) throw new Error(`NUMBER_INVALID:${name}`);
  return value;
}

function optionalHttpsUrl(form, name) {
  const value = field(form, name, 500);
  if (!value) return "";
  let parsed;
  try { parsed = new URL(value); } catch { throw new Error(`URL_INVALID:${name}`); }
  if (parsed.protocol !== "https:") throw new Error(`URL_INVALID:${name}`);
  return parsed.toString();
}

function csv(value) {
  return String(value ?? "").split(",").map((item) => item.trim()).filter(Boolean).slice(0, 30);
}

function uuid(value, name = "id") {
  const normalized = String(value ?? "");
  if (!uuidPattern.test(normalized)) throw new Error(`UUID_INVALID:${name}`);
  return normalized;
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
  :root{font-family:system-ui,sans-serif;color:#172033;background:#f5f7fb}body{margin:0}header{background:#111827;color:white;padding:16px 24px}nav a{color:#dbeafe;margin-right:14px;line-height:2}main{max-width:1280px;margin:24px auto;padding:0 18px}.card{background:white;border:1px solid #dbe2ea;border-radius:12px;padding:18px;margin-bottom:16px;overflow:auto}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:10px;border-bottom:1px solid #e5e7eb;vertical-align:top}input,select,textarea,button{padding:9px;border:1px solid #cbd5e1;border-radius:7px;max-width:100%}textarea{min-width:220px}button{background:#1d4ed8;color:white;cursor:pointer}.danger{background:#b91c1c}.muted{color:#64748b}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.metric{font-size:28px;font-weight:700}.actions{display:flex;gap:8px;align-items:flex-start;flex-wrap:wrap}.form-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:10px}.form-grid label{display:flex;flex-direction:column;gap:4px}.wide{grid-column:1/-1}</style></head><body><header><strong>DWLabs SDR</strong><nav><a href="/">Visão geral</a><a href="/services">Serviços</a><a href="/leads">Pipeline</a><a href="/handoffs">Atendimento humano</a><a href="/catalog">Conteúdo</a><a href="/rules">Regras</a><a href="/followups">Follow-ups</a><a href="/privacy">LGPD</a><a href="/settings">Controles</a><a href="/logout">Sair</a></nav></header><main>${content}</main></body></html>`;
}

function send(res, status, content, headers = {}) {
  res.writeHead(status, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "content-security-policy": "default-src 'self'; style-src 'unsafe-inline'; frame-ancestors 'none'", ...headers });
  res.end(content);
}

async function audit(client, action, entityType, entityId, diff) {
  await client.query("INSERT INTO audit.admin_change_log(admin_subject,action,entity_type,entity_id,diff_redacted) VALUES($1,$2,$3,$4,$5)", [adminUser, action, entityType, entityId, diff]);
}

async function transaction(work) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await work(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
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
      if (url.pathname === "/services/save") {
        const serviceId = String(form.get("id") ?? "");
        const slug = field(form, "slug", 100, true);
        if (!slugPattern.test(slug)) throw new Error("SERVICE_SLUG_INVALID");
        const pricingMode = field(form, "pricing_mode", 40, true);
        if (!["sob_consulta", "faixa", "fixo"].includes(pricingMode)) throw new Error("PRICING_MODE_INVALID");
        const priceFrom = optionalNumber(form, "price_from");
        const priceTo = optionalNumber(form, "price_to");
        if ((priceFrom !== null && priceFrom < 0) || (priceTo !== null && priceTo < 0)) throw new Error("PRICE_INVALID");
        if (pricingMode === "fixo" && (priceFrom === null || (priceTo !== null && priceTo !== priceFrom))) throw new Error("FIXED_PRICE_INVALID");
        if (pricingMode === "faixa" && (priceFrom === null || priceTo === null || priceFrom > priceTo)) throw new Error("PRICE_RANGE_INVALID");
        if (pricingMode === "sob_consulta" && (priceFrom !== null || priceTo !== null)) throw new Error("CONSULTATION_PRICE_INVALID");
        const values = [slug, field(form, "name", 160, true), field(form, "category", 100, true), field(form, "summary", 2000, true), field(form, "qualification_hint", 2000, true), pricingMode, priceFrom, priceTo, field(form, "currency", 3, true).toUpperCase(), field(form, "duration_estimate", 200), optionalHttpsUrl(form, "commercial_url"), form.get("active") === "true"];
        const client = await pool.connect();
        try {
          await client.query("BEGIN");
          const result = serviceId ? await client.query("UPDATE core.services SET slug=$2,name=$3,category=$4,summary=$5,qualification_hint=$6,pricing_mode=$7,price_from=$8,price_to=$9,currency=$10,duration_estimate=NULLIF($11,''),commercial_url=NULLIF($12,''),active=$13,updated_at=NOW() WHERE service_id=$1 RETURNING service_id", [uuid(serviceId), ...values]) : await client.query("INSERT INTO core.services(slug,name,category,summary,qualification_hint,pricing_mode,price_from,price_to,currency,duration_estimate,commercial_url,active) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,NULLIF($10,''),NULLIF($11,''),$12) RETURNING service_id", values);
          if (!result.rowCount) throw new Error("SERVICE_NOT_FOUND");
          await audit(client, serviceId ? "update" : "create", "service", result.rows[0].service_id, { slug, pricing_mode: pricingMode, price_configured: priceFrom !== null || priceTo !== null, commercial_url_configured: Boolean(values[10]) });
          await client.query("COMMIT");
        } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
        return send(res, 303, "", { location: "/services" });
      }
      if (url.pathname === "/leads/stage") {
        const leadId = uuid(form.get("id"), "lead_id");
        const stage = field(form, "stage", 40, true);
        if (!leadStages.includes(stage)) throw new Error("LEAD_STAGE_INVALID");
        const client = await pool.connect();
        try {
          await client.query("BEGIN");
          const result = await client.query("UPDATE core.leads SET stage=$2,updated_at=NOW() WHERE lead_id=$1 RETURNING lead_id", [leadId, stage]);
          if (!result.rowCount) throw new Error("LEAD_NOT_FOUND");
          await audit(client, "set_stage", "lead", leadId, { stage });
          await client.query("COMMIT");
        } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
        return send(res, 303, "", { location: "/leads" });
      }
      if (url.pathname === "/portfolio/save") {
        const itemId = String(form.get("id") ?? "");
        const slug = field(form, "slug", 100, true);
        if (!slugPattern.test(slug)) throw new Error("PORTFOLIO_SLUG_INVALID");
        const serviceIdRaw = String(form.get("service_id") ?? "");
        const serviceId = serviceIdRaw ? uuid(serviceIdRaw, "service_id") : null;
        const values = [serviceId, slug, field(form, "title", 200, true), field(form, "segment", 120, true), field(form, "summary", 2000, true), field(form, "proof", 2000, true), field(form, "project_url", 500), field(form, "image_url", 500), csv(form.get("technologies")), field(form, "outcome_summary", 2000), form.get("is_public") === "true"];
        const client = await pool.connect();
        try {
          await client.query("BEGIN");
          const result = itemId ? await client.query("UPDATE core.portfolio_items SET service_id=$2,slug=$3,title=$4,segment=$5,summary=$6,proof=$7,project_url=NULLIF($8,''),image_url=NULLIF($9,''),technologies=$10,outcome_summary=NULLIF($11,''),is_public=$12,updated_at=NOW() WHERE portfolio_item_id=$1 RETURNING portfolio_item_id", [uuid(itemId), ...values]) : await client.query("INSERT INTO core.portfolio_items(service_id,slug,title,segment,summary,proof,project_url,image_url,technologies,outcome_summary,is_public) VALUES($1,$2,$3,$4,$5,$6,NULLIF($7,''),NULLIF($8,''),$9,NULLIF($10,''),$11) RETURNING portfolio_item_id", values);
          if (!result.rowCount) throw new Error("PORTFOLIO_NOT_FOUND");
          await audit(client, itemId ? "update" : "create", "portfolio_item", result.rows[0].portfolio_item_id, { slug, is_public: values[10] });
          await client.query("COMMIT");
        } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
        return send(res, 303, "", { location: "/catalog" });
      }
      if (url.pathname === "/knowledge/save") {
        const documentId = String(form.get("id") ?? "");
        const slug = field(form, "slug", 100, true);
        if (!slugPattern.test(slug)) throw new Error("KNOWLEDGE_SLUG_INVALID");
        const title = field(form, "title", 240, true);
        const category = field(form, "category", 100, true);
        const sourceUri = field(form, "source_uri", 500);
        const content = field(form, "content", 20_000, true);
        const status = field(form, "status", 20, true);
        if (!["active", "inactive"].includes(status)) throw new Error("KNOWLEDGE_STATUS_INVALID");
        const contentHash = createHash("sha256").update(content).digest("hex");
        const client = await pool.connect();
        try {
          await client.query("BEGIN");
          const result = documentId ? await client.query("UPDATE rag.knowledge_documents SET slug=$2,title=$3,category=$4,source_uri=NULLIF($5,''),body=$6,body_hash=$7,status=$8,updated_at=NOW() WHERE document_id=$1 RETURNING document_id", [uuid(documentId), slug, title, category, sourceUri, content, contentHash, status]) : await client.query("INSERT INTO rag.knowledge_documents(slug,title,category,source_uri,body,body_hash,status) VALUES($1,$2,$3,NULLIF($4,''),$5,$6,$7) RETURNING document_id", [slug, title, category, sourceUri, content, contentHash, status]);
          if (!result.rowCount) throw new Error("KNOWLEDGE_NOT_FOUND");
          const savedId = result.rows[0].document_id;
          await client.query("INSERT INTO rag.knowledge_chunks(document_id,chunk_index,title,body,body_tsv) VALUES($1,1,$2,$3,to_tsvector('portuguese',$3)) ON CONFLICT(document_id,chunk_index) DO UPDATE SET title=EXCLUDED.title,body=EXCLUDED.body,body_tsv=EXCLUDED.body_tsv", [savedId, title, content]);
          await audit(client, documentId ? "update" : "create", "knowledge_document", savedId, { slug, category, status });
          await client.query("COMMIT");
        } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
        return send(res, 303, "", { location: "/catalog" });
      }
      if (url.pathname === "/questions/save") {
        const code = field(form, "code", 100, true);
        if (!slugPattern.test(code)) throw new Error("QUESTION_CODE_INVALID");
        const weight = optionalNumber(form, "weight");
        if (!Number.isInteger(weight) || weight < 0 || weight > 100) throw new Error("QUESTION_WEIGHT_INVALID");
        await transaction(async (client) => {
          const result = await client.query("INSERT INTO core.qualification_questions(code,question,objective,weight,active) VALUES($1,$2,$3,$4,$5) ON CONFLICT(code) DO UPDATE SET question=EXCLUDED.question,objective=EXCLUDED.objective,weight=EXCLUDED.weight,active=EXCLUDED.active RETURNING question_id", [code, field(form, "question", 1000, true), field(form, "objective", 1000, true), weight, form.get("active") === "true"]);
          await audit(client, "save", "qualification_question", result.rows[0].question_id, { code, weight });
        });
        return send(res, 303, "", { location: "/rules" });
      }
      if (url.pathname === "/score-rules/save") {
        const code = field(form, "code", 100, true);
        if (!slugPattern.test(code)) throw new Error("SCORE_CODE_INVALID");
        const delta = optionalNumber(form, "delta");
        if (!Number.isInteger(delta) || delta < -100 || delta > 100) throw new Error("SCORE_DELTA_INVALID");
        await transaction(async (client) => {
          const result = await client.query("INSERT INTO core.score_rules(code,fact_key,match_value,label,delta,active) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(code) DO UPDATE SET fact_key=EXCLUDED.fact_key,match_value=EXCLUDED.match_value,label=EXCLUDED.label,delta=EXCLUDED.delta,active=EXCLUDED.active,updated_at=NOW() RETURNING rule_id", [code, field(form, "fact_key", 100, true), field(form, "match_value", 100, true), field(form, "label", 160, true), delta, form.get("active") === "true"]);
          await audit(client, "save", "score_rule", result.rows[0].rule_id, { code, delta });
        });
        return send(res, 303, "", { location: "/rules" });
      }
      if (url.pathname === "/business-hours/save") {
        const weekday = optionalNumber(form, "weekday");
        if (!Number.isInteger(weekday) || weekday < 0 || weekday > 6) throw new Error("WEEKDAY_INVALID");
        const opensAt = field(form, "opens_at", 5, true);
        const closesAt = field(form, "closes_at", 5, true);
        if (!/^\d{2}:\d{2}$/.test(opensAt) || !/^\d{2}:\d{2}$/.test(closesAt)) throw new Error("BUSINESS_HOURS_INVALID");
        await transaction(async (client) => {
          const enabled = form.get("enabled") === "true";
          const result = await client.query("UPDATE core.business_hours SET enabled=$2,opens_at=$3::time,closes_at=$4::time,updated_at=NOW() WHERE weekday=$1 RETURNING weekday", [weekday, enabled, opensAt, closesAt]);
          if (!result.rowCount) throw new Error("BUSINESS_HOURS_NOT_FOUND");
          await audit(client, "save", "business_hours", String(weekday), { enabled, opens_at: opensAt, closes_at: closesAt });
        });
        return send(res, 303, "", { location: "/rules" });
      }
      if (url.pathname === "/privacy/request") {
        const leadId = uuid(form.get("lead_id"), "lead_id");
        const requestType = field(form, "request_type", 20, true);
        if (!["export", "anonymize", "delete"].includes(requestType)) throw new Error("PRIVACY_TYPE_INVALID");
        await transaction(async (client) => {
          const result = await client.query("INSERT INTO ops.privacy_requests(lead_id,request_type,requested_by,result_redacted) SELECT lead_id,$2,$3,'{}'::jsonb FROM core.leads WHERE lead_id=$1 RETURNING privacy_request_id", [leadId, requestType, adminUser]);
          if (!result.rowCount) throw new Error("LEAD_NOT_FOUND");
          await audit(client, "request", "privacy_request", result.rows[0].privacy_request_id, { request_type: requestType, lead_id: leadId });
        });
        return send(res, 303, "", { location: "/privacy" });
      }
      if (url.pathname === "/flags/set") {
        const allowed = new Set(["automation_paused", "followup_enabled", "dispatcher_enabled", "retention_enabled"]);
        const flag = String(form.get("flag"));
        if (!allowed.has(flag)) throw new Error("FLAG_FORBIDDEN");
        const enabled = form.get("enabled") === "true";
        await transaction(async (client) => {
          const result = await client.query("UPDATE ops.runtime_flags SET enabled=$2,updated_at=NOW() WHERE flag_name=$1 RETURNING flag_name", [flag, enabled]);
          if (!result.rowCount) throw new Error("FLAG_NOT_FOUND");
          await audit(client, "set", "runtime_flag", flag, { enabled });
        });
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
      const { rows } = await pool.query("SELECT (SELECT count(*) FROM core.leads) leads,(SELECT count(*) FROM core.leads WHERE stage='FECHADO') fechados,(SELECT round(100.0*count(*) FILTER (WHERE stage='FECHADO')/NULLIF(count(*),0),1) FROM core.leads) conversao_pct,(SELECT round(avg(score),1) FROM core.leads) score_medio,(SELECT count(*) FROM core.meetings WHERE status IN ('scheduled','rescheduled')) reunioes,(SELECT count(*) FROM core.leads WHERE stage='PERDIDO') perdidos,(SELECT count(*) FROM core.handoffs WHERE status IN ('open','acknowledged')) handoffs,(SELECT count(*) FROM core.followups WHERE status='sent') followups_enviados,(SELECT count(*) FROM ops.delivery_outbox WHERE status='failed') falhas,(SELECT round(avg(metric_value),0) FROM ops.metrics_events WHERE metric_name='tool_call' AND created_at>NOW()-INTERVAL '24 hours') latencia_tool_ms,(SELECT round(avg(metric_value),0) FROM ops.metrics_events WHERE metric_name='model_call' AND created_at>NOW()-INTERVAL '24 hours') latencia_modelo_ms,(SELECT count(*) FROM ops.metrics_events WHERE metric_name='model_call' AND dimensions ->> 'outcome'='error' AND created_at>NOW()-INTERVAL '24 hours') erros_modelo");
      const cards = Object.entries(rows[0]).map(([key, value]) => `<div class="card"><div class="muted">${escapeHtml(key)}</div><div class="metric">${escapeHtml(value)}</div></div>`).join("");
      const origins = await pool.query("SELECT COALESCE(NULLIF(origin_detail,''),'nao_informada') origin,count(*) leads,count(*) FILTER (WHERE stage='FECHADO') fechados FROM core.leads GROUP BY COALESCE(NULLIF(origin_detail,''),'nao_informada') ORDER BY leads DESC LIMIT 20");
      const originRows = origins.rows.map((row) => `<tr><td>${escapeHtml(row.origin)}</td><td>${escapeHtml(row.leads)}</td><td>${escapeHtml(row.fechados)}</td></tr>`).join("");
      const tools = await pool.query("SELECT dimensions ->> 'tool' tool,count(*) calls,round(avg(metric_value),0) latency_ms,count(*) FILTER (WHERE COALESCE((dimensions ->> 'ok')::boolean,FALSE)=FALSE) errors FROM ops.metrics_events WHERE metric_name='tool_call' AND created_at>NOW()-INTERVAL '7 days' GROUP BY dimensions ->> 'tool' ORDER BY calls DESC LIMIT 20");
      const toolRows = tools.rows.map((row) => `<tr><td>${escapeHtml(row.tool)}</td><td>${escapeHtml(row.calls)}</td><td>${escapeHtml(row.latency_ms)}</td><td>${escapeHtml(row.errors)}</td></tr>`).join("");
      const models = await pool.query("SELECT dimensions ->> 'provider' provider,dimensions ->> 'model' model,count(*) calls,round(avg(metric_value),0) latency_ms,count(*) FILTER (WHERE dimensions ->> 'outcome'='error') errors FROM ops.metrics_events WHERE metric_name='model_call' AND created_at>NOW()-INTERVAL '7 days' GROUP BY dimensions ->> 'provider',dimensions ->> 'model' ORDER BY calls DESC LIMIT 20");
      const modelRows = models.rows.map((row) => `<tr><td>${escapeHtml(row.provider)}</td><td>${escapeHtml(row.model)}</td><td>${escapeHtml(row.calls)}</td><td>${escapeHtml(row.latency_ms)}</td><td>${escapeHtml(row.errors)}</td></tr>`).join("");
      return send(res, 200, page("Visão geral", `<h1>Visão geral</h1><div class="grid">${cards}</div><div class="card"><h2>Leads por origem</h2><table><tr><th>Origem</th><th>Leads</th><th>Fechados</th></tr>${originRows}</table></div><div class="card"><h2>Ferramentas — últimos 7 dias</h2><table><tr><th>Ferramenta</th><th>Chamadas</th><th>Latência média (ms)</th><th>Erros</th></tr>${toolRows}</table></div><div class="card"><h2>Modelo — últimos 7 dias</h2><table><tr><th>Provedor</th><th>Modelo</th><th>Chamadas</th><th>Latência média (ms)</th><th>Erros</th></tr>${modelRows}</table><p class="muted">Custo estimado permanece indisponível até o provedor entregar tokens e tabela de preço confiáveis; o painel não inventa esse valor.</p></div>`));
    }
    if (url.pathname === "/services") {
      const { rows } = await pool.query("SELECT service_id,slug,name,category,summary,qualification_hint,pricing_mode,price_from,price_to,currency,duration_estimate,commercial_url,active FROM core.services ORDER BY name");
      const formFor = (row = {}) => `<form method="post" action="/services/save" class="form-grid"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="id" value="${escapeHtml(row.service_id ?? "")}"><label>Slug<input name="slug" required value="${escapeHtml(row.slug ?? "")}"></label><label>Nome<input name="name" required value="${escapeHtml(row.name ?? "")}"></label><label>Categoria<input name="category" required value="${escapeHtml(row.category ?? "")}"></label><label>Preço<select name="pricing_mode"><option value="sob_consulta"${row.pricing_mode === "sob_consulta" ? " selected" : ""}>Sob consulta</option><option value="faixa"${row.pricing_mode === "faixa" ? " selected" : ""}>Faixa</option><option value="fixo"${row.pricing_mode === "fixo" ? " selected" : ""}>Fixo</option></select></label><label>De / valor fixo<input name="price_from" inputmode="decimal" value="${escapeHtml(row.price_from ?? "")}"></label><label>Até (somente faixa)<input name="price_to" inputmode="decimal" value="${escapeHtml(row.price_to ?? "")}"></label><label>Moeda<input name="currency" maxlength="3" required value="${escapeHtml(row.currency ?? "BRL")}"></label><label>Duração estimada<input name="duration_estimate" value="${escapeHtml(row.duration_estimate ?? "")}"></label><label>Link comercial HTTPS<input name="commercial_url" type="url" value="${escapeHtml(row.commercial_url ?? "")}"></label><label>Estado<select name="active"><option value="true"${row.active !== false ? " selected" : ""}>Ativo</option><option value="false"${row.active === false ? " selected" : ""}>Inativo</option></select></label><label class="wide">Resumo<textarea name="summary" required>${escapeHtml(row.summary ?? "")}</textarea></label><label class="wide">Orientação de qualificação<textarea name="qualification_hint" required>${escapeHtml(row.qualification_hint ?? "")}</textarea></label><button>${row.service_id ? "Salvar" : "Adicionar serviço"}</button></form>`;
      const data = rows.map((row) => `<div class="card"><h2>${escapeHtml(row.name)}</h2>${formFor(row)}</div>`).join("");
      return send(res, 200, page("Serviços", `<h1>Serviços e preços</h1><p class="muted">Valores vazios continuam sob consulta e nunca devem ser inventados.</p><div class="card"><h2>Novo serviço</h2>${formFor()}</div>${data}`));
    }
    if (url.pathname === "/leads") {
      const { rows } = await pool.query("SELECT l.lead_id,c.full_name,co.name company,l.stage,l.score,l.temperature_band,l.segment,l.city,l.objective,l.service_interests,l.updated_at FROM core.leads l JOIN core.contacts c ON c.contact_id=l.contact_id LEFT JOIN core.companies co ON co.company_id=l.company_id ORDER BY l.updated_at DESC LIMIT 200");
      const data = rows.map((row) => `<tr><td>${escapeHtml(row.full_name)}</td><td>${escapeHtml(row.company)}</td><td>${escapeHtml(row.segment ?? "-")} / ${escapeHtml(row.city ?? "-")}</td><td>${escapeHtml((row.service_interests ?? []).join(", ") || "-")}</td><td>${escapeHtml(row.objective ?? "-")}</td><td>${row.score} · ${escapeHtml(row.temperature_band)}</td><td><form method="post" action="/leads/stage"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="id" value="${row.lead_id}"><select name="stage">${leadStages.map((stage) => `<option value="${stage}"${stage === row.stage ? " selected" : ""}>${stage}</option>`).join("")}</select><button>Salvar</button></form></td></tr>`).join("");
      return send(res, 200, page("Pipeline", `<h1>Pipeline</h1><div class="card"><table><tr><th>Contato</th><th>Empresa</th><th>Segmento/cidade</th><th>Serviços</th><th>Objetivo</th><th>Score</th><th>Etapa manual</th></tr>${data}</table></div>`));
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
    if (url.pathname === "/catalog") {
      const [portfolio, knowledge, services] = await Promise.all([
        pool.query("SELECT portfolio_item_id,service_id,slug,title,segment,summary,proof,project_url,image_url,technologies,outcome_summary,is_public FROM core.portfolio_items ORDER BY title"),
        pool.query("SELECT document_id,slug,title,category,source_uri,status,body FROM rag.knowledge_documents ORDER BY title"),
        pool.query("SELECT service_id,name FROM core.services ORDER BY name")
      ]);
      const serviceOptions = (selected) => `<option value="">Sem vínculo</option>${services.rows.map((service) => `<option value="${service.service_id}"${service.service_id === selected ? " selected" : ""}>${escapeHtml(service.name)}</option>`).join("")}`;
      const portfolioForm = (row = {}) => `<form method="post" action="/portfolio/save" class="form-grid"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="id" value="${escapeHtml(row.portfolio_item_id ?? "")}"><label>Slug<input name="slug" required value="${escapeHtml(row.slug ?? "")}"></label><label>Título<input name="title" required value="${escapeHtml(row.title ?? "")}"></label><label>Serviço<select name="service_id">${serviceOptions(row.service_id)}</select></label><label>Segmento<input name="segment" required value="${escapeHtml(row.segment ?? "")}"></label><label>URL<input name="project_url" value="${escapeHtml(row.project_url ?? "")}"></label><label>Imagem<input name="image_url" value="${escapeHtml(row.image_url ?? "")}"></label><label>Tecnologias, separadas por vírgula<input name="technologies" value="${escapeHtml((row.technologies ?? []).join(", "))}"></label><label>Estado<select name="is_public"><option value="true"${row.is_public !== false ? " selected" : ""}>Público</option><option value="false"${row.is_public === false ? " selected" : ""}>Oculto</option></select></label><label class="wide">Resumo<textarea name="summary" required>${escapeHtml(row.summary ?? "")}</textarea></label><label class="wide">Prova permitida<textarea name="proof" required>${escapeHtml(row.proof ?? "")}</textarea></label><label class="wide">Resultado<textarea name="outcome_summary">${escapeHtml(row.outcome_summary ?? "")}</textarea></label><button>${row.portfolio_item_id ? "Salvar" : "Adicionar portfólio"}</button></form>`;
      const knowledgeForm = (row = {}) => `<form method="post" action="/knowledge/save" class="form-grid"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="id" value="${escapeHtml(row.document_id ?? "")}"><label>Slug<input name="slug" required value="${escapeHtml(row.slug ?? "")}"></label><label>Título<input name="title" required value="${escapeHtml(row.title ?? "")}"></label><label>Categoria<input name="category" required value="${escapeHtml(row.category ?? "")}"></label><label>Fonte<input name="source_uri" value="${escapeHtml(row.source_uri ?? "")}"></label><label>Estado<select name="status"><option value="active"${row.status !== "inactive" ? " selected" : ""}>Ativo</option><option value="inactive"${row.status === "inactive" ? " selected" : ""}>Inativo</option></select></label><label class="wide">Conteúdo<textarea name="content" required>${escapeHtml(row.body ?? "")}</textarea></label><button>${row.document_id ? "Salvar" : "Adicionar conhecimento"}</button></form>`;
      const portfolioCards = portfolio.rows.map((row) => `<div class="card"><h3>${escapeHtml(row.title)}</h3>${portfolioForm(row)}</div>`).join("");
      const knowledgeCards = knowledge.rows.map((row) => `<div class="card"><h3>${escapeHtml(row.title)}</h3>${knowledgeForm(row)}</div>`).join("");
      return send(res, 200, page("Conteúdo", `<h1>Portfólio e conhecimento</h1><div class="card"><h2>Novo item de portfólio</h2>${portfolioForm()}</div>${portfolioCards}<div class="card"><h2>Novo documento de conhecimento</h2>${knowledgeForm()}</div>${knowledgeCards}`));
    }
    if (url.pathname === "/rules") {
      const [questions, rules, hours] = await Promise.all([
        pool.query("SELECT code,question,objective,weight,active FROM core.qualification_questions ORDER BY code"),
        pool.query("SELECT code,fact_key,match_value,label,delta,active FROM core.score_rules ORDER BY code"),
        pool.query("SELECT weekday,enabled,opens_at::text,closes_at::text,timezone FROM core.business_hours ORDER BY weekday")
      ]);
      const questionForm = (row = {}) => `<form method="post" action="/questions/save" class="form-grid"><input type="hidden" name="csrf" value="${session.csrf}"><label>Código<input name="code" required value="${escapeHtml(row.code ?? "")}"></label><label>Peso<input type="number" min="0" max="100" name="weight" required value="${escapeHtml(row.weight ?? 0)}"></label><label>Estado<select name="active"><option value="true"${row.active !== false ? " selected" : ""}>Ativa</option><option value="false"${row.active === false ? " selected" : ""}>Inativa</option></select></label><label class="wide">Pergunta<textarea name="question" required>${escapeHtml(row.question ?? "")}</textarea></label><label class="wide">Objetivo<textarea name="objective" required>${escapeHtml(row.objective ?? "")}</textarea></label><button>Salvar pergunta</button></form>`;
      const scoreForm = (row = {}) => `<form method="post" action="/score-rules/save" class="form-grid"><input type="hidden" name="csrf" value="${session.csrf}"><label>Código<input name="code" required value="${escapeHtml(row.code ?? "")}"></label><label>Campo do fato<input name="fact_key" required value="${escapeHtml(row.fact_key ?? "")}"></label><label>Valor esperado<input name="match_value" required value="${escapeHtml(row.match_value ?? "")}"></label><label>Rótulo<input name="label" required value="${escapeHtml(row.label ?? "")}"></label><label>Pontos<input type="number" min="-100" max="100" name="delta" required value="${escapeHtml(row.delta ?? 0)}"></label><label>Estado<select name="active"><option value="true"${row.active !== false ? " selected" : ""}>Ativa</option><option value="false"${row.active === false ? " selected" : ""}>Inativa</option></select></label><button>Salvar regra</button></form>`;
      const hourRows = hours.rows.map((row) => `<form method="post" action="/business-hours/save" class="form-grid card"><input type="hidden" name="csrf" value="${session.csrf}"><input type="hidden" name="weekday" value="${row.weekday}"><strong>Dia ${row.weekday}</strong><label>Abre<input type="time" name="opens_at" required value="${escapeHtml(row.opens_at.slice(0,5))}"></label><label>Fecha<input type="time" name="closes_at" required value="${escapeHtml(row.closes_at.slice(0,5))}"></label><label>Estado<select name="enabled"><option value="true"${row.enabled ? " selected" : ""}>Aberto</option><option value="false"${!row.enabled ? " selected" : ""}>Fechado</option></select></label><button>Salvar horário</button></form>`).join("");
      return send(res, 200, page("Regras", `<h1>Regras comerciais</h1><h2>Horário comercial</h2>${hourRows}<div class="card"><h2>Nova pergunta</h2>${questionForm()}</div>${questions.rows.map((row) => `<div class="card">${questionForm(row)}</div>`).join("")}<div class="card"><h2>Nova regra de score</h2>${scoreForm()}</div>${rules.rows.map((row) => `<div class="card">${scoreForm(row)}</div>`).join("")}`));
    }
    if (url.pathname === "/followups") {
      const { rows } = await pool.query("SELECT f.followup_id,c.full_name,f.sequence_number,f.scheduled_for,f.status,o.status delivery_status,o.attempt_count,o.last_error_code FROM core.followups f JOIN core.leads l ON l.lead_id=f.lead_id JOIN core.contacts c ON c.contact_id=l.contact_id LEFT JOIN ops.delivery_outbox o ON o.followup_id=f.followup_id ORDER BY f.created_at DESC LIMIT 200");
      const data = rows.map((row) => `<tr><td>${escapeHtml(row.full_name)}</td><td>${row.sequence_number}</td><td>${escapeHtml(row.scheduled_for)}</td><td>${escapeHtml(row.status)}</td><td>${escapeHtml(row.delivery_status ?? "-")}</td><td>${row.attempt_count ?? 0}</td><td>${escapeHtml(row.last_error_code ?? "-")}</td></tr>`).join("");
      return send(res, 200, page("Follow-ups", `<h1>Follow-ups</h1><div class="card"><table><tr><th>Contato</th><th>#</th><th>Agendado</th><th>Estado</th><th>Entrega</th><th>Tentativas</th><th>Erro</th></tr>${data}</table></div>`));
    }
    if (url.pathname === "/privacy") {
      const [leads, requests] = await Promise.all([
        pool.query("SELECT l.lead_id,c.full_name,co.name company FROM core.leads l JOIN core.contacts c ON c.contact_id=l.contact_id LEFT JOIN core.companies co ON co.company_id=l.company_id ORDER BY l.updated_at DESC LIMIT 300"),
        pool.query("SELECT p.privacy_request_id,p.request_type,p.status,p.requested_by,p.created_at,c.full_name FROM ops.privacy_requests p LEFT JOIN core.leads l ON l.lead_id=p.lead_id LEFT JOIN core.contacts c ON c.contact_id=l.contact_id ORDER BY p.created_at DESC LIMIT 300")
      ]);
      const leadOptions = leads.rows.map((lead) => `<option value="${lead.lead_id}">${escapeHtml(lead.full_name)}${lead.company ? ` · ${escapeHtml(lead.company)}` : ""}</option>`).join("");
      const requestRows = requests.rows.map((row) => `<tr><td>${escapeHtml(row.full_name ?? "Lead removido")}</td><td>${escapeHtml(row.request_type)}</td><td>${escapeHtml(row.status)}</td><td>${escapeHtml(row.requested_by)}</td><td>${escapeHtml(row.created_at)}</td></tr>`).join("");
      return send(res, 200, page("LGPD", `<h1>Solicitações LGPD</h1><div class="card"><p>Esta fila registra pedidos de exportação, anonimização ou exclusão. A execução continua manual para evitar perda acidental.</p><form method="post" action="/privacy/request" class="form-grid"><input type="hidden" name="csrf" value="${session.csrf}"><label>Lead<select name="lead_id" required>${leadOptions}</select></label><label>Tipo<select name="request_type"><option value="export">Exportar</option><option value="anonymize">Anonimizar</option><option value="delete">Excluir</option></select></label><button>Registrar solicitação</button></form></div><div class="card"><table><tr><th>Contato</th><th>Tipo</th><th>Estado</th><th>Solicitado por</th><th>Data</th></tr>${requestRows}</table></div>`));
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
