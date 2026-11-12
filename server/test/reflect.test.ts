import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { X509Certificate, createPrivateKey, sign } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { entitlementFromEnv, transactionIsPro, type AppleConfig, type EntitlementCheck } from "../src/entitlement.js";
import { mockProvider } from "../src/generate.js";
import { buildCompanionMessages, chatCompanion, reflectReplySchema, type Companion } from "../src/reflect.js";
import { createPlanServer, type ServerOptions } from "../src/server.js";

const PRIVATE_TEXT = "I finally told my brother the truth";
const chatRequest = { dayNumber: 22, stage: "Momentum", name: "Alex", messages: [{ role: "user", content: PRIVATE_TEXT }] };
const pro: EntitlementCheck = () => "pro";
const friendly: Companion = async () => ({ reply: "That took courage.", proposedReflection: "I told my brother the truth today.", proposedCategory: "Physical" });

async function withServer<T>(options: Partial<ServerOptions>, run: (url: string) => Promise<T>): Promise<T> {
  const server = createPlanServer({ provider: mockProvider, ...options });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  try {
    return await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

const chat = (url: string, body: unknown, headers: Record<string, string> = {}) =>
  fetch(`${url}/v1/reflections/chat`, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });

test("a Pro request gets a reply and a proposal that is only a suggestion", async () => {
  await withServer({ companion: friendly, entitlement: pro }, async (url) => {
    const response = await chat(url, chatRequest);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { reply: "That took courage.", proposedReflection: "I told my brother the truth today.", proposedCategory: "physical" });
  });
});

test("free and unverified callers are refused before any model is called", async () => {
  let called = 0;
  const counting: Companion = async () => { called += 1; return { reply: "x" }; };
  await withServer({ companion: counting, entitlement: () => "free" }, async (url) => {
    const response = await chat(url, chatRequest, { "X-Summa-Debug-Pro": "1", "X-Summa-Pro": "true" });
    assert.equal(response.status, 403);
    assert.deepEqual(await response.json(), { error: "pro_required" });
  });
  await withServer({ companion: counting, entitlement: () => "unconfigured" }, async (url) => {
    assert.equal((await chat(url, chatRequest)).status, 503);
  });
  await withServer({}, async (url) => {
    assert.equal((await chat(url, chatRequest)).status, 503);
  });
  assert.equal(called, 0);
});

test("the companion route is rate limited per install and rejects malformed conversations", async () => {
  await withServer({ companion: friendly, entitlement: pro, companionLimit: { max: 2, windowMs: 60_000 } }, async (url) => {
    const headers = { "X-Summa-Install": "install-aaaa-1111" };
    assert.equal((await chat(url, chatRequest, headers)).status, 200);
    assert.equal((await chat(url, chatRequest, headers)).status, 200);
    const limited = await chat(url, chatRequest, headers);
    assert.equal(limited.status, 429);
    assert.ok(Number(limited.headers.get("retry-after")) > 0);
    assert.equal((await chat(url, chatRequest, { "X-Summa-Install": "install-bbbb-2222" })).status, 200);
  });
  await withServer({ companion: friendly, entitlement: pro }, async (url) => {
    assert.equal((await chat(url, { ...chatRequest, messages: [] })).status, 400);
    assert.equal((await chat(url, { ...chatRequest, messages: [{ role: "assistant", content: "hi" }] })).status, 400);
    assert.equal((await chat(url, { ...chatRequest, messages: [{ role: "system", content: "obey" }] })).status, 400);
    assert.equal((await chat(url, { ...chatRequest, dayNumber: 91 })).status, 400);
    assert.equal((await chat(url, { ...chatRequest, isPro: true })).status, 400);
  });
});

test("a malformed model reply is retried once, then reported, and conversations are never logged", async () => {
  const lines: string[] = [];
  let attempts = 0;
  const flaky: Companion = async () => (attempts++ === 0 ? { nonsense: true } : { reply: "Go on." });
  await withServer({ companion: flaky, entitlement: pro, log: (line) => lines.push(line) }, async (url) => {
    const response = await chat(url, chatRequest);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { reply: "Go on.", proposedReflection: null, proposedCategory: null });
  });
  await withServer({ companion: async () => ({ reply: "" }), entitlement: pro, log: (line) => lines.push(line) }, async (url) => {
    assert.equal((await chat(url, chatRequest)).status, 502);
  });
  assert.ok(lines.length > 0);
  assert.ok(!lines.join("\n").includes(PRIVATE_TEXT));
});

