# Quickstart: Running and Validating Crop Tracking

**Feature**: `001-crop-tracking` | **Plan**: [plan.md](./plan.md) | **Data model**: [data-model.md](./data-model.md) | **Contracts**: [contracts/](./contracts/)

How to run the app and prove the feature works end to end. Scenarios map to the spec's user stories and success criteria; details live in the linked artifacts rather than being repeated here.

## Prerequisites

| Need | Version |
|---|---|
| Flutter SDK | 3.x (includes Dart 3.x) |
| Android Studio | Ladybug or newer, SDK 35 |
| Xcode | 16+ — macOS only, required for the iOS target |
| Node.js | 22 (Lambda handlers) |
| Terraform | 1.11+ — earlier versions lack `use_lockfile` and will ask for a DynamoDB lock table |
| AWS CLI | v2, with a configured profile (`export AWS_PROFILE=basilmariano-dev` for the dev account) |
| Test devices | one physical Android 8.0+ phone **and** one physical iOS 15+ device — **both required**, see Scenario 5 |

> Simulators and emulators are fine for scenarios 1–4 and 9–11. Scenario 5 (offline reminders) must run on real hardware on **both** platforms: Android tests OEM background restriction, iOS tests the 64-notification ceiling (research.md R6). Neither risk reproduces on a simulator.

## Setup

```bash
export AWS_PROFILE=basilmariano-dev          # dev account

# One-off, per AWS account: the bucket that holds Terraform state.
# Its own state is local, because it cannot store state in itself.
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply

# Build the Lambda bundles BEFORE planning - Terraform hashes the zips,
# so a plan run against stale artifacts deploys stale code.
cd api && npm ci && ./build.sh

# Backend: table, REST API, Cognito pool, reference-data endpoint.
# The tf:* scripts follow the mr-billing house pattern and run from api/.
# ENV_NAME picks BOTH the tfvars file and the workspace, and defaults to dev.
# They only shell out to terraform, so npm run / pnpm / yarn are interchangeable.
pnpm tf:init
pnpm tf:plan          # read this before applying -- tf:apply replays it exactly
pnpm tf:apply

# Google sign-in is optional and needs its client secret to exist FIRST, under
# the name in main.tfvars. Without both google_* values the pool offers email and
# password only, through the same hosted UI, and the apply succeeds either way.

# Point the client at what was just deployed
cd ../app
cp env.example.json env.json         # fill from `(cd ../api && pnpm tf:output)`
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift codegen

flutter run --dart-define-from-file=env.json -d <android-device-id>
flutter run --dart-define-from-file=env.json -d <ios-device-id>

# Without --dart-define-from-file the app builds and runs guest-only, and says so
# on the sign-in screen. That is a supported configuration, not a broken one.
```

## Running the test suites

```bash
cd app

# Domain calculations — plain Dart, no Flutter, no device. Carries SC-009.
dart test test/domain

# Local store, outbox atomicity and ordering, sync, widgets
flutter test

# On-device journeys
flutter test integration_test --device-id <device-id>

# API handlers and contract tests against contracts/api.openapi.yaml
# Includes the REST-v1-vs-HTTP-v2 claims-path cases: these fail if the
# account id is ever derived from one gateway shape only (research.md R2).
cd ../api && npx vitest run

# Infrastructure: formatting, and a configuration that actually parses.
# `-backend=false` installs the providers and modules WITHOUT touching remote
# state, so this runs with no AWS credentials and in CI. Plain `validate`
# without it fails with "Module not installed", which reads like a broken
# configuration when it only means the directory was never initialised.
terraform -chdir=../terraform fmt -check -recursive
terraform -chdir=../api/terraform init -backend=false -input=false
terraform -chdir=../api/terraform validate
```

`dart test test/domain` is the suite to run most often — it holds every figure the farmer's decisions rest on, needs no device, and runs in seconds.

```bash
# Enforce the layering that makes the above possible (plan.md, Structure Decision)
! grep -rq "package:flutter" app/lib/domain/ && echo "domain layer is clean"
```

---

## Validation scenarios

### Scenario 1 — The bottom line (User Story 1, P1)

The core loop. Proves SC-003 and SC-009.

1. Launch, continue **as a guest**.
2. Add field "Field 1", area `2.5` ha.
3. Start a cropping: rice, any variety, transplanted, wet season, today's date.
4. Log expenses: `3,500` labor, `12,000` land preparation, `8,000` seeds.
5. Record a harvest: `100` sacks × `50` kg average wet.
6. Record a sale: `4,000` kg at `20.00`/kg, any buyer.

**Expected**

