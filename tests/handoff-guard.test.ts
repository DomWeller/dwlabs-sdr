import { afterEach, describe, expect, it, vi } from "vitest";
import plugin, {
  hasActiveHandoff,
  isCommercialAgentContext,
  leadFromResponse,
  normalizeWhatsAppSenderId
} from "../plugins/dwlabs-sdr-tools/src/index.js";

afterEach(() => vi.unstubAllGlobals());

describe("human handoff guard", () => {
  it("normalizes WhatsApp JIDs without leaking device suffixes into the phone", () => {
    expect(normalizeWhatsAppSenderId("5511999999999@s.whatsapp.net")).toBe("5511999999999");
    expect(normalizeWhatsAppSenderId("5511999999999:12@s.whatsapp.net")).toBe("5511999999999");
    expect(normalizeWhatsAppSenderId("invalid")).toBeNull();
  });

  it("recognizes the commercial agent from the explicit id or canonical session key", () => {
    expect(isCommercialAgentContext({ agentId: "comercial" })).toBe(true);
    expect(isCommercialAgentContext({}, "agent:comercial:test-session")).toBe(true);
    expect(isCommercialAgentContext({ agentId: "main" }, "agent:main:test-session")).toBe(false);
  });

  it("claims only leads with an active handoff", () => {
    const response = (status: string | null) => ({
      ok: true,
      data: { lead: { handoff: status ? { handoff_id: "id", status, priority: "normal" } : null } }
    });
    expect(hasActiveHandoff(response("open"))).toBe(true);
    expect(hasActiveHandoff(response("acknowledged"))).toBe(true);
    expect(hasActiveHandoff(response("closed"))).toBe(false);
    expect(hasActiveHandoff(response(null))).toBe(false);
    expect(hasActiveHandoff({ ok: false, data: null })).toBe(false);
    expect(leadFromResponse(response("closed"))).toMatchObject({ handoff: { status: "closed" } });
    expect(leadFromResponse({ ok: false, data: null })).toBeNull();
  });

  it("registers all tools, silences active handoffs and injects persisted CRM context", async () => {
    const tools: unknown[] = [];
    let inboundClaim: ((event: unknown, context: Record<string, unknown>) => Promise<unknown>) | undefined;
    let beforePromptBuild: ((event: unknown, context: Record<string, unknown>) => Promise<unknown>) | undefined;
    let modelCallEnded: ((event: Record<string, unknown>, context: Record<string, unknown>) => Promise<unknown>) | undefined;
    const api = {
      pluginConfig: { baseUrl: "https://n8n.invalid/webhook", bearerToken: "test-token-".repeat(6) },
      logger: { info: vi.fn() },
      registerTool(tool: unknown) { tools.push(tool); },
      on(name: string, handler: typeof inboundClaim) {
        if (name === "inbound_claim") inboundClaim = handler;
        if (name === "before_prompt_build") beforePromptBuild = handler;
        if (name === "model_call_ended") modelCallEnded = handler as typeof modelCallEnded;
      }
    };
    plugin.register(api as never);
    expect(tools).toHaveLength(22);
    expect(inboundClaim).toBeTypeOf("function");
    expect(beforePromptBuild).toBeTypeOf("function");
    expect(modelCallEnded).toBeTypeOf("function");

    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      ok: true,
      data: { lead: { handoff: { handoff_id: "id", status: "open", priority: "normal" } } }
    }), { status: 200, headers: { "content-type": "application/json" } })));

    await expect(inboundClaim?.({ channel: "whatsapp", senderId: "5511999999999:3@s.whatsapp.net", messageId: "message-1" }, {
      agentId: "comercial",
      senderId: "5511999999999:3@s.whatsapp.net",
      messageId: "message-1"
    })).resolves.toEqual({ handled: true });

    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      ok: true,
      data: { lead: { stage: "QUALIFICADO", needs: ["crm"], handoff: null } }
    }), { status: 200, headers: { "content-type": "application/json" } })));
    await expect(beforePromptBuild?.({}, {
      agentId: "comercial",
      messageProvider: "whatsapp",
      senderId: "5511999999999@s.whatsapp.net",
      runId: "run-1"
    })).resolves.toMatchObject({ prependContext: expect.stringContaining('"stage":"QUALIFICADO"') });

    await expect(modelCallEnded?.({
      runId: "run-1",
      callId: "call-1",
      durationMs: 1250,
      provider: "openai",
      model: "gpt-test",
      outcome: "completed"
    }, { agentId: "comercial", messageProvider: "whatsapp" })).resolves.toBeUndefined();
    const metricRequest = vi.mocked(fetch).mock.calls.at(-1)?.[1] as RequestInit;
    expect(String(metricRequest.body)).toContain('"metric_name":"model_call"');
  });
});
