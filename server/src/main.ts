import { providerFromEnv } from "./generate.js";
import { createPlanServer } from "./server.js";

const { provider, mode } = providerFromEnv();
const port = Number(process.env.PORT ?? 8787);
const server = createPlanServer({
  provider,
  rateLimit: {
    max: Number(process.env.RATE_LIMIT_MAX ?? 5),
    windowMs: Number(process.env.RATE_LIMIT_WINDOW_SECONDS ?? 600) * 1000,
  },
  log: (line) => console.log(line),
});

server.listen(port, () => {
  console.log(`Summa plan API listening on :${port} (${mode} mode)`);
});
