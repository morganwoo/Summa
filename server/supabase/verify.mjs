#!/usr/bin/env node
// End-to-end check of Summa's accounts and friend requests against YOUR Supabase project.
//
//   cd server && node --env-file=.env supabase/verify.mjs
//
// Reads SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY from server/.env (git-ignored).
// The service-role key is used only here, on your machine, to create four throwaway confirmed test
// users and delete them afterwards. It is never needed by the app and must never be put in it.
//
// (Maintainers: VERIFY_LOCAL_JWT_SECRET + VERIFY_LOCAL_USER_IDS run the same checks against a bare
// PostgREST, minting tokens locally instead of using Supabase Auth.)
import { createHmac, randomBytes } from "node:crypto";

const url = (process.env.SUPABASE_URL ?? "").replace(/\/$/, "");
const anon = process.env.SUPABASE_ANON_KEY ?? "";
const service = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
const localSecret = process.env.VERIFY_LOCAL_JWT_SECRET;
const local = Boolean(localSecret);
const rest = local ? url : `${url}/rest/v1`;

const fail = (message) => { console.error(`\n✗ ${message}`); process.exitCode = 1; throw new Error(message); };
let passed = 0;
const ok = (label, condition, detail = "") => { if (!condition) fail(`${label} ${detail}`); passed += 1; console.log(`✓ ${label}`); };

const b64 = (value) => Buffer.from(typeof value === "string" ? value : JSON.stringify(value)).toString("base64url");
const mint = (claims) => {
  const body = `${b64({ alg: "HS256", typ: "JWT" })}.${b64({ exp: Math.floor(Date.now() / 1000) + 600, ...claims })}`;
  return `${body}.${createHmac("sha256", localSecret).update(body).digest("base64url")}`;
};
const roleOf = (key) => { try { return JSON.parse(Buffer.from(key.split(".")[1], "base64url").toString()).role; } catch { return undefined; } };

if (!url) fail("SUPABASE_URL is not set.");
if (!local) {
  if (!anon || !service) fail("Set SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY in server/.env.");
  if (anon === service || roleOf(anon) === "service_role" || anon.startsWith("sb_secret_")) fail("SUPABASE_ANON_KEY holds a secret key. Use the anon / publishable key there.");
}
const anonKey = local ? mint({ role: "anon" }) : anon;

