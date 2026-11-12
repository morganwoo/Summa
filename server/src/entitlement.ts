import { X509Certificate, verify as verifySignature } from "node:crypto";
import { readFileSync } from "node:fs";

/**
 * Decides whether a request comes from a Summa Pro customer.
 *
 * The app sends the signed App Store transaction that StoreKit gave it. This service checks the
 * signature and Apple's certificate chain itself, so a client that merely claims to be Pro gets nothing.
 */
export type Entitlement = "pro" | "free" | "unconfigured";
export type EntitlementCheck = (headers: Record<string, string | string[] | undefined>) => Entitlement;

export const PRO_PRODUCTS = new Set(["app.summa.pro.monthly", "app.summa.pro.annual", "app.summa.pro.lifetime"]);

// DER encodings of the Apple extension OIDs that mark a Mac App Store receipt signing leaf
// (1.2.840.113635.100.6.11.1) and the Apple Worldwide Developer Relations intermediate (…6.2.1).
const LEAF_OID = Buffer.from("060a2a864886f7636406 0b01".replace(/\s/g, ""), "hex");
const INTERMEDIATE_OID = Buffer.from("060a2a864886f76364060201", "hex");

export interface AppleConfig {
  roots: X509Certificate[];
  bundleId: string;
  /** Skip the certificate chain. Only for Xcode's local StoreKit testing, whose transactions Apple does not sign. */
  localTesting?: boolean;
}

interface TransactionPayload {
  bundleId?: string;
  productId?: string;
  expiresDate?: number;
  revocationDate?: number;
}

const decodePart = (part: string): unknown => JSON.parse(Buffer.from(part, "base64url").toString("utf8"));

function chainIsTrusted(x5c: unknown, roots: X509Certificate[], now: Date): X509Certificate | null {
  if (!Array.isArray(x5c) || x5c.length !== 3 || !x5c.every((entry) => typeof entry === "string")) return null;
  const [leaf, intermediate, root] = (x5c as string[]).map((entry) => new X509Certificate(Buffer.from(entry, "base64")));
  if (!leaf || !intermediate || !root) return null;
  for (const certificate of [leaf, intermediate, root]) {
    if (new Date(certificate.validFrom) > now || new Date(certificate.validTo) < now) return null;
  }
  if (!roots.some((trusted) => trusted.fingerprint256 === root.fingerprint256)) return null;
  if (!root.verify(root.publicKey) || !intermediate.verify(root.publicKey) || !leaf.verify(intermediate.publicKey)) return null;
  if (!intermediate.ca || !intermediate.raw.includes(INTERMEDIATE_OID) || !leaf.raw.includes(LEAF_OID)) return null;
  return leaf;
}

/** True only for a current, unrevoked Summa Pro transaction that verifies. Never throws. */
export function transactionIsPro(jws: string, config: AppleConfig, now: Date = new Date()): boolean {
  try {
    const parts = jws.split(".");
    if (parts.length !== 3 || jws.length > 16_000) return false;
    const [headerPart, payloadPart, signaturePart] = parts as [string, string, string];
    const header = decodePart(headerPart) as { alg?: string; x5c?: unknown };
    if (!config.localTesting) {
      if (header.alg !== "ES256") return false;
      const leaf = chainIsTrusted(header.x5c, config.roots, now);
      if (!leaf) return false;
      const signed = verifySignature("sha256", Buffer.from(`${headerPart}.${payloadPart}`),
        { key: leaf.publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signaturePart, "base64url"));
      if (!signed) return false;
    }
    const payload = decodePart(payloadPart) as TransactionPayload;
    if (payload.bundleId !== config.bundleId || !PRO_PRODUCTS.has(payload.productId ?? "")) return false;
    if (payload.revocationDate) return false;
    return !payload.expiresDate || payload.expiresDate > now.getTime();
  } catch {
    return false;
  }
}

function loadRoots(paths: string): X509Certificate[] {
  return paths.split(",").map((path) => path.trim()).filter(Boolean).map((path) => new X509Certificate(readFileSync(path)));
}

/**
 * APPLE_ENVIRONMENT=Xcode       local StoreKit testing: transactions are read but their chain is not checked,
 *                               and the debug header from a DEBUG app build is accepted. Never use in production.
 * APPLE_ENVIRONMENT=Sandbox or Production, with APPLE_BUNDLE_ID and APPLE_ROOT_CERT_FILE
 *                               (Apple Root CA - G3 from https://www.apple.com/certificateauthority/): full verification.
 * Unset                         Pro-only routes are refused, so a misconfigured server never gives Pro away.
 */
export function entitlementFromEnv(env: NodeJS.ProcessEnv = process.env): { check: EntitlementCheck; mode: string } {
  const environment = (env.APPLE_ENVIRONMENT ?? "").toLowerCase();
  const bundleId = env.APPLE_BUNDLE_ID ?? "app.summa.Summa";
  const header = (headers: Record<string, string | string[] | undefined>, name: string) => {
    const value = headers[name];
    return typeof value === "string" ? value : "";
  };
  if (environment === "xcode") {
    const config: AppleConfig = { roots: [], bundleId, localTesting: true };
    return {
      mode: "xcode-local-testing",
      check: (headers) =>
        header(headers, "x-summa-debug-pro") === "1" || transactionIsPro(header(headers, "x-summa-transaction"), config) ? "pro" : "free",
    };
  }
  if ((environment === "sandbox" || environment === "production") && env.APPLE_ROOT_CERT_FILE) {
    const config: AppleConfig = { roots: loadRoots(env.APPLE_ROOT_CERT_FILE), bundleId };
    return { mode: environment, check: (headers) => (transactionIsPro(header(headers, "x-summa-transaction"), config) ? "pro" : "free") };
  }
  return { mode: "unconfigured", check: () => "unconfigured" };
}
