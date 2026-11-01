# Implementation Plan: Crop Tracking for Rice and Corn Farmers

**Branch**: `001-crop-tracking` | **Date**: 2026-11-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-crop-tracking/spec.md`

## Summary

A Philippine rice and corn farmer records every cropping on every field — what it cost, what it yielded, what it sold for — and gets back the three numbers the app exists to produce: net profit or loss, tons per hectare, and cost per kilogram produced. Along the way the app turns a per-hectare fertilizer recommendation into "buy this many 50 kg bags for this field" and reminds the farmer before each application is due.

Technical approach: a Flutter app for Android and iOS whose system of record on the device is a Drift (SQLite) database, so every save completes offline and instantly. Writes are mirrored into an append-only outbox that the app drains on launch and resume, in order and idempotently, to an HTTP API (API Gateway + Lambda) backed by DynamoDB — the durable copy that survives a lost phone. That infrastructure is provisioned by **Terraform**, laid out to match the house pattern (research.md R11). Identity comes from Cognito with Google Sign-In; guest mode runs entirely local and migrates into an account on sign-up. All money and weight arithmetic is integer-based, because the spec commits to figures that match the farmer's own calculator exactly.

Agronomic reference data — varieties and fertilizer templates — is versioned published data with a provenance trail, seeded in v1 from PhilRice and Bureau of Plant Industry guidance and updatable over the API without an app-store release. The CRM that lets those organizations maintain it directly is **feature 002**, not built here (research.md R9).

The one requirement that drove most of the platform decisions is FR-019: a reminder that fires with the app closed and the device offline. Flutter does not solve it — it is solved per platform underneath, and the risks are documented in research.md R6 rather than assumed away.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (client; domain layer is plain Dart with no Flutter import); TypeScript 5.x on Node.js 22 (Lambda handlers)

**Primary Dependencies**: `forui` (UI), `drift` + `sqlite3_flutter_libs` (local store), `flutter_local_notifications` + `timezone` (offline reminders), `dio` (HTTP), `flutter_riverpod` (state), `intl` (dates, and the phase-2 localisation seam), `uuid` (client-generated ids, which is what makes sync retries idempotent), `flutter_appauth` + `flutter_secure_storage` (Cognito hosted-UI sign-in, R4); Terraform (infrastructure, R11), AWS SDK v3 DynamoDB client (Lambda runtime-provided on nodejs22.x, so bundles exclude it)

> **Three dependencies this plan originally named are deliberately absent.** `workmanager` has no release compatible with Flutter 3.35, so there is no periodic background task; the outbox and the reminder schedule are reconciled on launch and on every resume instead (`ReminderLifecycleObserver`), and R6 records what that costs. `android_alarm_manager_plus` proved unnecessary — `flutter_local_notifications` schedules exact alarms and owns its own boot receiver. `amplify_auth_cognito` was not adopted: sign-in sits behind the `AuthSessionProvider` interface (R4) so guest mode, migration and restore stay testable without a network or an AWS account.

**Storage**: Drift/SQLite on device (system of record for the working copy); Amazon DynamoDB single table, account-partitioned (durable copy) — see [research.md](./research.md) R2, R7. Reference bundles are immutable, versioned, and public (R10). The durable copy is protected by point-in-time recovery for 35 days plus monthly copies retained 12 months (FR-053f, R12), and by two independent delete guards — `deletion_protection_enabled` and a `prevent_destroy` lifecycle block

**Testing**: `dart test` (domain), `drift` in-memory + `flutter_test` (local store), mocked HTTP client (sync), `integration_test` (journeys), Vitest + contract tests against the OpenAPI document (API) — see R8. Reminder *delivery* is verified on hardware, not in CI

**Target Platform**: Android 8.0 (API 26) and above, and iOS 15 and above. Phone form factor, portrait. **No web client** — see the constraint below.

**Project Type**: Cross-platform mobile app + serverless API

**Performance Goals**: cold start under 3 s on a low-end Android device; any list or result screen renders in under 300 ms from the local database; a save commits locally in under 100 ms (SC-002 allows 30 s for the whole logging interaction, so the constraint is interaction design, not compute)

**Constraints**:

- Every feature must work with no network connection (FR-050, FR-053, FR-065).
- Reminders must fire with the app closed and offline (FR-019), on both platforms. iOS caps pending local notifications at 64, so reminders are scheduled in a rolling window rather than a whole season at once (R6).
- No floating-point arithmetic anywhere in the domain layer (SC-009).
- **Flutter web must never be added without revisiting R5.** Dart's `int` is 64-bit on Android and iOS but double-backed on web, so compiling for web silently turns every peso amount into a float and breaks SC-009. This is a hard constraint, not a preference.
- App small enough to install and update over metered mobile data.
- All farmer-facing text externalised for phase 2 localisation (FR-056, FR-057).
- A reference bundle update must never overwrite a farmer's own template edits (R9, FR-024).
- **Sync retries must never give up** (FR-053g). The backoff is capped at six hours and runs indefinitely; the attempt count decides only when to warn the farmer. Introducing a maximum attempt count would turn a recoverable outage into data loss (R12).

**Scale/Scope**: one farmer per account; tens of fields, a few croppings per field per year, a few hundred records per cropping — thousands of small items per account over years. Roughly 12–15 screens. Scale is not a technical challenge here; correctness and offline reliability are.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Status: NOT EVALUATED — no constitution exists.**

`.specify/memory/constitution.md` is the unmodified Spec Kit template. Every principle, section, and governance rule is still a placeholder (`[PRINCIPLE_1_NAME]`, `[SECTION_2_CONTENT]`, and so on). There are therefore no gates to evaluate, and this plan passes no gate — it simply has none to pass. That is recorded here rather than marked as a pass, because a fabricated pass would be worse than an honest gap.

**Recommendation**: run `/speckit-constitution` before `/speckit-implement`. Three decisions in this plan are exactly the kind a constitution would normally govern, and would benefit from being ratified rather than assumed:

1. **Integer-only money and quantity arithmetic** (R5) — this directly carries SC-009 and should be a non-negotiable rule, not a convention a later contributor can quietly break with a `Double`.
2. **Domain layer free of Flutter dependencies** — what makes the calculations exhaustively testable without a device; worth stating as a structural rule, with the import lint as its enforcement.
3. **Account isolation enforced server-side from the verified token only** (R2, FR-062) — the one failure in this feature whose blast radius is another person's data.
4. **No Flutter web target** (R1, R5) — adding it silently converts every peso amount to a float and breaks SC-009. A constitution is the right place for a rule whose violation is invisible at review time.
5. **Sync retries never give up** (FR-053g, R12) — with no operator alerting by design, the only thing standing between a service outage and lost records is that the device keeps trying. A maximum attempt count would look like ordinary hygiene in review and would silently convert a recoverable outage into data loss.

**Re-check after Phase 1 design**: still not evaluable; unchanged for the same reason.

## Project Structure

### Documentation (this feature)

```text
specs/001-crop-tracking/
├── spec.md              # Feature specification (104 FRs, 19 SCs)
├── plan.md              # This file
├── research.md          # Phase 0 output — technical decisions and rationale
├── data-model.md        # Phase 1 output — entities, rules, state machine
├── quickstart.md        # Phase 1 output — how to run and validate
├── contracts/
│   ├── api.openapi.yaml # Sync + restore HTTP contract
│   └── sync-protocol.md # Outbox semantics, ordering, idempotency
├── checklists/
│   └── requirements.md  # Spec quality checklist (16/16)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
app/                                  # Flutter application
├── lib/
│   ├── domain/                       # PLAIN DART — no flutter/ import anywhere
│   │   ├── model/                    # entities, value types (Centavos, Grams, SquareMetres)
│   │   ├── calc/                     # yield, profit, cost per kg, bag scaling, due dates
│   │   └── rules/                    # status transitions, basis rules, validation
│   ├── data/
│   │   ├── local/                    # Drift tables, DAOs, migrations, outbox
│   │   ├── remote/                   # API client, DTOs
│   │   ├── sync/                     # outbox drain, retry, reconciliation
│   │   └── reference/                # bundle loader, provenance merge (R9)
│   ├── platform/
│   │   └── reminders/                # ReminderScheduler interface + Android/iOS impls
│   ├── ui/
│   │   ├── home/                     # FR-044 to FR-046b
│   │   ├── fields/                   # FR-001 to FR-005
│   │   ├── croppings/                # FR-006 to FR-013
│   │   ├── fertilizer/               # FR-014 to FR-026
│   │   ├── expenses/                 # FR-027 to FR-031c
│   │   ├── harvest/                  # FR-032 to FR-038b
│   │   ├── results/                  # FR-039 to FR-043
│   │   ├── account/                  # FR-058 to FR-067
│   │   └── common/
│   └── l10n/                         # ARB files — all farmer-facing text (FR-056)
├── assets/reference/
│   └── bundle-v1.json                # Seed varieties + templates, PhilRice/BPI sourced (R9)
├── test/                             # dart test + flutter_test
├── integration_test/                 # on-device journeys
├── android/                          # exact alarms, BOOT_COMPLETED receiver
└── ios/                              # UNUserNotificationCenter wiring

