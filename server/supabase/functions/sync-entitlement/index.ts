// Supabase Edge Function: records Summa Pro for the signed-in user after verifying an App Store transaction.
// The app sends the signed transaction (JWS) that StoreKit gave it. Nothing the app says about being Pro is trusted:
// the signature is checked against Apple's certificate chain, and only this function (service role) writes `entitlements`.
//
// Deploy:   supabase functions deploy sync-entitlement
// Secrets:  supabase secrets set APPLE_BUNDLE_ID=app.summa.Summa APPLE_ENVIRONMENT=Sandbox APPLE_ROOT_CERTS_BASE64=<comma-separated base64 DER of Apple root CAs> [APPLE_APP_ID=<numeric id, Production only>]
// Root certificates: https://www.apple.com/certificateauthority/ (Apple Root CA - G3 at minimum).
import { createClient } from "npm:@supabase/supabase-js@2";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@1";

const PRODUCTS = new Set(["app.summa.pro.monthly", "app.summa.pro.annual", "app.summa.pro.lifetime"]);

Deno.serve(async (request) => {
  const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = request.headers.get("Authorization") ?? "";
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: authHeader } } });
  const { data: userData, error: userError } = await asUser.auth.getUser();
  if (userError || !userData.user) return json(401, { error: "not_signed_in" });

  let jws: string | null = null;
  try {
    jws = (await request.json()).transaction ?? null;
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const record = { user_id: userData.user.id, is_pro: false, product_id: null as string | null, expires_at: null as string | null, updated_at: new Date().toISOString() };

  if (jws) {
    try {
      const roots = (Deno.env.get("APPLE_ROOT_CERTS_BASE64") ?? "").split(",").filter(Boolean).map((b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
      const environment = Deno.env.get("APPLE_ENVIRONMENT") === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
      const appId = Deno.env.get("APPLE_APP_ID");
      const verifier = new SignedDataVerifier(roots as never, true, environment, Deno.env.get("APPLE_BUNDLE_ID")!, appId ? Number(appId) : undefined);
      const transaction = await verifier.verifyAndDecodeTransaction(jws);
      const expires = transaction.expiresDate ? new Date(transaction.expiresDate) : null;
      const active = PRODUCTS.has(transaction.productId ?? "") && !transaction.revocationDate && (!expires || expires > new Date());
      record.is_pro = active;
      record.product_id = transaction.productId ?? null;
      record.expires_at = expires ? expires.toISOString() : null;
    } catch {
      return json(400, { error: "transaction_not_verified" });
    }
  }
  // No transaction means "I have no entitlement": the row is set to free.
  const { error } = await admin.from("entitlements").upsert(record);
  if (error) return json(500, { error: "could_not_save" });
  return json(200, { is_pro: record.is_pro });
});
