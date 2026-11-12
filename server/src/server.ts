import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { InvalidPlanError, draftPlan, type Provider } from "./generate.js";
import { planRequestSchema } from "./schema.js";

export interface ServerOptions {
  provider: Provider;
  rateLimit?: { max: number; windowMs: number };
  /** Receives one line per request: method, path, status, duration. Never bodies. */
  log?: (line: string) => void;
  now?: () => number;
}

const MAX_BODY_BYTES = 16 * 1024;

class HttpError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
  }
}

async function readJson(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += (chunk as Buffer).length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, "body_too_large");
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
        return send(response, status, { ok: true });
      }
      if (path !== "/v1/plans") throw new HttpError(404, "not_found");
      if (request.method !== "POST") throw new HttpError(405, "method_not_allowed");

      const install = request.headers["x-summa-install"];
      const key = (typeof install === "string" && /^[A-Za-z0-9-]{8,64}$/.test(install) ? install : undefined) ?? request.socket.remoteAddress ?? "unknown";
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
      if (error instanceof InvalidPlanError) {
        status = 502;
        return send(response, status, { error: "invalid_plan" });
      }
      status = 502;
      // Log the kind of failure only; provider messages can echo user text.
      log(`error ${error instanceof Error ? error.name : "unknown"}`);
      return send(response, status, { error: "generation_failed" });
    } finally {
      log(`${request.method} ${path} ${status} ${now() - started}ms`);
    }
  });
}