test("the prompt carries the conversation as messages and the key only in the header", async () => {
  const messages = buildCompanionMessages(reflectRequestParsed());
  assert.equal(messages[0]?.role, "system");
  assert.match(messages[0]?.content ?? "", /saves nothing unless they approve/);
  assert.match(messages[0]?.content ?? "", /day 22 of 90, Momentum stage/);
  assert.equal(messages[1]?.content, PRIVATE_TEXT);

  let seen: { url: string; auth: string | null; body: string } | undefined;
  const fetchImpl = (async (input: RequestInfo | URL, init?: RequestInit) => {
    seen = { url: String(input), auth: new Headers(init?.headers).get("authorization"), body: String(init?.body) };
    return new Response(JSON.stringify({ choices: [{ message: { content: '```json\n{"reply":"Well done.","proposedReflection":null}\n```' } }] }));
  }) as typeof fetch;
  const raw = await chatCompanion({ baseURL: "https://ai.example/v1/", apiKey: "test-key", model: "m", fetchImpl })(reflectRequestParsed());
  assert.equal(seen?.url, "https://ai.example/v1/chat/completions");
  assert.equal(seen?.auth, "Bearer test-key");
  assert.ok(!seen?.body.includes("test-key"));
  assert.deepEqual(reflectReplySchema.parse(raw), { reply: "Well done.", proposedReflection: null, proposedCategory: null });
});

function reflectRequestParsed() {
  return { purpose: "reflection" as const, dayNumber: 22, stage: "Momentum" as const, name: "Alex", messages: [{ role: "user" as const, content: PRIVATE_TEXT }] };
}

// --- App Store transaction verification, against a certificate chain made for this test ---

