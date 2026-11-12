# Summa plan API

The single service the iOS app calls to draft a 90-day plan. Provider credentials stay here.

```sh
npm install
npm start        # http://localhost:8787, mock mode unless AI_API_KEY is set
npm test         # integration tests against a real HTTP server
```

`POST /v1/plans` takes the onboarding answers and returns a plan in schema version 1 (`src/schema.ts`,
mirrored by `PlanSchema` in `ios/SummaCore`).

- **Validation.** Requests are validated before generation. Model output is validated against the plan schema,
  retried once, and otherwise rejected with `502 invalid_plan`. Nothing unvalidated reaches the app.
- **Rate limiting.** Per install token (falls back to address). Defaults to 5 plans per 10 minutes. The limiter is
  in memory; move it to a shared store before running more than one instance.
- **Logging.** One line per request: method, path, status, duration. Bodies, answers, and provider error
  messages are never logged.
- **Providers.** Any OpenAI-compatible chat completions endpoint via `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL`
  (see `.env.example`). Without a key the service returns deterministic drafts.
- **Accounts.** None in this version, so there is no server-side persistence and no per-user records to isolate.
