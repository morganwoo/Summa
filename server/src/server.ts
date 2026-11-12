import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { InvalidPlanError, draftPlan, type Provider } from "./generate.js";
import { planRequestSchema } from "./schema.js";
import { InvalidReplyError, companionReply, reflectRequestSchema, type Companion } from "./reflect.js";
import type { EntitlementCheck } from "./entitlement.js";

export interface ServerOptions {
  /** "mock" or "provider"; reported by /healthz so a mock server is easy to spot. */
  mode?: string;
  provider: Provider;
  rateLimit?: { max: number; windowMs: number };
  /** The reflection companion (Summa Pro). Omit to leave the route switched off. */
  companion?: Companion;
  /** Verifies Summa Pro from the request's signed App Store transaction. */
  entitlement?: EntitlementCheck;
  companionLimit?: { max: number; windowMs: number };
  /** Receives one line per request: method, path, status, duration. Never bodies. */
  log?: (line: string) => void;
  now?: () => number;
}

const MAX_BODY_BYTES = 16 * 1024;
const MAX_CHAT_BODY_BYTES = 48 * 1024;

class HttpError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
  }
}

async function readJson(request: IncomingMessage, maxBytes: number = MAX_BODY_BYTES): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += (chunk as Buffer).length;
    if (size > maxBytes) throw new HttpError(413, "body_too_large");
    chunks.push(chunk as Buffer);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new HttpError(400, "invalid_json");
  }
}

/** Fixed-window limiter keyed by install token (or address). In-memory: use a shared store when scaling out. */
function createLimiter(max: number, windowMs: number, now: () => number) {
  const windows = new Map<string, { start: number; count: number }>();
  return (key: string): number | null => {
    const time = now();
    const current = windows.get(key);
    if (!current || time - current.start >= windowMs) {
      if (windows.size > 50_000) windows.clear();
      windows.set(key, { start: time, count: 1 });
      return null;
    }
    if (current.count >= max) return Math.ceil((current.start + windowMs - time) / 1000);
    current.count += 1;
    return null;
  };
}

export function createPlanServer(options: ServerOptions): Server {
  const now = options.now ?? Date.now;
  const limit = options.rateLimit ?? { max: 5, windowMs: 600_000 };
  const limiter = createLimiter(limit.max, limit.windowMs, now);
  const chatLimit = options.companionLimit ?? { max: 40, windowMs: 24 * 60 * 60 * 1000 };
  const chatLimiter = createLimiter(chatLimit.max, chatLimit.windowMs, now);
  const log = options.log ?? (() => {});

  const send = (response: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}) => {
    response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers });
    response.end(JSON.stringify(body));
  };

  return createServer(async (request, response) => {
    const started = now();
    const path = (request.url ?? "/").split("?")[0] ?? "/";
    let status = 500;
    try {
      if (request.method === "GET" && path === "/healthz") {
        status = 200;
        return send(response, status, { ok: true, mode: options.mode ?? "unknown" });
      }
      if (path !== "/v1/plans" && path !== "/v1/reflections/chat") throw new HttpError(404, "not_found");
      if (request.method !== "POST") throw new HttpError(405, "method_not_allowed");

      const install = request.headers["x-summa-install"];
      const key = (typeof install === "string" && /^[A-Za-z0-9-]{8,64}$/.test(install) ? install : undefined) ?? request.socket.remoteAddress ?? "unknown";

      if (path === "/v1/reflections/chat") {
        if (!options.companion || !options.entitlement) throw new HttpError(503, "companion_unavailable");
        // Summa Pro is checked here, from the signed transaction, before any model is called.
        const tier = options.entitlement(request.headers);
        if (tier === "unconfigured") throw new HttpError(503, "entitlement_not_configured");
        if (tier !== "pro") throw new HttpError(403, "pro_required");
        const wait = chatLimiter(key);
        if (wait !== null) {
          status = 429;
          return send(response, status, { error: "rate_limited" }, { "Retry-After": String(wait) });
        }
        const chat = reflectRequestSchema.safeParse(await readJson(request, MAX_CHAT_BODY_BYTES));
        if (!chat.success) throw new HttpError(400, "invalid_request");
        const reply = await companionReply(chat.data, options.companion);
        status = 200;
        return send(response, status, reply);
      }
      const retryAfter = limiter(key);
      if (retryAfter !== null) {
        status = 429;
        return send(response, status, { error: "rate_limited" }, { "Retry-After": String(retryAfter) });
      }

      const parsed = planRequestSchema.safeParse(await readJson(request));
      if (!parsed.success) throw new HttpError(400, "invalid_request");

      const plan = await draftPlan(parsed.data, options.provider);
      status = 200;
      return send(response, status, plan);
    } catch (error) {
      if (error instanceof HttpError) {
        status = error.status;
        return send(response, status, { error: error.code });
      }
      if (error instanceof InvalidReplyError) {
        status = 502;
        return send(response, status, { error: "invalid_reply" });
      }
      if (error instanceof InvalidPlanError) {
        status = 502;
        return send(response, status, { error: "invalid_plan" });
      }
      status = 502;
      // Log the kind of failure only; provider messages can echo user text.
      // The provider's status code is safe to log and says most of what is needed (401 key, 404 model, 429 quota).
      const providerStatus = error instanceof Error ? /^provider responded \d{3}$/.exec(error.message)?.[0] : undefined;
      log(`error ${providerStatus ?? (error instanceof Error ? error.name : "unknown")}`);
      return send(response, status, { error: "generation_failed" });
    } finally {
      log(`${request.method} ${path} ${status} ${now() - started}ms`);
    }
  });
}