api/
├── src/
│   ├── handlers/                     # one Lambda per route
│   ├── lambda/                       # entry points, one bundle per function
│   ├── auth/                         # JWT claim → account id (the ONLY source of account id)
│   ├── store/                        # DynamoDB access, key construction
│   ├── reference/                    # bundle publishing + GET /v1/reference-data (R10)
│   ├── validation/                   # server-side record validation
│   └── docs/saka-api.json            # OpenAPI document API Gateway is BUILT FROM (not just described by)
├── terraform/                        # root module for this service: table, gateway, Cognito, 4 Lambdas
├── build.sh                          # esbuild → build/<fn>.zip, AWS SDK left external
└── tests/
    ├── unit/
    └── contract/                     # asserted against contracts/api.openapi.yaml

terraform/                            # shared infrastructure, house pattern (R11)
├── bootstrap/                        # the state bucket itself — local state, by necessity
├── environments/dev/
│   ├── backend.hcl                   # -backend-config: bucket, region, use_lockfile
│   └── main.tfvars                   # -var-file: account, region, tags, log retention
└── modules/
    ├── dynamodb/                     # PITR, SSE, deletion protection
    ├── lambda-function/
    ├── apigateway/                   # REST API v1, body from the OpenAPI document
    └── cognito/
```

**Structure Decision**: Cross-platform mobile + serverless API, with the Flutter app layered by directory and enforced by an import lint rather than by separate packages.

The layering is load-bearing, not ceremony. `domain/` must contain no `package:flutter` import, so every calculation behind SC-009 runs under plain `dart test` in milliseconds and cannot reach for a widget, a database, or the clock. `data/` owns both the local store and the sync machinery, keeping the outbox invariant — write and enqueue in one transaction — in one place where it can be enforced. `platform/reminders/` isolates the per-platform notification code, which is the most fragile part of the build (R6), behind a single Dart interface that the rest of the app and its tests see instead. `ui/` is widgets only.

A lint rule forbidding `package:flutter` inside `lib/domain/` is the cheapest way to keep that boundary real; without it, the separation is a convention that erodes on the first deadline.

`api/` stays thin: authenticate, validate, write to DynamoDB, read back, serve reference bundles. No calculation lives there that is not also in `domain/`, because the device must produce every figure offline — which makes the client the authority on calculation and the server the authority on ownership.

Two things about the infrastructure layout are load-bearing rather than arbitrary:

**`api/src/docs/saka-api.json` is the gateway, not documentation of it.** Terraform passes it through `templatefile` as the REST API's body, so routes, integrations and the Cognito authorizer exist because they are in that document. A route added to a Lambda but not to the document is unreachable; a route whose `security` is omitted inherits the authorizer, which is the safe direction to fail. `/v1/reference-data` carries an explicit `"security": []` because it is deliberately public (R10) — that empty array is the only thing making it so, and deleting it would break guests rather than expose anything.

**Environments are workspaces, not directories.** `dev` and any later environment share one root module and differ by `backend.hcl`, `main.tfvars` and a `terraform.workspace` name that prefixes every resource. The alternative — a directory per environment — duplicates the configuration and lets the copies drift apart, which is the failure mode where production differs from staging in a way nobody can see in a diff.

## Known gaps in the built system

Recorded here because each is a place where an artifact claims more than the code delivers. Found while refreshing this plan against the repository on 2026-11-01.

**Sign-in is implemented but has never run against a real pool.** `CognitoAuthSessionProvider` (R4) was written on 2026-11-02: hosted UI, authorization code + PKCE, session in secure storage, `main.dart` overriding both the auth provider and the API client from build-time configuration. What is proven and what is not:

- Proven in tests: the all-or-nothing configuration rule, and that an unconfigured build refuses to offer sign-in at all rather than letting the in-memory stub answer — which would have told a farmer they had an account while nothing left the phone.
- Proven against the deployed pool: the hosted UI answers 200 for the real client id and redirect URI, so `ph.saka.saka://callback` is accepted rather than rejected at the redirect — the failure mode that would otherwise surface only after a farmer had typed their password.
- Not proven: a single real token end to end. Nobody has signed in, so the code exchange, the refresh, and the API's acceptance of the resulting JWT are all unexercised. T167 closes this.
- FR-062 account isolation is enforced and tested **server-side** (`api/tests/contract/isolation.test.ts`), independent of any of the above.
- Task T132 predates this and should be read as "the screen is complete".