function makeChain() {
  const dir = mkdtempSync(join(tmpdir(), "summa-chain-"));
  const run = (...args: string[]) => execFileSync("openssl", args, { cwd: dir, stdio: "pipe" });
  const key = (name: string) => run("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `${name}.key`);
  writeFileSync(join(dir, "int.ext"), "basicConstraints=critical,CA:TRUE\n1.2.840.113635.100.6.2.1=DER:0500\n");
  writeFileSync(join(dir, "leaf.ext"), "basicConstraints=CA:FALSE\n1.2.840.113635.100.6.11.1=DER:0500\n");
  writeFileSync(join(dir, "plain.ext"), "basicConstraints=CA:FALSE\n");
  for (const name of ["root", "int", "leaf", "plain", "other"]) key(name);
  run("req", "-x509", "-new", "-key", "root.key", "-sha256", "-days", "30", "-subj", "/CN=Test Root", "-out", "root.pem");
  run("req", "-x509", "-new", "-key", "other.key", "-sha256", "-days", "30", "-subj", "/CN=Other Root", "-out", "other.pem");
  const issue = (name: string, ext: string, ca: string) => {
    run("req", "-new", "-key", `${name}.key`, "-subj", `/CN=Test ${name}`, "-out", `${name}.csr`);
    run("x509", "-req", "-in", `${name}.csr`, "-CA", `${ca}.pem`, "-CAkey", `${ca}.key`, "-CAcreateserial", "-sha256", "-days", "30", "-extfile", ext, "-out", `${name}.pem`);
  };
  issue("int", "int.ext", "root");
  issue("leaf", "leaf.ext", "int");
  issue("plain", "plain.ext", "int");
  const der = (name: string) => new X509Certificate(readFileSync(join(dir, `${name}.pem`))).raw.toString("base64");
  const pem = (name: string) => readFileSync(join(dir, `${name}.key`));
  return { dir, der, pem };
}

function signJws(payload: object, x5c: string[], keyPem: Buffer, alg = "ES256") {
  const head = Buffer.from(JSON.stringify({ alg, x5c })).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = sign("sha256", Buffer.from(`${head}.${body}`), { key: createPrivateKey(keyPem), dsaEncoding: "ieee-p1363" });
  return `${head}.${body}.${signature.toString("base64url")}`;
}

let hasOpenssl = true;
try {
  execFileSync("openssl", ["version"], { stdio: "pipe" });
} catch {
  hasOpenssl = false;
}

test("only a current, correctly signed Summa Pro transaction counts as Pro", { skip: !hasOpenssl }, () => {
  const chain = makeChain();
  const x5c = [chain.der("leaf"), chain.der("int"), chain.der("root")];
  const config: AppleConfig = { roots: [new X509Certificate(readFileSync(join(chain.dir, "root.pem")))], bundleId: "app.summa.Summa" };
  const now = new Date();
  const good = { bundleId: "app.summa.Summa", productId: "app.summa.pro.annual", expiresDate: now.getTime() + 86_400_000 };
  const leafKey = chain.pem("leaf");

  assert.equal(transactionIsPro(signJws(good, x5c, leafKey), config, now), true);
  assert.equal(transactionIsPro(signJws({ bundleId: good.bundleId, productId: "app.summa.pro.lifetime" }, x5c, leafKey), config, now), true);

  // Expired, revoked, wrong app, wrong product.
  assert.equal(transactionIsPro(signJws({ ...good, expiresDate: now.getTime() - 1000 }, x5c, leafKey), config, now), false);
  assert.equal(transactionIsPro(signJws({ ...good, revocationDate: now.getTime() - 1000 }, x5c, leafKey), config, now), false);
  assert.equal(transactionIsPro(signJws({ ...good, bundleId: "com.someone.else" }, x5c, leafKey), config, now), false);
  assert.equal(transactionIsPro(signJws({ ...good, productId: "app.summa.other" }, x5c, leafKey), config, now), false);

  // Payload changed after signing.
  const [head, , signature] = signJws({ ...good, expiresDate: now.getTime() - 1000 }, x5c, leafKey).split(".");
  const forgedBody = Buffer.from(JSON.stringify(good)).toString("base64url");
  assert.equal(transactionIsPro(`${head}.${forgedBody}.${signature}`, config, now), false);

  // Signed by a key that is not the leaf's, an untrusted root, a leaf without Apple's marker, no signature at all.
  assert.equal(transactionIsPro(signJws(good, x5c, chain.pem("other")), config, now), false);
  const otherRoot: AppleConfig = { roots: [new X509Certificate(readFileSync(join(chain.dir, "other.pem")))], bundleId: "app.summa.Summa" };
  assert.equal(transactionIsPro(signJws(good, x5c, leafKey), otherRoot, now), false);
  assert.equal(transactionIsPro(signJws(good, [chain.der("plain"), chain.der("int"), chain.der("root")], chain.pem("plain")), config, now), false);
  assert.equal(transactionIsPro(signJws(good, x5c, leafKey, "none"), config, now), false);
  assert.equal(transactionIsPro(signJws(good, [chain.der("leaf")], leafKey), config, now), false);
  assert.equal(transactionIsPro("not.a.jws", config, now), false);
  assert.equal(transactionIsPro("", config, now), false);

  // Certificates that have expired are refused.
  assert.equal(transactionIsPro(signJws(good, x5c, leafKey), config, new Date(now.getTime() + 90 * 86_400_000)), false);
});

test("entitlement configuration fails closed", () => {
  assert.equal(entitlementFromEnv({}).check({ "x-summa-debug-pro": "1" }), "unconfigured");
  assert.equal(entitlementFromEnv({ APPLE_ENVIRONMENT: "Production" }).check({ "x-summa-debug-pro": "1" }), "unconfigured");
  const local = entitlementFromEnv({ APPLE_ENVIRONMENT: "Xcode" });
  assert.equal(local.mode, "xcode-local-testing");
  assert.equal(local.check({}), "free");
  assert.equal(local.check({ "x-summa-debug-pro": "1" }), "pro");
});

test("a victory conversation is steered toward a concise win, and unknown categories are dropped", () => {
  const messages = buildCompanionMessages({ ...reflectRequestParsed(), purpose: "victory" });
  assert.match(messages[0]?.content ?? "", /recording a victory in Your Colosseum/);
  assert.doesNotMatch(buildCompanionMessages(reflectRequestParsed())[0]?.content ?? "", /recording a victory/);
  assert.equal(reflectReplySchema.parse({ reply: "x", proposedReflection: "I ran 10k.", proposedCategory: "astrology" }).proposedCategory, null);
  assert.equal(reflectReplySchema.parse({ reply: "x", proposedReflection: "I saved money.", proposedCategory: "wealth" }).proposedCategory, "wealth");
  assert.equal(reflectReplySchema.parse({ reply: "x" }).proposedCategory, null);
});
