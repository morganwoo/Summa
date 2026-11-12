import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { buildUserMessage, chatProvider, mockProvider, type Provider } from "../src/generate.js";
import { planSchema } from "../src/schema.js";
import { createPlanServer, type ServerOptions } from "../src/server.js";

const SECRET_TEXT = "my private three-year vision";

const validRequest = {
  schemaVersion: 1,
  answers: {
    name: ["Alex"],
    focus: ["Reading", "Movement"],
    username: ["alex_k"],
    obstacles: ["Low energy"],
    objective: ["Finish four books"],
    timeOfDay: ["Morning"],
    startSize: ["Tiny — almost too easy"],
    future: [SECRET_TEXT],
  },
  weekdays: [2, 4, 6],
  minutesPerDay: 20,
};

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

const post = (url: string, body: unknown, headers: Record<string, string> = {}) =>
  fetch(`${url}/v1/plans`, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: typeof body === "string" ? body : JSON.stringify(body) });

test("drafts a schema-valid plan in mock mode without credentials", async () => {
  await withServer({}, async (url) => {
    const response = await post(url, validRequest);
    assert.equal(response.status, 200);
    const plan = planSchema.parse(await response.json());
    assert.equal(plan.objective, "Finish four books");
    assert.equal(plan.habits.length, 3);
    assert.equal(plan.habits[0]?.target, "2 pages");
    assert.match(plan.habits[0]?.reason ?? "", /Finish four books.*low energy/);
    assert.deepEqual(plan.habits[0]?.weekdays, [2, 4, 6]);
    assert.deepEqual(plan.habits[0]?.reminder, { hour: 7, minute: 30 });
    assert.deepEqual(plan.phases.map((phase) => phase.title), ["Find your footing", "Settle into rhythm", "Make it yours"]);
  });
});

test("rejects malformed requests before any generation happens", async () => {
  let calls = 0;
  const provider: Provider = async (request) => { calls += 1; return mockProvider(request); };
  await withServer({ provider, rateLimit: { max: 100, windowMs: 1000 } }, async (url) => {
    assert.equal((await post(url, "{not json")).status, 400);
    assert.equal((await post(url, { ...validRequest, schemaVersion: 2 })).status, 400);
    assert.equal((await post(url, { ...validRequest, weekdays: [0, 9] })).status, 400);
    assert.equal((await post(url, { ...validRequest, answers: { unknownQuestion: ["x"] } })).status, 400);
    assert.equal((await post(url, { ...validRequest, extraField: true })).status, 400);
    assert.equal((await post(url, { ...validRequest, answers: { future: ["x".repeat(20_000)] } })).status, 413);
    assert.equal((await fetch(`${url}/v1/plans`)).status, 405);
    assert.equal((await fetch(`${url}/nope`)).status, 404);
    assert.equal(calls, 0);
  });
});

test("never returns model output that fails the plan schema", async () => {
  const base = (await mockProvider(validRequest as never)) as { habits: Record<string, unknown>[] };
  const bad: unknown[] = [
    null,
    "I am not JSON",
    { schemaVersion: 1, objective: "x", habits: [], phases: [] },
    ...[2, 4].map((length) => ({ ...base, habits: Array.from({ length }, (_, i) => ({ title: `H${i}`, action: "a", minimumVersion: "m", target: "1", reason: "r", weekdays: [1] })) })),
    { ...base, habits: base.habits.map(({ reason, ...rest }) => rest) },
    { ...base, habits: base.habits.map((habit) => ({ ...habit, title: "Same" })) },
    { ...base, injected: "<script>" },
  ];
  for (const output of bad) {
    let calls = 0;
    await withServer({ provider: async () => { calls += 1; return output; }, rateLimit: { max: 100, windowMs: 1000 } }, async (url) => {
      const response = await post(url, validRequest);
      assert.equal(response.status, 502);
      assert.deepEqual(await response.json(), { error: "invalid_plan" });
    });
    assert.equal(calls, 2, "retries once before failing");
  }
});

test("drafts exactly three habits for every profile, and does not send the username to the model", async () => {
  for (const focus of [[], ["Reading"], ["Focus", "Movement", "Reading", "Sleep routine", "Reflection"], ["Learn the cello"]]) {
    const plan = planSchema.parse(await mockProvider({ ...validRequest, answers: { ...validRequest.answers, focus } } as never));
    assert.equal(plan.habits.length, 3);
    assert.equal(new Set(plan.habits.map((habit) => habit.title)).size, 3);
  }
  assert.ok(!buildUserMessage(validRequest as never).includes("alex_k"));
});

test("recovers when the first draft is invalid and the retry is valid", async () => {
  let calls = 0;
  const provider: Provider = async (request) => (++calls === 1 ? { nonsense: true } : mockProvider(request));
  await withServer({ provider }, async (url) => {
    const response = await post(url, validRequest);
    assert.equal(response.status, 200);
    planSchema.parse(await response.json());
  });
});

test("rate-limits generation per install and isolates installs from each other", async () => {
  let time = 0;
  await withServer({ rateLimit: { max: 2, windowMs: 60_000 }, now: () => time }, async (url) => {
    const a = { "X-Summa-Install": "install-aaaaaaaa" };
    const b = { "X-Summa-Install": "install-bbbbbbbb" };
    assert.equal((await post(url, validRequest, a)).status, 200);
    assert.equal((await post(url, validRequest, a)).status, 200);
    const limited = await post(url, validRequest, a);
    assert.equal(limited.status, 429);
    assert.equal(limited.headers.get("retry-after"), "60");
    assert.equal((await post(url, validRequest, b)).status, 200, "another install is unaffected");
    time = 60_001;
    assert.equal((await post(url, validRequest, a)).status, 200, "the window resets");
  });
});

test("keeps answers and provider errors out of logs", async () => {
  const lines: string[] = [];
  const failing: Provider = async () => { throw new Error(`upstream echoed: ${SECRET_TEXT}`); };
  await withServer({ log: (line) => lines.push(line), rateLimit: { max: 100, windowMs: 1000 } }, async (url) => {
    await post(url, validRequest);
  });
  await withServer({ provider: failing, log: (line) => lines.push(line) }, async (url) => {
    const response = await post(url, validRequest);
    assert.equal(response.status, 502);
    assert.ok(!(await response.text()).includes(SECRET_TEXT));
  });
  assert.ok(lines.some((line) => /^POST \/v1\/plans 200 \d+ms$/.test(line)));
  assert.ok(lines.every((line) => !line.includes(SECRET_TEXT) && !line.includes("Alex")), lines.join("\n"));
});

test("sends the provider key server-side and wraps answers as data", async () => {
  let seen: { url: string; auth: string; body: any } | undefined;
  const fetchImpl = (async (url: any, init: any) => {
    seen = { url: String(url), auth: init.headers.Authorization, body: JSON.parse(init.body) };
    return new Response(JSON.stringify({ choices: [{ message: { content: "```json\n" + JSON.stringify(await mockProvider(validRequest as never)) + "\n```" } }] }));
  }) as typeof fetch;
  const provider = chatProvider({ baseURL: "https://example.test/v1/", apiKey: "sk-test", model: "m", fetchImpl });
  planSchema.parse(await provider(validRequest as never));
  assert.equal(seen?.url, "https://example.test/v1/chat/completions");
  assert.equal(seen?.auth, "Bearer sk-test");
  assert.match(seen?.body.messages[1].content, /^<answers>[\s\S]*<\/answers>$/);
  assert.match(buildUserMessage(validRequest as never), /Days that work \(1=Sunday\): 2, 4, 6/);
});