**FR-053f's monthly tier is deployed but has never produced a recovery point.** Applied to dev on 2026-11-02; AWS holds the plan at `cron(0 16 L * ? *)` and 370 days. The first copy is taken at the turn of the month, and no restore has been performed, so SC-019 is still unmet — a backup nobody has restored is a belief, not a backup (T165).

**The reference bundle ships placeholder agronomy** (T151, R9): every rate is `0` and `isPlaceholder` is `true`. The app says recommendations are unavailable rather than presenting invented figures, which is the right failure, but it is still a feature that cannot do its job until real PhilRice / BPI values land.

## Complexity Tracking

> No Constitution Check violations to justify — there is no constitution to violate (see Constitution Check above).

Two choices are nonetheless more complex than the simplest thing that could work, and are recorded here so a reviewer can challenge them:

| Choice | Why needed | Simpler alternative rejected because |
|---|---|---|
| API Gateway + Lambda in front of DynamoDB | FR-062 account isolation must be enforced from a verified token server-side | Writing to DynamoDB directly from the device is fewer moving parts, but makes every installed app a trusted actor and any authorization slip a direct data-exposure bug with no backstop (R2) |
| A `ReminderScheduler` interface over two platform implementations | FR-019 is met differently on each platform, and iOS adds a 64-notification ceiling Android does not have | Calling the notification plugin directly from the UI is less code, but spreads two sets of platform quirks across every screen that schedules a reminder, and makes the scheduling logic untestable without a device |
| Reference data as versioned bundles with provenance, rather than constants | A bundle update must not discard the farmer's own template edits (R9, FR-024), and corrected agronomy must reach phones that never update the app | Hardcoded constants are far simpler, but then fixing a wrong maturity figure requires an app-store release most of these farmers will never install |
| Import lint forbidding `package:flutter` in `lib/domain/` | Keeps the SC-009 calculations testable without a device and free of platform types | Trusting the convention costs nothing to set up, but the boundary silently erodes and the fast test suite goes with it |
| Terraform laid out as `bootstrap` + `environments` + `modules` + a per-service root module | Matches the house pattern (R11), so anyone who operates another service here can operate this one | A single `main.tf` is far less structure for one small service, but it has nowhere to put a second environment and nothing to share with the next service |
| Two restore tiers — PITR for 35 days *and* monthly copies for 12 months | FR-053f: server-side damage to a figure is typically found a season later, after a 35-day window has expired | PITR alone is one setting and the common stopping point; rejected because it only covers damage somebody notices quickly, which is not the damage that destroys a season's comparison |
| Two independent delete guards on the table (`deletion_protection_enabled` + `prevent_destroy`) | They fail differently: one stops Terraform planning a destroy, the other stops a deletion issued outside Terraform | Either guard alone is simpler and covers the likelier accident, but this is the one resource in the system whose loss is unrecoverable |

**Deliberately *less* machinery than the obvious design**, recorded here for the same reason — so a reviewer can challenge it:

| Omission | Why |
|---|---|
| No CloudWatch alarms, dashboards or dead-letter queue for sync failures | Decided 2026-11-01. A failed sync is self-healing: the record is committed on the device and retried indefinitely (FR-053g), so the backlog drains by itself when the service returns. The farmer is warned directly when their own backup is failing (FR-053c). The accepted exposure — a handset lost *during* an outage — is recorded in spec.md under Assumptions, not hidden |
