# Summa for iOS

A native iPhone app for 90 days of Stoic practice. Swift, SwiftUI, SwiftData, WidgetKit.

## Run it

Requires Xcode 16 or later (the project uses folder-synchronized groups) and an iOS 17+ simulator or device.

1. Open `ios/Summa.xcodeproj`.
2. Select the **Summa** scheme and an iPhone simulator.
3. Press **Run**.

No credentials are needed. With `SUMMA_API_BASE_URL` empty (the default), plans are drafted on device, so you can
complete onboarding, review and edit a plan, start it, check in, and see progress.

To run on a physical device, set your team under *Signing & Capabilities* for the `Summa` and
`SummaWidgetExtension` targets. Both use the app group `group.app.summa.Summa`; change it in
`Config/*.entitlements` and `WidgetSnapshot.appGroup` if you use a different bundle ID.

### Use the plan API instead of on-device drafts

```sh
cd server && npm install && npm start      # mock mode unless AI_API_KEY is set; see server/.env.example
```

Then set the `SUMMA_API_BASE_URL` build setting (project level) to `http://localhost:8787` and run in the simulator.

### Launch arguments

| Argument | Effect |
| --- | --- |
| `-simulateGenerationFailure` | The first plan request fails, to exercise retry and the editable starter plan. |
| `-uiTesting` | In-memory store, no speech or notification prompts, short generation steps. |
| `-persist` | With `-uiTesting`, use the on-disk store. |
| `-resetState` | Erase the saved plan and onboarding answers at launch. |

## Summa Pro (StoreKit 2)

Product IDs: `app.summa.pro.monthly` (7.99), `app.summa.pro.annual` (36.99), `app.summa.pro.lifetime` (89.99).
The Summa scheme runs with `Config/Summa.storekit`, so purchases, restores, renewals, and refunds can be tested
locally in the simulator (Xcode: Debug > StoreKit > Manage Transactions). To sell in the App Store, create the same
three product IDs in App Store Connect (one subscription group for monthly and annual, one non-consumable), sign the
Paid Applications agreement, add a privacy policy URL, and enable the App Groups capability for both targets.

Free: three active habits, one reminder. Pro: unlimited habits, a reminder for every habit plus a second time each,
and home-screen widgets. Entitlement comes only from verified transactions (`Services/Store.swift`).

## Friends (Supabase)

Friends needs a Supabase project. Without one the tab says it is not connected, and everything else works.

1. Create a Supabase project and run `server/supabase/schema.sql` in its SQL editor.
2. In Authentication, enable the Email provider with one-time codes (include `{{ .Token }}` in the email template).
3. Deploy `server/supabase/functions/sync-entitlement` and set its secrets (see the comment at the top of that file).
4. Set the build settings `SUPABASE_URL` and `SUPABASE_ANON_KEY` on the Summa project. Use the anon key only;
   the service-role key must never be in the app.

`server/supabase/test.sql` checks the access rules against a local PostgreSQL.

## Tests

- **Schedule and metric rules** (Swift Testing): `SummaCore/Tests`. Run with the Summa scheme's Test action,
  or `cd ios/SummaCore && swift test` on a Mac.
- **First run and daily check-in** (XCUITest): `SummaUITests`, also in the Summa scheme.
- **Plan API** (integration): `cd server && npm test`.
- `scripts/linux-core-tests.sh` runs the SummaCore suites on a Linux Swift toolchain that predates Swift Testing.

## How it is put together

```
ios/
  SummaCore/        Foundation-only package: days, schedules, streaks, completion, plan schema, starter plans
  Summa/            The app
    App/            Entry point and routing between onboarding and the daily app
    Models/         SwiftData models and PlanStore (the one place that writes)
    Onboarding/     Welcome, the two paths, generation, plan review, habit editor
    Main/           Heatmaps, Progress, Plan, Settings
    Services/       Plan API client, Keychain, dictation, reminders, onboarding persistence
    Theme/          Black Marble and White Marble, type, shared components
  SummaWidget/      Home-screen widget: today's habits (small) or the week (medium)
  SummaUITests/
  Config/           Info.plist additions and entitlements
server/             TypeScript plan API (the only place a model provider is called)
```

### Counting rules

These live in `SummaCore/Sources/SummaCore/Metrics.swift` and are explained in the app under
*Progress → How this is counted*.

- A day is a civil date (`DayKey`, `yyyy-MM-dd`), fixed when the check-in is made. Time-zone travel and
  daylight-saving changes cannot move a past check-in.
- A streak counts scheduled occurrences completed in a row. Rest days never break it.
- Today is pending until the day ends: it cannot break a streak, and it extends the streak once completed.
- Completion = completed scheduled days ÷ scheduled days from the start of the period through today or the end
  of the period, whichever is first. Today counts as scheduled.
- Editing a schedule adds a new version effective that day; earlier days keep the schedule they were lived under.
- One check-in per habit per day, enforced by a unique key, so duplicate writes are harmless.

### Privacy

- Plans, habits, schedules, and check-ins are stored on device with SwiftData and work offline.
- Dictation uses Apple's Speech framework (on-device when the device supports it). Audio is never written to disk.
- Onboarding answers are kept in a protected file until the plan starts, then deleted.
- The plan request carries only the answers; the referral code and UI state stay on device. The server does not
  log request or response bodies.
- There are no accounts in this version. The only identifier is a random install token in the Keychain, used by
  the API for rate limiting.

## Regenerating the Xcode project

Source files are picked up automatically. If you add a target or change build settings and prefer to keep the
project scripted, edit and run `python3 scripts/generate-xcodeproj.py`.

## Fonts and imagery

Cormorant Garamond and Cinzel are bundled under the SIL Open Font License (see `Summa/Resources/Fonts`).
The sculpture images come from the Summa website's assets.
