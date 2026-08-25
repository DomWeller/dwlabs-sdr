import { afterEach, describe, expect, it, vi } from "vitest";
import plugin, { hasActiveHandoff, normalizeWhatsAppSenderId } from "../plugins/dwlabs-sdr-tools/src/index.js";

afterEach(() => vi.unstubAllGlobals());

describe("human handoff guard", () => {
  it("normalizes WhatsApp JIDs without leaking device suffixes into the phone", () => {
    expect(normalizeWhatsAppSenderId("5511999999999@s.whatsapp.net")).toBe("5511999999999");
    expect(normalizeWhatsAppSenderId("5511999999999:12@s.whatsapp.net")).toBe("5511999999999");
    expect(normalizeWhatsAppSenderId("invalid")).toBeNull();
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
  });

  it("registers all tools plus an inbound claim hook that silences active handoffs", async () => {
    const tools: unknown[] = [];
    let inboundClaim: ((event: unknown, context: Record<string, unknown>) => Promise<unknown>) | undefined;
    const api = {
      pluginConfig: { baseUrl: "https://n8n.invalid/webhook", bearerToken: "test-token-".repeat(6) },
      registerTool(tool: unknown) { tools.push(tool); },
      on(name: string, handler: typeof inboundClaim) {
        if (name === "inbound_claim") inboundClaim = handler;
      }
    };
    plugin.register(api as never);
    expect(tools).toHaveLength(22);
    expect(inboundClaim).toBeTypeOf("function");

    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      ok: true,
      data: { lead: { handoff: { handoff_id: "id", status: "open", priority: "normal" } } }
    }), { status: 200, headers: { "content-type": "application/json" } })));

    await expect(inboundClaim?.({}, {
      agentId: "comercial",
      channelId: "whatsapp",
      senderId: "5511999999999:3@s.whatsapp.net",
      messageId: "message-1"
    })).resolves.toEqual({ handled: true });
  });
});