async function call(token, path, { method = "POST", body, base = rest } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { "Content-Type": "application/json", apikey: anonKey, Authorization: `Bearer ${token ?? anonKey}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* not JSON */ }
  return { status: response.status, json };
}
const rpc = (token, name, args = {}) => call(token, `/rpc/${name}`, { body: args });

const tag = randomBytes(3).toString("hex");
const names = ["a", "b", "c", "d"].map((letter) => `sv${tag}_${letter}`);
const users = [];

try {
  // ---- accounts
  if (local) {
    for (const id of process.env.VERIFY_LOCAL_USER_IDS.split(",")) users.push({ id, token: mint({ role: "authenticated", sub: id }) });
  } else {
    const admin = { "Content-Type": "application/json", apikey: service, Authorization: `Bearer ${service}` };
    for (const name of names) {
      const email = `${name}@summa-verify.example.com`;
      const password = randomBytes(18).toString("base64url");
      const created = await fetch(`${url}/auth/v1/admin/users`, { method: "POST", headers: admin, body: JSON.stringify({ email, password, email_confirm: true }) });
      const createdJson = await created.json();
      if (!created.ok) fail(`Could not create a test user (${created.status}). Is the service-role key correct?`);
      const signIn = await call(null, "/auth/v1/token?grant_type=password", { body: { email, password }, base: url });
      if (signIn.status !== 200) fail(`Test user could not sign in (${signIn.status}). Is the Email provider enabled?`);
      users.push({ id: createdJson.id, token: signIn.json.access_token, refresh: signIn.json.refresh_token });
    }
    ok("four test accounts were created and signed in with the anon key", users.length === 4);
    const refreshed = await call(null, "/auth/v1/token?grant_type=refresh_token", { body: { refresh_token: users[0].refresh }, base: url });
    ok("a session can be refreshed (persistent sessions)", refreshed.status === 200 && Boolean(refreshed.json.access_token));
    users[0].token = refreshed.json.access_token;
  }
  const [A, B, C, D] = users;
  const today = new Date().toISOString().slice(0, 10);

  // ---- usernames
  for (const [index, user] of users.entries()) {
    const saved = await rpc(user.token, "set_profile", { p_username: names[index], p_plan_start: today, p_chapter: 1 });
    if (saved.status !== 200) fail(`set_profile failed (${saved.status} ${saved.json?.code ?? ""}). Has migration 0001 been applied?`);
  }
  ok("each account has a profile and username", true);
  const taken = await rpc(B.token, "set_profile", { p_username: names[0].toUpperCase(), p_plan_start: today, p_chapter: 1 });
  ok("a taken username is refused, ignoring case", taken.status === 409 && taken.json?.code === "23505", JSON.stringify(taken));
  const mine = await call(A.token, "/profiles?select=id,username", { method: "GET" });
  ok("an account can read its own profile, and only its own", mine.status === 200 && mine.json.length === 1 && mine.json[0].username === names[0], JSON.stringify(mine.json));

  // ---- search
  const found = await rpc(A.token, "search_users", { q: names[1].slice(0, 9) });
  ok("one account finds another by username", found.status === 200 && found.json.some((row) => row.user_id === B.id && row.username === names[1]), JSON.stringify(found));
  ok("search returns usernames and ids only", Object.keys(found.json[0]).sort().join() === "user_id,username");

  // ---- request and accept
  ok("a friend request is sent", (await rpc(A.token, "request_friend", { target: B.id })).status < 300);
  const incoming = await rpc(B.token, "friends_overview");
  ok("the recipient sees the incoming request", incoming.json.some((row) => row.user_id === A.id && row.relation === "incoming"), JSON.stringify(incoming));
  ok("the request is accepted", (await rpc(B.token, "respond_friend", { from_user: A.id, accept: true })).status < 300);
  const aSees = await rpc(A.token, "friends_overview");
  const bSees = await rpc(B.token, "friends_overview");
  ok("both accounts see the accepted friendship", aSees.json.some((r) => r.user_id === B.id && r.relation === "friend") && bSees.json.some((r) => r.user_id === A.id && r.relation === "friend"));

  // ---- free limit of two
  await rpc(A.token, "request_friend", { target: C.id });
  await rpc(C.token, "respond_friend", { from_user: A.id, accept: true });
  const status = await rpc(A.token, "my_social_status");
  ok("a free account holds two friends", status.json[0].friend_count === 2 && status.json[0].is_pro === false, JSON.stringify(status.json));
  const third = await rpc(A.token, "request_friend", { target: D.id });
  ok("a third request from a full free account is refused (SF001)", third.status >= 400 && third.json?.code === "SF001", JSON.stringify(third));
  await rpc(D.token, "request_friend", { target: A.id });
  const acceptThird = await rpc(A.token, "respond_friend", { from_user: D.id, accept: true });
  ok("accepting a third friend is refused (SF001)", acceptThird.status >= 400 && acceptThird.json?.code === "SF001", JSON.stringify(acceptThird));
  ok("declining still works at the limit", (await rpc(A.token, "respond_friend", { from_user: D.id, accept: false })).status < 300);
  const after = await rpc(A.token, "my_social_status");
  ok("existing friendships are intact", after.json[0].friend_count === 2);

  // ---- nobody can grant themselves Pro, and strangers see nothing
  const selfPro = await call(A.token, "/entitlements", { body: { user_id: A.id, is_pro: true } });
  ok("a client cannot write its own entitlement", selfPro.status >= 400, JSON.stringify(selfPro));
  const others = await call(D.token, "/friendships?select=*", { method: "GET" });
  ok("an account sees only friendships it is part of", others.status === 200 && others.json.every((row) => [row.requester, row.addressee].includes(D.id)));
  const signedOut = await rpc(null, "search_users", { q: names[0] });
  ok("signed-out callers are refused", signedOut.status === 401 || signedOut.status === 403 || signedOut.status === 404, JSON.stringify(signedOut));
  const signedOutRead = await call(null, "/profiles?select=username", { method: "GET" });
  ok("signed-out callers cannot read profiles", signedOutRead.status >= 400 || (Array.isArray(signedOutRead.json) && signedOutRead.json.length === 0), JSON.stringify(signedOutRead));

  // ---- remove
  ok("a friend can be removed", (await rpc(A.token, "remove_friend", { other: C.id })).status < 300);
  ok("the count follows the removal", (await rpc(A.token, "my_social_status")).json[0].friend_count === 1);
  console.log(`\nAll ${passed} checks passed against ${local ? "local PostgREST" : url}.`);
} finally {
  if (!local) {
    const admin = { apikey: service, Authorization: `Bearer ${service}` };
    for (const user of users) await fetch(`${url}/auth/v1/admin/users/${user.id}`, { method: "DELETE", headers: admin }).catch(() => {});
    console.log("Test accounts removed.");
  }
}