| Figure | Value |
|---|---|
| Total expenses | ₱23,500.00 |
| Revenue | ₱80,000.00 |
| Net profit | ₱56,500.00 |
| Yield | 5.00 tons (fresh weight) |
| Tons per hectare | 2.00 |
| Cost per kg produced | ₱4.70 |
| Remaining unsold | 1,000 kg |
| Result label | **Provisional** — not final |

Verify every number against a calculator. A disagreement of even one centavo means floating point has leaked into the domain layer (research.md R5).

### Scenario 2 — Post-harvest costs and closing (FR-012a, FR-031a, FR-042a)

Continuing from Scenario 1:

1. Log `4,000` hauling, dated 5 days after the harvest.
2. Confirm expenses become ₱27,500.00 and profit falls to ₱52,500.00, **still labelled provisional**.
3. Close the cropping.

**Expected**: a warning naming the 1,000 kg still unsold (FR-012c); after confirming, the result is marked **final** and further expenses and sales are rejected (FR-013).

### Scenario 3 — Two open croppings on one field (FR-008a, FR-031b)

The feature's sharpest correctness risk.

1. On the Scenario 1 cropping, record the harvest but **do not close it**.
2. Start a new cropping on Field 1 — this must be allowed (FR-008a), with a prompt to close the old one that can be declined (FR-008b).
3. Log an expense, choosing Field 1.

**Expected**: the app asks **which cropping** the expense belongs to and identifies each by crop, growing season, and planting date — never by field alone (FR-031c). Choosing wrongly must be possible only by the farmer's choice, never by a silent default.

### Scenario 4 — Fertilizer schedule and bag scaling (User Story 2, SC-004)

1. Open the Scenario 1 cropping's fertilizer schedule.
2. Find a step recommending `100` kg/ha of Urea 46-0-0.

**Expected**: `250 kg` and `5.0 bags` for the 2.5 ha field (FR-016), a due date of planting date + days after planting (FR-017), and the general-guidance statement visible (FR-026).

3. Mark the step done with a cost of `7,500`.

**Expected**: a single ₱7,500.00 expense appears in the **fertilizer** category — exactly once (SC-006). Edit the cost to `8,000` and confirm the expense follows and the total moves by ₱500, not ₱8,000 (FR-021).

### Scenario 5 — Offline reminders on real hardware (FR-019, SC-005)

**The riskiest requirement in the feature. Run on both platforms, on real devices. A simulator pass means nothing here.**

**Android**

1. Create a cropping with a schedule step due 2 days out.
2. Enable airplane mode.
3. Force-stop the app.
4. Advance the device clock to the reminder time.

**Expected**: the notification fires with no network and the app closed.

5. Reboot the device and repeat.

**Expected**: it still fires — `BOOT_COMPLETED` re-registration is working.

**iOS**

6. Repeat steps 1–4 on an iOS device.
7. Then create enough active croppings to generate **more than 64 pending reminders** across them.

**Expected**: reminders still arrive for the nearest-due applications. iOS caps pending local notifications at 64, so the app must schedule a rolling window and top it up during the daily reconciliation rather than registering a whole season at once (research.md R6). If the 65th cropping silently stops reminding, the rolling window is not implemented.

If any of this fails on target hardware, raise it rather than working around it: SC-005 depends on delivery neither platform fully guarantees, and the in-app overdue list (FR-018, FR-045) is the fallback that must then carry more weight.

### Scenario 6 — Offline-first sync (FR-053, SC-014)

1. Airplane mode on.
2. Add a field, a cropping, and three expenses.

**Expected**: every save completes instantly; the home screen shows a **pending** count (FR-053b).

3. Airplane mode off.

**Expected**: the pending count drains to zero and the state reads **up to date**. Confirm in DynamoDB that exactly one item exists per record — a duplicate means idempotency is broken (contracts/sync-protocol.md I3).

4. Kill the app mid-sync and relaunch.

**Expected**: pending entries survive and resume; nothing is lost or duplicated (FR-053d).

### Scenario 7 — Guest to account, and restore (FR-061, SC-016, SC-013)

1. As the guest from Scenario 1, create an account with Google Sign-In.

**Expected**: every guest record migrates into the account with nothing re-entered and no figure changing (SC-016).

2. Uninstall, reinstall, sign in again.

**Expected**: the full history returns — fields, croppings, schedules, expenses, harvest, sales (SC-013). Confirm cropping statuses are correct and pending alarms have been rescheduled (sync-protocol.md, Restore).

### Scenario 8 — Account isolation (FR-062)

**Security check. Must be automated in `api/tests/contract`, not only done by hand.**

1. Capture account A's JWT.
2. Call `GET /v1/snapshot` with A's token.
3. Attempt to read or write a record owned by account B — by id, by crafted body field, by any means available.

