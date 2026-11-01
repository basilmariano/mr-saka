# Saka

Crop tracking for Philippine rice and corn farmers. A farmer records every cropping
on every field and gets back the three numbers the app exists to produce: **net
profit or loss, tons per hectare, and cost per kilogram produced**.

Specification, plan and task list live in [specs/001-crop-tracking/](specs/001-crop-tracking/).

## Layout

```
app/        Flutter app (Android + iOS)
api/        Lambda handlers, the OpenAPI document the gateway is built from,
            and this service's Terraform root module
terraform/  Shared infrastructure: state bootstrap, per-environment config, modules
specs/      Spec Kit artifacts: spec, plan, research, data model, contracts, tasks
```

Inside `app/lib`:

| Directory | What belongs there |
|---|---|
| `domain/` | Entities, calculations, rules. **Plain Dart — no `package:flutter`.** |
| `data/` | Drift (SQLite) local store, outbox, sync, reference bundles |
| `platform/` | Per-platform notification scheduling |
| `ui/` | Forui screens |
| `l10n/` | ARB files — every farmer-facing string |

## Setup

```bash
cd app && flutter pub get && dart run build_runner build --delete-conflicting-outputs
```

```bash
cd api && npm ci
```

Copy `app/env.example.json` to `app/env.json` and fill it from the Terraform outputs
(`terraform -chdir=api/terraform output`), then build with
`flutter run --dart-define-from-file=env.json`.

The app runs without it: a guest's records are device-only by design, and the sign-in
screen says plainly that this build has no account service rather than offering buttons
the in-memory stub would answer. Build-time defines rather than a bundled `.env`,
because a declared asset must exist for the build to succeed — which would make the
"runs without configuration" promise true only for someone who had already created the
file it calls optional.

See `specs/001-crop-tracking/quickstart.md` for the full deploy sequence — the Lambda
bundles must be built before Terraform plans, because Terraform hashes the zips.

## Running the checks

```bash
cd app && dart test test/domain
```

The fastest and most important suite — every figure the farmer's decisions rest on,
no device needed.

```bash
cd app && flutter test
```

```bash
cd app && ./tool/check_all.sh
```

```bash
cd api && npx vitest run
```

On a device or simulator:

```bash
cd app && flutter test integration_test -d <device-id>
```

## Invariants a contributor must not break

Each has a guard in `app/tool/`, because all of them are invisible in a diff and
none would be caught by a passing test suite.

**Money and weights are integers.** `Centavos`, `Grams`, `SquareMetres` — never
`double`. SC-009 promises every figure matches the farmer's own calculator, and
binary floating point cannot represent 0.1, so a season of summed peso amounts
drifts. *Guard: `check_no_double.sh`.*

**No Flutter web target.** Dart's `int` is 64-bit on Android and iOS but a
JavaScript double on web. Compiling for web silently turns every peso amount into a
float. *Guard: `check_no_web_target.sh`.*

**`lib/domain/` imports no Flutter.** This is what keeps the calculations testable
in milliseconds with no device. *Guard: `check_domain_boundary.sh`.*

**Farmer-facing text lives in ARB files**, and **behaviour never branches on display
text**. v1 ships English; phase 2 adds a local language, and that must be
translation only. *Guards: `check_strings_externalised.sh`, `check_no_label_branching.sh`.*

**A write and its outbox append happen in one transaction.** `WriteThrough` is the
only path that should write a synced row — it makes "saved" and "queued" atomic, so
a crash between them cannot lose the farmer's entry.

**Harvest is always recorded fresh weight.** Yield and cost per kilogram sit on one
basis, which is the only reason croppings can be compared at all. Dry kilograms are
never subtracted from a wet harvest — `WeightBasisRules` throws rather than convert.

**The account comes only from the verified token.** `api/src/auth/account.ts` builds
the DynamoDB partition key from the JWT `sub` and nothing else. A request that names
an account is refused. This is the one failure whose blast radius is another person's
records; `api/tests/contract/isolation.test.ts` covers it.

**A published bundle never overwrites a farmer's edit.** Rows carry
`seed` / `published` / `farmer` provenance. A data refresh that discarded the advice
a farmer's agriculturist gave them is the failure most likely to destroy trust in the
recommendations.

## Platform floors

Android **API 26**, iOS **15**. Both are pinned in the build files, not just the
plan — notification channels arrive in API 26 and the reminder code assumes them.

## Known gaps

- `app/assets/reference/bundle-v1.json` ships **placeholder agronomy**: every rate is
  `0` and `isPlaceholder` is `true`. The app says "Recommended amounts are not yet
  available" rather than presenting invented figures as guidance. Real PhilRice /
  Bureau of Plant Industry values must land before a farmer uses this.
- **Android reminder delivery is verified on an emulator, not on real hardware.** The
  scheduling mechanism is now checked against the OS rather than the app's own books:
  `dumpsys alarm` shows an exact `RTC_WAKEUP` (`window=0`,
  `exactAllowReason=policy_permission`, so `USE_EXACT_ALARM` is being honoured and the
  alarm was not downgraded) aimed at the plugin's boot receiver at the right instant in
  `Asia/Manila`, and letting one fire posts the notification. What remains open is the
  part that actually threatens FR-019: OEM battery managers on low-end handsets can
  suppress even exact alarms, and an emulator has none, so it needs a physical handset
  of the kind the target farmers buy. See research.md R6.
- **There is no periodic background task.** No `workmanager` release is compatible
  with Flutter 3.35, so reminders are reconciled on app launch and on every resume
  instead (`ReminderLifecycleObserver`). Reboot re-registration is handled by
  `flutter_local_notifications`' own receiver and never depended on it. See
  research.md R6 for what this costs. Revisit if Flutter moves to 3.38+.

## Running the device tests

```
flutter test integration_test -d <android-device>   # 17 cases
flutter test integration_test -d <ios-device>       # 17 cases, see below
```

**On iOS the run stops on the notification prompt.** `flutter test` reinstalls the app
each time, so iOS asks for authorisation every run and sits there until someone taps
Allow. It is not a hang. Android needs no tap: `AlarmManager` arms an alarm whether or
not `POST_NOTIFICATIONS` is granted — the permission gates only *display*, which is
precisely why a denied permission on Android is invisible from inside the app and why
the settings screen asks the platform directly (FR-019a).
