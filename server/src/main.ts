import { providerFromEnv } from "./generate.js";
import { createPlanServer } from "./server.js";

// Load server/.env when present, so `npm start` never falls back to mock mode by accident.
try {
  process.loadEnvFile(new URL("../.env", import.meta.url));
} catch {
  // No .env file: environment variables come from the host, or the service runs in mock mode.
}

const { provider, mode } = providerFromEnv();
const port = Number(process.env.PORT ?? 8787);
const server = createPlanServer({
  provider,
  mode,
  rateLimit: {
    max: Number(process.env.RATE_LIMIT_MAX ?? 5),
    windowMs: Number(process.env.RATE_LIMIT_WINDOW_SECONDS ?? 600) * 1000,
  },
  log: (line) => console.log(line),
});

server.listen(port, () => {
  console.log(`Summa plan API listening on :${port} (${mode} mode)`);
  if (mode === "mock") console.log("No AI_API_KEY found: plans are canned mock drafts, not written by a model.");
});
