# Phase 0 Research: Crop Tracking for Rice and Corn Farmers

**Feature**: `001-crop-tracking` | **Date**: 2026-11-01 | **Spec**: [spec.md](./spec.md)

Every unknown in the plan's Technical Context is resolved below. Decisions marked **(farmer's choice)** came from the clarification sessions and are recorded, not re-litigated. Decisions marked **(proposed)** are mine and should be confirmed before `/speckit-tasks` — each one notes what would change if it were overturned.

---

## R1. Target platform — Flutter, Android and iOS

**Decision (farmer's choice, 2026-11-01)**: Flutter 3.x / Dart 3.x, one codebase delivering both Android (API 26+) and iOS (15+). **This reverses the Android-only native recommendation previously recorded here**; that decision and its reasoning are preserved below under "Superseded" so the trade-off being accepted stays visible.

**Rationale**:

- Both platforms ship from one codebase, so iOS is not a second project. Given a feature this size, that is the dominant cost consideration.
- The domain layer — every calculation behind SC-009 — becomes plain Dart with no platform dependency, and runs in a fast `dart test` suite on either developer machine.
- Flutter's Material widgets cover every screen this feature needs; nothing here requires a platform-specific UI idiom.

**What this costs, stated plainly**:

- The hardest requirement in the spec (FR-019: a reminder that fires with the app closed and the device offline) is **not** solved by Flutter. It is solved per platform underneath it, via `flutter_local_notifications` + `android_alarm_manager_plus` on Android and `UNUserNotificationCenter` on iOS. The Android reliability risk in R6 is unchanged, and iOS adds its own limits.
- Runtime size grows relative to a native build, which matters for farmers installing over metered data.
- Platform-channel work is still required for alarm scheduling, so the plugin boundary is a place bugs can hide. R6 and R8 account for this.

**Superseded (for the record)**: Android-only native Kotlin was recommended because Android dominates among Philippine smallholder farmers, native `AlarmManager` is the most reliable path to FR-019, and APK size is smallest. That reasoning still holds on its own terms — it was outweighed by wanting iOS from day one.

> **Correctness constraint created by this choice**: Dart's `int` is 64-bit on Android and iOS, but is JavaScript's double-backed number on **Flutter web**. The integer money and weight representation in R5 is therefore only safe on the mobile targets. **Flutter web must not be added without revisiting R5**, or every peso amount silently becomes a float and SC-009 breaks. This is recorded as a constraint in plan.md.

## R2. Remote storage — DynamoDB behind an API, not direct from the device

**Decision**: Amazon DynamoDB **(farmer's choice)**, reached through Amazon API Gateway + AWS Lambda. The client never talks to DynamoDB directly and never holds AWS credentials.

**Superseded detail (2026-11-01)**: this section originally specified API Gateway **HTTP API (v2)**. The build uses **REST API (v1)**, to match the house infrastructure pattern (R11), which defines the gateway from an OpenAPI document with `x-amazon-apigateway-integration`. The difference is not cosmetic and is recorded because it already caused a defect: a v1 Cognito authorizer puts the verified claims at `requestContext.authorizer.claims`, while v2 puts them at `requestContext.authorizer.jwt.claims`. Code written against the v2 shape derives no `sub`, and every authenticated request 401s. `api/src/auth/account.ts` now reads both shapes, and `api/tests/contract/isolation.test.ts` fails if either is dropped.

**Rationale**:

- FR-062 requires that one account's records are unreadable and unwritable by any other. The only trustworthy way to enforce that is server-side: the Lambda derives the owning account from the verified JWT and builds the partition key from it, **never** from anything in the request body. A client that writes to DynamoDB directly must be trusted to address only its own partition, and a tampered client is not trustworthy.
- An API boundary lets the DynamoDB key design change without shipping a new APK — important because the app must keep working on phones that are never updated.
- Server-side validation gives one place to reject impossible records (negative area, sale exceeding remaining, wet/dry basis mismatches) rather than trusting every client version ever installed.

**Alternatives considered**:

| Alternative | Why rejected |
|---|---|
| Device → DynamoDB directly via Cognito Identity Pool credentials | Workable, and IAM policy variables can scope access per identity. Rejected because it hard-couples the table's key schema to every installed APK version, and any authorization mistake is a direct data-exposure bug with no server-side backstop. |
| AWS Amplify DataStore / AppSync | Genuinely attractive — it ships offline sync and conflict resolution out of the box, which is most of R3. Rejected for v1 because its conflict model solves a problem this feature does not have (one farmer, one device, no concurrent editors), while coupling the domain model to a GraphQL schema and making the money and yield calculations harder to unit-test in isolation. Reconsider if multi-device editing ever enters scope. |
| RDS / Aurora Serverless | A relational store fits this model better on the merits. Rejected because the farmer chose DynamoDB; the access patterns here are narrow enough (R7) that the choice is not harmful. |

---

## R3. Offline-first sync — local SQLite plus an append-only outbox

**Decision (proposed)**: Drift (SQLite) is the system of record on the device. Every write goes to Drift inside a transaction that also appends to an `outbox` table. A `workmanager` background task drains the outbox to the API in insertion order.

**Rationale**:

- FR-053 says a save must complete locally with no network and must never be rejected for being offline. Writing the record and the outbox row in one Drift transaction makes "saved" and "queued to sync" atomic, so a crash between them cannot lose the entry or queue a write that was never applied.
- Drift rather than raw `sqflite` because it gives compile-time-checked queries and typed row classes, which matters when the schema carries money and weight types that must not be accidentally widened to `double`.
- FR-053e requires changes to reach remote storage in the order the farmer made them. A monotonically increasing outbox sequence, drained strictly in order and halting on a hard failure, delivers that. Out-of-order draining would let a stale value overwrite a correction.
- FR-053d requires pending entries to survive app and device restarts — the SQLite file and the registered background task both persist across restart and reboot. On iOS, background execution is more constrained, so the drain also runs on app foreground; a pending entry is never lost, it may simply sync later.
- Each outbox entry carries a client-generated UUID that is also the record's primary key, so a retry after an ambiguous network failure is idempotent on the server (`PutItem` on the same key). Without this, a timeout that actually succeeded would create a duplicate expense and silently corrupt the totals the whole app exists to produce.
- Sync is effectively one-way (device → cloud) except at sign-in on a new device, which is a full download. The spec's single-farmer, single-device model (FR-048) means no merge is required; last write wins and that is correct here.

**Alternatives considered**: a "sync on app close" or timer-based push (rejected — leaves a longer window where records exist only on a phone that may be lost, and FR-053b asks the farmer to be told what is unprotected); bidirectional delta sync with vector clocks (rejected — solves concurrent multi-device editing, which is explicitly out of scope).

**Known limitation, already in the spec**: entries still in the outbox when a device is lost are unrecoverable. The spec acknowledges this ("Device lost before entries sync") and FR-053b requires the pending count to be visible so the farmer is never falsely reassured.

---

## R4. Authentication — Cognito User Pools, Google Sign-In first

**Decision (proposed)**: Amazon Cognito User Pools. Google Sign-In as the primary method, email + password as a fallback. Guest mode holds no Cognito identity at all.

**Rationale**:

- FR-058 needs an identity that the API can verify; Cognito issues a JWT that API Gateway validates before Lambda runs, giving R2's server-side isolation with no custom auth code.
- Google Sign-In is the right default for this audience: every Android phone is already signed into a Google account, so sign-up is two taps with nothing to remember. It also satisfies FR-066 (recovery) for free — Google owns the recovery flow, and a farmer who forgets a password never loses a season of records.
- Email + password is kept as a fallback for farmers without a usable Google account, with Cognito's standard reset flow.
- **Phone/SMS OTP was considered and deliberately not chosen for v1**, despite fitting the audience: it carries a per-message cost that scales with sign-ins and password resets, and SMS delivery to Philippine networks is not reliable enough to be the only way into an account holding several seasons of records. Worth revisiting in phase 2 alongside the local-language work.
- Guest mode (FR-059, FR-060): no identity, no API calls, local Drift database only. On sign-up, FR-061 is satisfied by assigning the new account id to every existing local row and enqueueing all of them to the outbox — the records are already keyed by client-generated UUIDs, so nothing is rewritten or re-entered.

**How it is built (settled 2026-11-02)**: Cognito's **hosted UI** over authorization-code + PKCE, driven by `flutter_appauth`, with the session in `flutter_secure_storage`. Chosen over `amplify_auth_cognito`, which pulls the Amplify runtime and its own config format into a codebase that has neither, and over hand-rolled SRP, which would mean owning the crypto on the one path protecting a farmer's records.

Three consequences worth stating, because each one removed code or a risk:

- **This app never sees a password.** Credentials are typed on Cognito's page, so the sign-in screen has no email or password field and no bug in it can leak one. Google and email/password are the same flow — `preferGoogle` only adds `identity_provider=Google` to skip the chooser.
- **The hosted UI is not a Google feature.** The Terraform originally created the domain and enabled the OAuth flows only when Google was fully configured, which would have left email/password sign-in with nowhere to redirect. Domain and OAuth are now gated on `cognito_domain_prefix` alone; Google adds the identity provider on top.
- **FR-066 needs no code.** The forgotten-password route lives on the hosted page, so the app no longer carries a recovery screen or its strings.

**FR-065 shaped the implementation more than the choice did.** The session lives in secure storage and is read with no network call; an expired access token postpones a sync rather than ending a session; a failed refresh keeps the session. Only an explicit sign-out ends one. A farmer deep in a field must not be locked out of their own records.

**If overturned**: switching to phone OTP changes the Cognito configuration and the sign-in screen only. The account-id plumbing, API contract, and migration path are unaffected.

---

## R5. Money and quantity representation — integers, never floating point

**Decision (proposed)**: money is stored and computed as `Long` **centavos**; weights as `Long` **grams**. Floating point appears nowhere in the domain layer. Area in hectares is stored as `Long` in square metres (1 ha = 10,000 m²).

**Rationale**:

- SC-009 commits that every figure matches the farmer's own hand calculation, for 100% of croppings. Binary floating point cannot represent 0.1 exactly, so repeated addition of peso amounts drifts; a season of expenses summed as `Double` will eventually disagree with the farmer's calculator by a centavo, and the farmer will be right.
- Derived figures (cost per kilogram, tons per hectare, category share of total) are computed from integers with explicit rounding applied only at the display boundary, and the rounding rule is stated once in the domain layer rather than scattered through the UI.
- Grams rather than kilograms because FR-032 allows an average kg per sack that is not a whole number; grams keep that exact without decimals.
- Square metres rather than hectares for the same reason — FR-001 allows 2.5 ha, and FR-016 multiplies area by a per-hectare rate, so an exact area keeps the bag count exact.

**Alternatives considered**: `BigDecimal` (correct, but heavier on low-end devices and easy to misuse by constructing from a `Double`); storing pesos as `Double` (rejected — directly threatens SC-009).

---

## R6. Offline reminders — per-platform scheduling behind one Dart interface

**Decision (proposed)**: one `ReminderScheduler` interface in Dart, implemented per platform.

| Platform | Mechanism |
|---|---|
| Android | `flutter_local_notifications` zoned schedule with `AndroidScheduleMode.exactAllowWhileIdle`, re-registered on boot by the plugin's own `ScheduledNotificationBootReceiver` |
| iOS | `UNUserNotificationCenter` local notifications, scheduled at the calendar trigger |

A daily background task reconciles scheduled notifications against the schedule rows in Drift as a safety net on both platforms.

**Superseded during implementation**: the daily WorkManager job was dropped. No published `workmanager` release works with Flutter 3.35 — 0.9.3+ requires Flutter 3.38, 0.9.2 ships a federated split whose iOS package does not implement its own platform interface, and 0.5.2 uses the v1 plugin embedding Flutter has removed. Upgrading Flutter mid-project to keep one background job was the worse trade.

The two risks this section names are covered without it. **Reboot**: `flutter_local_notifications` re-registers its own scheduled notifications through `ScheduledNotificationBootReceiver`, which never depended on WorkManager. **Force-stop and OEM battery managers**: alarms are reinstalled whenever the app runs — on launch and now on every resume (`ReminderLifecycleObserver`).

What is genuinely lost is topping up the iOS 48-reminder rolling window for a farmer who does not open the app for weeks. Reconciling on resume covers more real usage than a background job that, on the low-end handsets this section is worried about, the OS is likely to decline anyway.

**Corrected during implementation**: `android_alarm_manager_plus` was named here originally and turned out to be unnecessary. `flutter_local_notifications` already schedules exact alarms via `AlarmManager.setExactAndAllowWhileIdle` and ships the boot receiver that re-registers them. Adding it would have meant a second alarm registry to keep in sync with `replaceAll`, for no extra capability.

**Rationale**:

- FR-019 requires delivery with the app closed and offline, so the trigger must be local. Nothing server-side (push, SMS) satisfies it — which is why this requirement, not the UI, has driven the platform decisions throughout.
- Android loses exact alarms across reboot, so `BOOT_COMPLETED` re-registration is mandatory. Without it, a farmer who restarts their phone silently stops being reminded and nothing reports an error.
- The daily reconciliation exists because alarms are also lost to force-stop and to OEM battery managers.

**Risks, flagged rather than hidden**:

- **Android**: several OEMs popular in the Philippines aggressively suppress background work, including exact alarms, on exactly the low-end handsets this audience buys. Mitigations: request the exact-alarm permission explicitly, prompt once for battery-optimisation exemption, and keep the in-app overdue list (FR-018) and home screen (FR-045) as the surface that always works.
- **iOS**: a hard ceiling of 64 pending local notifications per app. A farmer with several active croppings, each with a multi-step schedule and two reminders per step (2 days before and on the day, FR-019), can approach that. **Mitigation: schedule only the next N reminders per cropping and top up during the daily reconciliation**, rather than registering the whole season at once. This is a real constraint introduced by adding iOS, and it must be designed for, not discovered in testing.

SC-005 (90% of applications actioned within 3 days of due) depends on delivery neither platform fully guarantees. **Measure on real target hardware early.**

**Verified on an Android emulator (API 36), 2026-11-01.** Until this point every claim in
this section rested on documentation; none of the scheduling code had ever run on Android.
Scheduling a reminder and reading Android's own `dumpsys alarm` shows:

```
RTC_WAKEUP #39: Alarm{80afc44 type 0 origWhen 1793919600000 ... ph.saka.saka}
  tag=*walarm*:ph.saka.saka/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
  type=RTC_WAKEUP origWhen=2026-11-06 07:00:00.000 window=0 exactAllowReason=policy_permission
  policyWhenElapsed: ... device_idle=-- battery_saver=-49s401ms
```

`exactAllowReason=policy_permission` is the OS confirming it honoured the `USE_EXACT_ALARM`
manifest entry: the alarm is genuinely exact (`window=0`), not quietly downgraded to inexact,
which is the failure the app itself could never have detected. `origWhen` also confirms
`Asia/Manila` and the 07:00 rule survived the round trip into the platform. Letting one fire
produced the notification:

```
NotificationRecord(pkg=ph.saka.saka id=424242 importance=4
  Notification(channel=fertilizer_reminders ...))
android.title=String (Urea 46-0-0 due)   android.text=String (Field 1 - 5.0 bags)
```

**What this did NOT settle**: the OEM battery-manager risk above. An emulator has no Xiaomi or
Oppo power manager, so the one risk this section calls out as most likely to break FR-019 in
the field remains open and still needs a physical low-end handset (T153).

**A platform difference found in the process, which the design had assumed away**: the two
platforms disagree about what an unauthorised app may schedule. Android's `AlarmManager` arms
the alarm whether or not `POST_NOTIFICATIONS` is granted — the permission gates only display,
so a denied permission produces an armed alarm, a receiver that runs, and a post that is
discarded with no error, no retry and no trace. iOS registers nothing at all while
unauthorised. The Android case is the dangerous one, because nothing in the app can see it;
it is why `ReminderScheduler.notificationsEnabled()` exists and why the settings screen asks
the platform rather than trusting the answer the farmer gave when prompted (FR-019a).

## R7. DynamoDB key design — single table, account-partitioned

**Decision (proposed)**: one table, `crop_tracking`. Partition key `PK = ACCOUNT#<cognito_sub>`, sort key `SK` identifying the entity.

| Entity | SK |
|---|---|
| Field | `FIELD#<fieldId>` |
| Cropping | `CROP#<croppingId>` |
| Scheduled application | `CROP#<croppingId>#APP#<applicationId>` |
| Expense | `CROP#<croppingId>#EXP#<expenseId>` |
| Harvest | `CROP#<croppingId>#HARVEST` |
| Sale | `CROP#<croppingId>#SALE#<saleId>` |
| Fertilizer template (farmer's edits) | `TEMPLATE#<crop>#<method>` |
| Custom variety | `VARIETY#<varietyId>` |

**Rationale**:

- Every access pattern this feature needs is satisfied without a secondary index: full download on sign-in is one `Query` on `PK`; everything belonging to one cropping is one `Query` with `begins_with(SK, "CROP#<id>")`; a single record is a `GetItem`.
- Account-scoped partitioning makes FR-062 structural rather than procedural — a request cannot reach another account's data, because the partition key is built from the verified token and the token is the only source of the account id.
- Per-partition size stays trivial: a farmer with a handful of fields over several seasons generates thousands of small items, far inside DynamoDB's 10 GB partition limit.
- On-demand capacity, because usage is spiky (a burst when a farmer comes back into signal after a week offline) and far too low to justify provisioned throughput.

**Note on reporting**: comparison across croppings (FR-043) is computed on the device from the local Drift copy, not by scanning DynamoDB. The device already holds the farmer's whole history, so the comparison works offline and costs nothing.

---

## R8. Testing strategy

**Decision (proposed)**:

| Layer | Tooling | What it must cover |
|---|---|---|
| Domain (pure Dart, no Flutter) | `dart test` | Every calculation in FR-033, FR-035, FR-036, FR-040; bag scaling (FR-016); due dates (FR-017); status transitions (FR-011a–c); wet/dry basis rules (FR-034c, FR-037a). This layer carries SC-009 and must be exhaustively tested. |
| Local store | `drift` in-memory + `flutter_test` | Outbox atomicity, ordering, survival across restart (FR-053d, FR-053e). |
| Sync | mocked HTTP client | Idempotent retry, ordered drain, halt-and-surface on persistent failure (FR-053c). |
| Reminders | fake `ReminderScheduler` in widget tests, **plus manual runs on real devices** | Scheduling logic is unit-tested against the fake; actual delivery under Doze, reboot, and the iOS 64-notification ceiling can only be verified on hardware. |
| API | handler unit tests + contract tests against the OpenAPI document | Account isolation (FR-062) — explicitly including an attempt to read another account's records, which must fail. |
| UI | `flutter_test` widget tests + `integration_test` | The P1 journey end to end, plus the two-open-croppings disambiguation (FR-031b). |

**Rationale**: the domain layer holds everything the farmer's livelihood decisions rest on, and as plain Dart it can be tested fast and exhaustively with no device. The isolation test is called out separately because it is the one failure whose consequence is other people's data rather than a wrong number. Reminder *delivery* is explicitly listed as not unit-testable — pretending otherwise is how FR-019 ships broken.

## R9. Agronomic reference data — published bundles, farmer edits preserved

**Decision (farmer's choice, 2026-11-01)**: agronomic reference data — rice and corn varieties with maturity days, and fertilizer templates per crop and planting method — is **published data with a provenance trail**, not hardcoded constants. v1 ships a seed bundle transcribed from PhilRice and Bureau of Plant Industry published guidance. A CRM that lets those organizations maintain the data directly is **planned as a separate feature (002)**, not built here.

**What v1 builds**:

- A versioned `ReferenceBundle`: a version number, a published date, a source attribution per record, and the varieties and templates it contains.
- The seed bundle ships inside the app and loads on first run.
- `GET /v1/reference-data` lets a device pick up a newer bundle without an app-store update — important because many of these phones are never updated, and agronomic guidance changes between seasons.
- Every variety and template row records where it came from: `SEED`, `PUBLISHED` (a later bundle), or `FARMER`.

**The rule that matters most**: a new bundle **never overwrites a farmer's own edits**. FR-024 lets the farmer change templates to follow a soil test or their local agriculturist, and FR-025 already protects running croppings. Provenance extends that protection: a bundle update replaces `SEED` and `PUBLISHED` rows and leaves `FARMER` rows untouched. Without this, a routine data refresh would silently discard the agriculturist's advice a farmer had deliberately entered — the exact failure most likely to destroy trust in the recommendations.

**Rationale for deferring the CRM to feature 002 rather than building it here**:

- It serves a **different class of user** — agronomists at PhilRice and BPI publishing data for everyone — with their own accounts, review workflow, and approval step. Feature 001's spec is explicit that it serves one farmer managing their own fields, and that team access is out of scope. Folding a multi-tenant editorial tool into it would quietly break that boundary.
- It is an entirely separate surface: a web admin application, not a screen in the farmer's phone app.
- **v1 does not need it to ship.** The seed bundle is enough to be useful, and the consumption side built here is exactly what a CRM would later publish into — so deferring costs nothing and building it now delays the farmer-facing app.

**Still true and still important**: the seed values must be real figures transcribed from PhilRice and BPI, with source and date recorded per record. FR-026 requires the app to state these are general guidance, which is honest only if they are genuine published guidance. **Do not ship invented numbers to a real farmer.**

---

## R10. Reference bundle distribution

**Decision (proposed)**: bundles are immutable and monotonically versioned. The device asks `GET /v1/reference-data?since=<version>` on sign-in and periodically thereafter; a newer bundle is applied in one transaction.

**Rationale**:

- Immutable versions make the device's state unambiguous — it has bundle N or it does not — which keeps the merge rule in R9 a simple replace-by-provenance rather than a field-level diff.
- Distribution via the API rather than the app store means corrected agronomy reaches farmers who never update the app, which is most of them.
- Applying in one transaction means a failed update leaves the previous bundle intact; a half-applied fertilizer template would produce wrong bag counts, which is worse than stale ones.
- The endpoint is **unauthenticated and cacheable** — reference data is public agronomic guidance, identical for every farmer, and carries nothing account-specific. Keeping it off the authenticated path also means a guest gets correct recommendations.

**Open for feature 002**: who approves a bundle before publication, and whether PhilRice and BPI publish independently or into a shared review queue. Not needed to build v1's consumption side.

---

## R11. Infrastructure as code — Terraform, following the house pattern

**Decision** *(farmer's choice, 2026-11-01)*: **Terraform** provisions API Gateway + Lambda + DynamoDB, laid out to match the ClickSend `mr-billing` repository's conventions. AWS CDK, which this plan originally specified and which was written and working, was deleted.

**Rationale**:

- The farmer named Terraform. That alone settles it, and the requirements did not move: no FR mentions a provisioning tool, so the swap cost nothing in `spec.md`.
- Following an existing in-house layout rather than inventing one means anyone who already operates another service in this organisation can read this one. That is worth more than a marginally tidier bespoke structure.
- Terraform state is held in S3 with native lockfile locking (`use_lockfile`), not the deprecated `dynamodb_table` argument, so there is no second table to provision and keep alive purely to serialise applies.

**Layout** (mirrors `mr-billing`):

```text
terraform/
├── bootstrap/                  # the state bucket itself, chicken-and-egg: local state
├── environments/<env>/
│   ├── backend.hcl             # -backend-config: bucket, region, use_lockfile
│   └── main.tfvars             # -var-file: account number, region, tags, retention
└── modules/{dynamodb,lambda-function,apigateway,cognito}/
api/terraform/                  # the root module for this service
```

Environments are `terraform.workspace` values rather than separate directories of duplicated resources, so `dev` and a later `prd` differ by a tfvars file and a workspace name, not by a forked copy of the configuration.

**What was deliberately not copied**: the module *interfaces* mirror `mr-billing`, but the implementations are written here. One interface was widened — `apigateway` takes `lambda_function_names` as a **list**, because this service fans out to four functions where the service it was modelled on had one.

**Alternatives considered**:

| Alternative | Why rejected |
|---|---|
| Keep the AWS CDK stack | It worked and was already written. Rejected because the farmer chose Terraform, and because a lone CDK service inside a Terraform organisation is a thing only its author can operate. |
| A bespoke Terraform layout | Marginally cleaner for a single service. Rejected because the value of the house pattern is that it is the house pattern. |
| S3 state with a DynamoDB lock table | The long-standing idiom, and chosen in an earlier pass this session. Superseded by `use_lockfile`, which Terraform 1.11 supports natively; the lock table is now a resource to provision, pay for, and forget to delete. |

**Guards on the durable copy**: the table carries `deletion_protection_enabled` *and* a `prevent_destroy` lifecycle block. Two independent guards because they fail differently — `prevent_destroy` stops a `terraform destroy` from planning the deletion, and deletion protection stops a deletion issued outside Terraform entirely. The CDK stack's `RemovalPolicy.RETAIN` intent was carried over rather than lost in the translation.

---

## R12. Server-side durability and operational posture

**Decision**: point-in-time recovery for the previous 35 days, **plus** AWS Backup monthly copies retained 12 months (FR-053f). **No operator alerting** on sync health (clarified 2026-11-01).

**Rationale for the two-tier restore**: a season runs about four months and farmers compare across seasons, so a 35-day window can expire before anyone notices that a bad release corrupted a figure. PITR covers the fast case — someone notices within the week — and the monthly copies cover the case nobody notices until the next season's comparison looks wrong. SC-019 states both depths as a restore drill that can be failed.

**Rationale for no alerting**: a failed sync costs time, not data. The record is already committed on the device, the outbox retains it, and `RetryPolicy` backs off to a six-hour cap and retries **indefinitely** — `attempts` is read only to decide when to warn the farmer (`surfaceAfterAttempts = 5`), never to abandon a record. So an outage drains itself once the service returns, and the person who can actually act during one — the farmer holding records that are not yet backed up — is told directly (FR-053c).

The exposure this accepts, stated plainly: during an outage the unsynced records exist only on the phone, so a farmer who loses or breaks the handset in that window loses them. That is a real cost, accepted because the alternative is operational machinery for a v1 with no on-call rota to page.

**Consequence for a later contributor**: FR-053g makes "retries never give up" a requirement rather than an implementation detail. A future change that adds a maximum attempt count would silently convert a recoverable outage into data loss, and would now break a stated requirement rather than only a habit.

**Built and applied 2026-11-02** (dev, account 251978470165): `terraform/modules/backup` provides the monthly tier — a vault that refuses deletion while it holds recovery points, a plan running `cron(0 16 L * ? *)` (midnight Asia/Manila at the turn of the month, so a copy holds month-end state in the farmer's own timezone, which is how SC-019 is worded), and 370-day retention so twelve copies are always present rather than the oldest expiring days before its replacement arrives. Selection is by named ARN rather than by tag: a tag selector fails open, so a mistyped tag on a new table would leave it silently unprotected with nothing in the diff to show it. Wired from `api/terraform/backup.tf`. AWS accepted the schedule and holds the plan at 370 days against the `dev-saka-crop-tracking-vault`.

**Still unproven**: no recovery point exists yet — the first one is taken at the turn of the month — and no restore has been performed. A backup nobody has restored is a belief, not a backup, which is why SC-019 is written as a drill (T165) rather than as a setting.

**What a real apply caught that neither `validate` nor `plan` could.** Both passed cleanly, and the apply still failed partway through: a REST API stage refuses to enable logging until the account-level CloudWatch Logs role is set, which is a singleton per account and region. It now lives in `terraform/bootstrap`, the module that runs once per account — not in the apigateway module, where a second service would fight this one for the same global setting. The REST API and its Lambda permissions had already been created when it failed, which is the ordinary shape of this class of fault: configuration that is valid, plannable, and still wrong about the account it lands in.

**Alternatives considered**:

| Alternative | Why rejected |
|---|---|
| PITR alone (35 days) | Simplest, and the default most services stop at. Rejected because the damage this protects against — a wrong figure, not an outage — is exactly the kind discovered a season later. |
| DynamoDB on-demand backups on a schedule | Equivalent in effect. AWS Backup chosen because retention and lifecycle are declared as policy rather than driven by something that has to keep running. |
| CloudWatch alarms + SNS on sync error rate | Rejected by the farmer: records resend themselves, so nobody needs paging. Recorded in Out of Scope (v1) so a later contributor sees it as a decision rather than an omission. |

---

## Summary of decisions needing confirmation

| # | Decision | Confidence | Cost if wrong |
|---|---|---|---|
| R1 | Flutter, Android + iOS **(farmer's choice)** | Settled | Accepts the FR-019 and size trade-offs noted above |
| R2 | API in front of DynamoDB | High | Low |
| R4 | Google Sign-In primary, not SMS OTP | Medium | Low, config-level |
| R5 | Integer centavos and grams — **mobile targets only** | High | High if ignored; **breaks outright on Flutter web** |
| R6 | Per-platform local notifications; iOS 64-notification ceiling must be designed for | High on approach, uncertain on delivery | SC-005 may not be reachable |
| R9 | Seed bundle now, CRM as feature 002 | High | Low — the consumption side is what a CRM publishes into |
| R10 | Unauthenticated, versioned, immutable bundles | Medium | Low, endpoint-level |
| R11 | Terraform, house pattern **(farmer's choice)** | Settled | Low — no requirement names a provisioning tool |
| R12 | PITR 35 days + monthly copies 12 months; no operator alerting | High on restore, deliberate on alerting | Monthly copies not yet provisioned; alerting gap is accepted and recorded |