**Expected**: no request returns or modifies B's data under any circumstance. The account id comes only from the verified token claim (contracts/sync-protocol.md I5). This is the one failure whose consequence is another person's records rather than a wrong number.

### Scenario 9 — Wet and dry weight (FR-034c, FR-037a)

1. New cropping; harvest `5,000` kg wet.
2. Mark the cropping **sold dry**; record a dried weight of `4,200` kg.
3. Sell `4,000` kg.

**Expected**: remaining shows **200 kg dry** — not 1,000 kg. Yield stays 5.00 tons and cost per kg stays on the fresh-weight basis (FR-033, FR-040). Attempting a dry sale before the dried weight is recorded is refused.

### Scenario 10 — Status transition (FR-011a to FR-011c)

1. Create a cropping dated today → status **planted**.
2. Mark its first fertilizer application done → status **growing** immediately.
3. Create a second cropping dated 15 days ago → starts in **growing** (FR-011c).
4. Create a third, dated today, touch nothing, advance the clock 10 days → **growing** (FR-011a), and confirm it happens offline (FR-011b).

### Scenario 11 — A reference bundle update must not discard farmer edits (R9)

The failure most likely to destroy trust in the recommendations.

1. Open the fertilizer template for transplanted rice.
2. Change one step's rate from `100` kg/ha to `120` kg/ha — simulating the local agriculturist's advice (FR-024).
3. Start a new cropping and confirm its schedule uses `120` kg/ha.
4. Publish a newer reference bundle to the API that changes that same step to `90` kg/ha, and let the device pick it up.

**Expected**: the farmer's `120` kg/ha edit **survives** — a bundle update replaces only `SEED` and `PUBLISHED` rows, never `FARMER` ones (data-model.md, ReferenceBundle). The cropping started in step 3 is also unchanged, because its schedule is a snapshot (FR-025).

5. Confirm an unedited template picks up the new values, and that the source attribution shown to the farmer updates with it.

### Scenario 12 — Reference data reaches a guest (R10)

1. Launch as a guest with no account.
2. Start a cropping.

**Expected**: the fertilizer schedule is fully populated. `GET /v1/reference-data` is unauthenticated, so a farmer trialling the app gets correct recommendations rather than an empty schedule.

### Scenario 13 — Server-side restore drill (FR-053f, SC-019)

This is the only scenario that proves a backup exists rather than that a setting is enabled. Run it against **dev**, never production, and never against a table holding a real farmer's records.

1. Sign in on a test account and record a full cropping — field, expenses, harvest, sale — then wait for the sync indicator to read **All records backed up**.
2. Note the current time, then write down the cropping's net profit, tons per hectare and cost per kilogram.
3. Simulate server-side damage: overwrite one expense's amount and delete one sale directly in the table, as a faulty release would.
4. Restore the table to the timestamp from step 2 (point-in-time recovery), into a new table name.
5. Point the API at the restored table and re-read the account.

**Expected**: every cropping, expense, harvest and sale is present and byte-identical to step 2, and the three figures match what was written down. A restore that returns the records but changes a figure is a failure, not a partial pass.

**Also prove the second tier**: repeat steps 4–5 against a monthly recovery point rather than a PITR timestamp, which is the path that matters when the damage is found a season later and the 35-day window has already expired.

> **Half runnable now.** Dev is applied, so `dev-saka-crop-tracking` exists with PITR enabled and the first tier can be drilled today. The monthly tier cannot: the plan runs `cron(0 16 L * ? *)`, so the first recovery point is taken at 16:00 UTC on 30 Nov 2026 (midnight Manila, 1 Dec). Until then there is nothing to restore from, and steps 4-5 against a monthly recovery point stay blocked.

---

---

## Definition of done for this feature

- [ ] All twelve device scenarios pass on physical Android **and** iOS devices
- [ ] Scenario 13 passes as a real restore drill against dev — both tiers, with figures matching (SC-019)
- [ ] `dart test test/domain` covers every calculation in data-model.md, with figures verified by hand (SC-009)
- [ ] Scenario 8 is an automated contract test, not a manual check
- [ ] Scenario 5 passes on a low-end Android handset representative of the target users, and on iOS past the 64-notification ceiling
- [ ] No `double` appears anywhere in `lib/domain/` (SC-009, research.md R5)
- [ ] No `package:flutter` import appears anywhere in `lib/domain/` — enforced by lint, not convention
- [ ] **No Flutter web target is configured** — it would silently break integer money (research.md R1, R5)
- [ ] All farmer-facing strings are in ARB files, none in logic (FR-056, FR-057)
- [ ] The seed reference bundle carries real PhilRice / BPI values with source attribution per record, not placeholders (research.md R9)
- [ ] Sync retries have no maximum attempt count — the attempt counter only decides when to warn the farmer (FR-053g, research.md R12)
