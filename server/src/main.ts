import { providerFromEnv } from "./generate.js";
import { createPlanServer } from "./server.js";
import { companionFromEnv } from "./reflect.js";
import { entitlementFromEnv } from "./entitlement.js";

// Load server/.env when present, so `npm start` never falls back to mock mode by accident.
try {
  process.loadEnvFile(new URL("../.env", import.meta.url));
} catch {
  // No .env file: environment variables come from the host, or the service runs in mock mode.
}

const { provider, mode } = providerFromEnv();
const entitlement = entitlementFromEnv();
const port = Number(process.env.PORT ?? 8787);
const server = createPlanServer({
  provider,
  mode,
  companion: companionFromEnv(),
  entitlement: entitlement.check,
  companionLimit: { max: Number(process.env.COMPANION_DAILY_MAX ?? 40), windowMs: 24 * 60 * 60 * 1000 },
  rateLimit: {
    max: Number(process.env.RATE_LIMIT_MAX ?? 5),
    windowMs: Number(process.env.RATE_LIMIT_WINDOW_SECONDS ?? 600) * 1000,
  },
  log: (line) => console.log(line),
});

server.listen(port, () => {
  console.log(`Summa plan API listening on :${port} (${mode} mode)`);
  console.log(`Reflection companion (Summa Pro): entitlement check is ${entitlement.mode}`);
  if (entitlement.mode === "unconfigured") console.log("Set APPLE_ENVIRONMENT (Xcode for local testing) to enable /v1/reflections/chat.");
  if (entitlement.mode === "xcode-local-testing") console.log("Local testing mode: App Store signatures are NOT verified. Never deploy with APPLE_ENVIRONMENT=Xcode.");
  if (mode === "mock") console.log("No AI_API_KEY found: plans are canned mock drafts, not written by a model.");
});
