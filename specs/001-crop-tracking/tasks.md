---

description: "Task list for 001-crop-tracking"
---

# Tasks: Crop Tracking for Rice and Corn Farmers

**Input**: Design documents from `/specs/001-crop-tracking/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Included. The design documents ask for them explicitly — research.md R8 defines a testing strategy per layer, SC-009 commits that every figure matches the farmer's own calculator, and quickstart.md's definition of done requires Scenario 8 (account isolation) to be an automated contract test rather than a manual check.

**Organization**: Tasks are grouped by user story so each can be implemented, tested, and shipped independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete work)
- **[Story]**: Which user story the task serves (US1–US5). Setup, Foundational, Durability, and Polish phases carry no story label.

## Path Conventions

Paths follow the Structure Decision in [plan.md](./plan.md): a Flutter app under `app/` layered into `domain/` (plain Dart), `data/`, `platform/`, `ui/`; a serverless API under `api/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project skeleton, dependencies, and the guard rails that make the rest of the plan enforceable rather than aspirational.

- [X] T001 Create the Flutter project and the directory skeleton from plan.md (`app/lib/{domain,data,platform,ui,l10n}`, `app/test`, `app/integration_test`, `api/src`, `api/infra`, `api/tests`)
- [X] T002 Declare dependencies in `app/pubspec.yaml`: `drift`, `sqlite3_flutter_libs`, `workmanager`, `flutter_local_notifications`, `android_alarm_manager_plus`, `amplify_auth_cognito`, `dio`, `riverpod`, `intl`, `uuid`; dev: `drift_dev`, `build_runner`, `test`, `flutter_test`, `integration_test`, `mocktail`
- [X] T003 [P] Configure `app/analysis_options.yaml` with a custom lint forbidding any `package:flutter` import inside `lib/domain/` — plan.md Structure Decision requires this be enforced, not merely conventional
- [X] T004 [P] Configure Drift codegen in `app/build.yaml` and verify `dart run build_runner build` succeeds
- [X] T005 [P] Initialize the Node 22 + TypeScript project in `api/` with Vitest, AWS SDK v3, and AWS CDK
- [X] T006 [P] Add `app/.env.example` and implement runtime config loading in `app/lib/data/remote/config.dart` for `API_BASE_URL`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`
- [X] T007 Configure `app/android/app/src/main/AndroidManifest.xml` with `SCHEDULE_EXACT_ALARM`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, and the boot receiver registration (research.md R6)
- [X] T008 [P] Configure `app/ios/Runner/Info.plist` for local notification permissions and background refresh (research.md R6)
- [X] T009 [P] Add a CI guard script at `app/tool/check_no_web_target.sh` that fails the build if a web target or `dart:html` import appears — research.md R1/R5: Flutter web silently converts integer money to floats and breaks SC-009

**Checkpoint**: Project builds on Android and iOS; the domain-layer lint and the no-web guard both fail correctly when deliberately violated.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Value types, the calculation engine, the local store, and the outbox write path. Every user story depends on these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

> **Why the outbox is built here and not in Phase 8**: the invariant in contracts/sync-protocol.md I1 is that a domain write and its outbox append happen in **one Drift transaction**. If stories are built writing directly to tables, adding the outbox later means touching every write path in the app. Nothing drains the outbox until Phase 8 — it simply accumulates — but every write goes through it from the first story onward.

### Value types and formatting

- [X] T010 [P] Implement `Centavos` as an `int`-backed value type in `app/lib/domain/model/centavos.dart` — data-model.md: "No raw `int` or `double` crosses a layer boundary for these quantities"
- [X] T011 [P] Implement `Grams` as an `int`-backed value type in `app/lib/domain/model/grams.dart`
- [X] T012 [P] Implement `SquareMetres` as an `int`-backed value type in `app/lib/domain/model/square_metres.dart` (1 ha = 10,000 m²)
- [X] T013 [P] Implement date-only handling in `app/lib/domain/model/calendar_date.dart` — spec Assumptions: "Dates are calendar dates in the farmer's local time; no time-of-day precision is needed anywhere"
- [X] T014 Implement the display formatting and rounding rule in `app/lib/domain/calc/formatting.dart` — data-model.md: "all arithmetic is exact integer arithmetic; rounding happens only when formatting for display, half-up. No intermediate result is ever rounded"

### Calculation engine (carries SC-009)

- [X] T015 [P] Write failing unit tests for every formula in the data-model.md Calculations table in `app/test/domain/calc_test.dart`, with expected values computed by hand — this suite is the evidence for SC-009
- [X] T016 Implement yield calculations (tons, tons per hectare) in `app/lib/domain/calc/yield_calc.dart` per FR-033, on the fresh-weight basis
- [X] T017 Implement money calculations (total expenses, category share, revenue, net profit, cost per kg) in `app/lib/domain/calc/money_calc.dart` per FR-029, FR-030, FR-035, FR-040
- [X] T018 Implement cost-per-kg as "not applicable" when harvested quantity is zero in `app/lib/domain/calc/money_calc.dart` — FR-041: never a division error
- [X] T019 Implement fertilizer scaling (per-hectare rate × area → grams, kg, and 50 kg bags to 1 dp) in `app/lib/domain/calc/fertilizer_calc.dart` per FR-016
- [X] T020 Implement date derivations (due date, expected harvest date) in `app/lib/domain/calc/date_calc.dart` per FR-009, FR-017

### Domain rules

- [X] T021 [P] Write failing unit tests for the cropping status state machine in `app/test/domain/status_rules_test.dart` covering FR-011a (first application done OR 10 days, whichever first), FR-011c (planting date >10 days past starts in GROWING), and the no-auto-close rule FR-012b
- [X] T022 Implement the status state machine in `app/lib/domain/rules/cropping_status.dart` per the data-model.md diagram, evaluated without any network call (FR-011b)
- [X] T023 [P] Write failing unit tests for weight-basis rules in `app/test/domain/weight_basis_test.dart` — FR-034c (sellable quantity), FR-037a ("MUST NOT subtract dry kilograms from a fresh harvest weight or the reverse")
- [X] T024 Implement weight-basis and sellable-quantity rules in `app/lib/domain/rules/weight_basis.dart` per FR-034a to FR-034d, FR-036, FR-037
- [X] T025 [P] Write failing unit tests for field occupancy in `app/test/domain/field_occupancy_test.dart` — a field holds at most one cropping in PLANTED or GROWING, and may simultaneously hold one HARVESTED (FR-008, FR-008a)
- [X] T026 Implement field occupancy rules in `app/lib/domain/rules/field_occupancy.dart` per FR-008 to FR-008b
- [X] T027 [P] Implement validation rules in `app/lib/domain/rules/validation.dart` — field area "> 0" rejecting "zero, negative, or non-numeric" (FR-002), expense amount > 0, sale rejected when it exceeds remaining or when no harvest exists (FR-037)

### Local store and outbox

- [X] T028 Define Drift tables for all entities in `app/lib/data/local/tables.dart` per data-model.md, with money as `int` centavos, weights as `int` grams, and area as `int` square metres
- [X] T029 Define the `outbox` table in `app/lib/data/local/outbox_table.dart` with `seq` (int, autoincrement), `entityType`, `entityId`, `operation`, `payload`, `attempts`, `lastError`
- [X] T030 Implement the transactional write wrapper in `app/lib/data/local/write_through.dart` so every domain write and its outbox append commit or roll back together — contracts/sync-protocol.md I1
- [X] T031 [P] Write tests for outbox atomicity and strict `seq` ordering in `app/test/data/outbox_test.dart`, including a simulated crash between the write and the append (FR-053d, FR-053e)
- [X] T032 Implement DAOs for all entities in `app/lib/data/local/daos/`, routing every mutation through the wrapper from T030 — *deferred into the Phase 3 repositories (T048, T052, T061, T068, T071) so each DAO lands with the story that uses it*
- [X] T033 Implement the Drift database class and initial migration in `app/lib/data/local/database.dart`

### Reference data (consumption side)

- [X] T034 [P] Define `ReferenceBundle`, `Variety`, and `FertilizerTemplate` models with `source` (`SEED` / `PUBLISHED` / `FARMER`), `sourceAttribution`, and `bundleVersion` in `app/lib/domain/model/reference.dart` per data-model.md
- [X] T035 [P] Write failing tests for the provenance merge in `app/test/data/reference_merge_test.dart` — a bundle update replaces `SEED` and `PUBLISHED` rows and leaves `FARMER` rows untouched (FR-026c)
- [X] T036 Implement the provenance merge, applied in one transaction, in `app/lib/data/reference/bundle_merge.dart` per FR-026c and FR-026d ("completely or not at all")
- [X] T037 Create the seed bundle at `app/assets/reference/bundle-v1.json` with rice and corn varieties, maturity days, and fertilizer templates per crop and planting method, each carrying a source attribution — **transcribe real PhilRice / Bureau of Plant Industry published figures; placeholder agronomy must not ship (research.md R9)**
- [X] T038 Implement the first-run bundle loader in `app/lib/data/reference/bundle_loader.dart`, available without an account (FR-026e)

### Platform and app shell

- [X] T039 [P] Define the `ReminderScheduler` interface and an in-memory fake for tests in `app/lib/platform/reminders/reminder_scheduler.dart`
- [X] T040 [P] Set up `app/lib/l10n/` with ARB files and the `intl` delegate so all farmer-facing text is externalised from the first screen onward (FR-055, FR-056, FR-057)
- [X] T041 Implement the app shell, routing, theme, and Riverpod providers in `app/lib/ui/common/app.dart`
- [X] T042 [P] Implement shared UI components (empty states, confirmation dialogs, currency and weight display widgets) in `app/lib/ui/common/widgets/`

**Checkpoint**: `dart test test/domain` passes with every calculation verified by hand. The database opens, writes go through the outbox, and the seed bundle loads. No user-facing screen exists yet.

---

## Phase 3: User Story 1 - Know the bottom line for one cropping (Priority: P1) 🎯 MVP

**Goal**: A farmer sets up a field, runs a cropping, logs expenses through to post-harvest, records the harvest and sales, and sees expenses, revenue, profit, tons, tons per hectare, and cost per kilogram — with no manual arithmetic.

**Independent Test**: Run quickstart.md Scenario 1 end to end in guest mode and verify all seven figures against a calculator. Then Scenario 2 (post-harvest costs and closing), Scenario 3 (two open croppings), Scenario 9 (wet/dry), and Scenario 10 (status transitions).

### Tests for User Story 1

- [X] T043 [P] [US1] Integration test for the full P1 journey in `app/integration_test/us1_bottom_line_test.dart` per quickstart.md Scenario 1, asserting the exact expected figures (₱23,500 expenses, ₱80,000 revenue, ₱56,500 profit, 5.00 tons, 2.00 t/ha, ₱4.70 per kg, 1,000 kg remaining, result labelled provisional)
- [X] T044 [P] [US1] Integration test for post-harvest costs and closing in `app/integration_test/us1_post_harvest_test.dart` per quickstart.md Scenario 2
- [X] T045 [P] [US1] Integration test for two open croppings on one field in `app/integration_test/us1_two_croppings_test.dart` per quickstart.md Scenario 3, asserting the app asks which cropping an expense belongs to and never defaults silently (FR-031b)
- [X] T046 [P] [US1] Integration test for the wet/dry weight basis in `app/integration_test/us1_weight_basis_test.dart` per quickstart.md Scenario 9, asserting remaining shows 200 kg dry and not 1,000 kg
- [X] T047 [P] [US1] Integration test for status transitions in `app/integration_test/us1_status_test.dart` per quickstart.md Scenario 10

### Fields

- [X] T048 [P] [US1] Implement the `Field` repository in `app/lib/data/local/repositories/field_repository.dart` with create, edit, archive, and cropping history (FR-001 to FR-005)
- [X] T049 [US1] Implement the field list and detail screens in `app/lib/ui/fields/` showing each field's name, area, and cropping history with result summaries (FR-005)
- [X] T050 [US1] Implement the add/edit field form in `app/lib/ui/fields/field_form.dart` — name required and non-blank, area in hectares rejecting "zero, negative, or non-numeric" (FR-002), optional location and notes
- [X] T051 [US1] Implement archive-instead-of-delete for a field with croppings in `app/lib/ui/fields/field_detail.dart` (FR-004)

### Croppings

- [X] T052 [P] [US1] Implement the `Cropping` repository in `app/lib/data/local/repositories/cropping_repository.dart` (FR-006 to FR-013)
- [X] T053 [US1] Implement the start-cropping flow in `app/lib/ui/croppings/start_cropping.dart` — field, crop (rice or corn), variety, planting method, growing season (wet or dry), planting date (FR-006)
- [X] T054 [US1] Restrict planting method options per crop in `app/lib/ui/croppings/start_cropping.dart` — rice offers transplanted and direct-seeded; corn offers direct-seeded only (FR-007, spec Assumptions)
- [X] T055 [US1] Enforce field occupancy at cropping start in `app/lib/ui/croppings/start_cropping.dart`, refusing when a cropping is in the ground and naming it, and prompting (but not forcing) closure of a harvested-but-open one (FR-008, FR-008b)
- [X] T056 [US1] Implement expected harvest date derivation with farmer override in `app/lib/ui/croppings/start_cropping.dart`, falling back to manual entry when the variety has no maturity days (FR-009, spec edge case)
- [X] T057 [US1] Implement the cropping detail screen with status display in `app/lib/ui/croppings/cropping_detail.dart` (FR-011)
- [X] T058 [US1] Implement deliberate closing with the unsold-quantity warning in `app/lib/ui/croppings/close_cropping.dart` — FR-012b: never automatic "on harvest, on a date, or when the remaining quantity reaches zero"; FR-012c warns and shows the quantity
- [X] T059 [US1] Implement write rejection on a closed cropping and the reopen path in `app/lib/data/local/repositories/cropping_repository.dart` (FR-013)
- [X] T060 [US1] Implement planting-date and field-area recalculation side effects in `app/lib/data/local/repositories/cropping_repository.dart` — shifts due dates and recommended quantities for steps not yet done, leaving recorded actuals unchanged (spec edge cases)

### Expenses

- [X] T061 [P] [US1] Implement the `Expense` repository in `app/lib/data/local/repositories/expense_repository.dart` (FR-027 to FR-031c)
- [X] T062 [US1] Implement the expense entry form in `app/lib/ui/expenses/expense_form.dart` with date, category, amount in PHP, and optional notes, optimised for the under-30-seconds target (SC-002)
- [X] T063 [US1] Implement the ten expense categories in `app/lib/domain/model/expense_category.dart` verbatim from FR-028: land preparation, seeds, fertilizer, pesticide/herbicide, labor, irrigation, equipment rental, harvesting/threshing, hauling, other
- [X] T064 [US1] Accept expense dates before the planting date and on or after the harvest date without warning in `app/lib/domain/rules/validation.dart` (FR-031a, spec edge case "Expenses before planting")
- [X] T065 [US1] Implement the cropping picker shown when a field has more than one open cropping in `app/lib/ui/expenses/cropping_picker.dart`, identifying each by field, crop, growing season, and planting date, with no silent default (FR-031b, FR-031c)
- [X] T066 [US1] Implement the running total and category breakdown with each category's amount and share of total in `app/lib/ui/expenses/expense_summary.dart` (FR-029, FR-030)
- [X] T067 [US1] Implement expense edit and delete with totals updating in `app/lib/ui/expenses/expense_form.dart` (FR-031)

### Harvest and sales

- [X] T068 [P] [US1] Implement the `Harvest` repository in `app/lib/data/local/repositories/harvest_repository.dart` (FR-032, FR-033)
- [X] T069 [US1] Implement the harvest entry form in `app/lib/ui/harvest/harvest_form.dart` accepting either sacks × average **wet** kg per sack or a total in **wet** kg, labelled fresh weight (FR-032, FR-032a)
- [X] T070 [US1] Display total tons and tons per hectare labelled fresh weight in `app/lib/ui/harvest/harvest_form.dart` (FR-033)
- [X] T071 [P] [US1] Implement the `Sale` repository in `app/lib/data/local/repositories/sale_repository.dart` (FR-034 to FR-038b)
- [X] T072 [US1] Implement the per-cropping weight basis prompt on first sale in `app/lib/ui/harvest/sale_form.dart`, changeable while the cropping is open (FR-034a)
- [X] T073 [US1] Require the lot's dried weight before any dry sale in `app/lib/ui/harvest/sale_form.dart`, with no wet-to-dry conversion attempted (FR-034b, spec edge case "Basis chosen before the lot is dried")
- [X] T074 [US1] Implement the sale entry form in `app/lib/ui/harvest/sale_form.dart` with quantity in kilograms, price per kilogram, buyer, and date, displaying the cropping's weight basis alongside (FR-034, FR-034d)
- [X] T075 [US1] Implement remaining-quantity display and sale rejection when quantity exceeds remaining or no harvest exists in `app/lib/ui/harvest/sale_form.dart` (FR-036, FR-037)
- [X] T076 [US1] Implement harvest and sale edit and delete with all derived figures updating in `app/lib/ui/harvest/` (FR-038)

### Results

- [X] T077 [US1] Implement the cropping result screen in `app/lib/ui/results/cropping_result.dart` showing total expenses, total revenue, net profit or loss, tons, tons per hectare, and cost per kilogram on one screen (FR-039, SC-003)
- [X] T078 [US1] Implement the three result states in `app/lib/ui/results/cropping_result.dart` — `IN_PROGRESS` before harvest showing expenses only and never as a loss (FR-042), `PROVISIONAL` while harvested and open and recalculating as costs and sales land (FR-042a), `FINAL` once closed (FR-042b)


> **Phase 3 verified on hardware 2026-11-01**: all 11 integration tests pass on an iPhone 16 simulator (Xcode 26.3), alongside 107 headless tests. The device run caught a real defect the headless suite could not — Save sat below the fold on a phone-sized screen, so it is now pinned to a `SafeArea` footer in every form. Android hardware is still unverified: no JDK in this environment.

**Checkpoint**: User Story 1 is fully functional in guest mode. A farmer can run a complete cropping and get every number. This is a shippable MVP — but see the Durability note in Implementation Strategy before putting it in a real farmer's hands.

---

## Phase 4: User Story 2 - Follow a fertilizer schedule sized to the field (Priority: P2)

**Goal**: Each cropping gets a schedule from the matching template, scaled to the field's area and shown in 50 kg bags, with reminders before each application and a one-tap path from "done" to a recorded expense.

**Independent Test**: quickstart.md Scenario 4 (bag scaling and the expense link) and Scenario 5 (offline reminders on real Android and iOS hardware).

### Tests for User Story 2

- [X] T079 [P] [US2] Integration test for schedule generation and bag scaling in `app/integration_test/us2_schedule_test.dart` per quickstart.md Scenario 4 — a 100 kg/ha step on 2.5 ha shows 250 kg and 5.0 bags
- [X] T080 [P] [US2] Integration test for the application-to-expense link in `app/integration_test/us2_expense_link_test.dart` asserting a ₱7,500 cost appears exactly once, and editing it to ₱8,000 moves the total by ₱500 and not ₱8,000 (FR-021, SC-006)
- [X] T081 [P] [US2] Unit tests for reminder scheduling against the fake `ReminderScheduler` in `app/test/platform/reminder_scheduling_test.dart`, including the iOS rolling-window cap (research.md R6)

### Schedule

- [X] T082 [P] [US2] Implement the `ScheduledApplication` repository in `app/lib/data/local/repositories/application_repository.dart` (FR-014 to FR-023)
- [X] T083 [US2] Generate a cropping's schedule from the matching template at cropping start in `app/lib/data/local/repositories/cropping_repository.dart`, snapshotting timing, growth stage, product, and rate per hectare (FR-014, FR-015, FR-025)
- [X] T084 [US2] Implement the schedule screen in `app/lib/ui/fertilizer/schedule_screen.dart` showing each step's growth stage, days after planting, product, per-hectare rate, derived due date, and quantity in both kg and 50 kg bags (FR-015 to FR-017)
- [X] T085 [US2] Flag overdue applications in `app/lib/ui/fertilizer/schedule_screen.dart` and stop showing steps as due or overdue once the cropping is harvested (FR-018, spec edge case "Pending steps at harvest time")
- [X] T086 [US2] Display the general-guidance statement wherever a recommendation appears, with its source attribution and published date, in `app/lib/ui/fertilizer/` (FR-026, FR-026a)

### Marking applications

- [X] T087 [US2] Implement mark-as-done capturing actual date, product, quantity, and cost in `app/lib/ui/fertilizer/mark_application.dart` (FR-020)
- [X] T088 [US2] Implement the linked-expense lifecycle in `app/lib/data/local/repositories/application_repository.dart` — recording a cost creates exactly one fertilizer-category expense; editing updates that same expense; deleting the application deletes it, so the cost is "never counted twice and never orphaned" (FR-021, SC-006)
- [X] T089 [US2] Implement mark-as-skipped with an optional reason and no expense in `app/lib/ui/fertilizer/mark_application.dart` (FR-022)
- [X] T090 [US2] Implement per-cropping schedule editing that does not affect the template in `app/lib/ui/fertilizer/edit_schedule.dart` (FR-023)
- [X] T091 [US2] Trigger the PLANTED → GROWING transition on the first application marked done in `app/lib/domain/rules/cropping_status.dart` (FR-011a)

### Reminders

- [X] T092 [US2] Implement the Android `ReminderScheduler` in `app/lib/platform/reminders/android_scheduler.dart` using exact alarms, with `BOOT_COMPLETED` re-registration (FR-019, research.md R6) — *implemented in `app/lib/platform/reminders/local_notification_scheduler.dart`, which covers BOTH platforms. `android_alarm_manager_plus` proved unnecessary: flutter_local_notifications already provides exact alarms and the manifest boot receiver. **Delivery unverified — no JDK.***
- [X] T093 [P] [US2] Implement the iOS `ReminderScheduler` in `app/lib/platform/reminders/ios_scheduler.dart` using `UNUserNotificationCenter`, scheduling only a rolling window per cropping to stay inside the 64 pending-notification cap (research.md R6) — *same file; the rolling window is enforced by `ReminderPlanner.plan` and covered by tests*
- [X] T094 [US2] Schedule reminders 2 days before each due date and again on the due date in `app/lib/data/sync/reminder_sync.dart` (FR-019)
- [X] T095 [US2] Implement the reminders on/off setting, keeping upcoming and overdue applications visible in-app when off, in `app/lib/ui/account/settings.dart` (FR-019a)
- [X] T096 [US2] Suppress reminders for applications already done or skipped and for croppings already harvested or closed in `app/lib/data/sync/reminder_sync.dart` (FR-019b)
- [X] T097 [US2] Implement the daily reconciliation task in `app/lib/data/sync/reminder_reconciliation.dart` that re-registers lost alarms and tops up the iOS rolling window (research.md R6)

**Checkpoint**: User Stories 1 and 2 both work independently. Scenario 5 must be validated on physical Android and iOS devices before this phase is called done.

---

## Phase 5: User Story 3 - See what needs attention right now (Priority: P3)

**Goal**: Opening the app shows active croppings, the next fertilizer applications due, upcoming harvests, and harvested croppings still awaiting sales — with no navigation.

**Independent Test**: With two active croppings on different fields and one harvested-but-open cropping, confirm all three sections populate correctly and in due-date order.

- [X] T098 [P] [US3] Widget test for the home screen in `app/test/ui/home_screen_test.dart` covering populated and empty states
- [X] T099 [US3] Implement the home screen scaffold in `app/lib/ui/home/home_screen.dart`
- [X] T100 [US3] Show croppings currently in progress with field, crop, status, and days since planting in `app/lib/ui/home/active_croppings.dart` (FR-044)
- [X] T101 [US3] Show the next fertilizer applications due across all active croppings, in due-date order, with field, product, and quantity in bags in `app/lib/ui/home/upcoming_applications.dart` (FR-045)
- [X] T102 [US3] Show croppings whose expected harvest date is approaching in `app/lib/ui/home/upcoming_harvests.dart` (FR-046)
- [X] T103 [US3] Show harvested-but-unclosed croppings with their unsold remaining quantity in `app/lib/ui/home/awaiting_closure.dart` — FR-046a exists so outstanding sales and post-harvest costs "are not forgotten once the field has been replanted"
- [X] T104 [US3] Show both croppings distinctly when a field has one in the ground and one harvested but open in `app/lib/ui/home/` (FR-046b)
- [X] T105 [US3] Implement the empty state inviting the farmer to start a cropping rather than showing blank sections in `app/lib/ui/home/home_screen.dart` (US3 acceptance scenario 4)


> **Phase 5 verified 2026-11-01**: 8 home-screen widget tests pass headlessly against a real in-memory database. The home screen is now the app entry point (`lib/main.dart`), replacing the fields list.

**Checkpoint**: User Stories 1, 2, and 3 all work independently.

---

## Phase 6: User Story 4 - Compare seasons and fields (Priority: P4)

**Goal**: The farmer compares croppings across seasons and fields on profit, yield, and cost per kilogram — all on the same fresh-weight basis, so the comparison is like-for-like.

**Independent Test**: With at least three closed croppings spanning two fields and two seasons, confirm side-by-side metrics and that filters by field, crop, and season work.

- [X] T106 [P] [US4] Widget test for the comparison view and its filters in `app/test/ui/comparison_test.dart`
- [X] T107 [US4] Implement the comparison view in `app/lib/ui/results/comparison_screen.dart` listing field, crop, variety, season, planting date, expenses, revenue, net profit or loss, tons, tons per hectare, and cost per kilogram (FR-043)
- [X] T108 [US4] Implement filters for field, crop, and season in `app/lib/ui/results/comparison_filters.dart` (FR-043)
- [X] T109 [US4] Label yields and cost per kilogram as fresh weight throughout the comparison in `app/lib/ui/results/comparison_screen.dart` — FR-043: "every cropping's yield and cost per kilogram are on the same fresh-weight basis, these comparisons are like-for-like"
- [X] T110 [US4] Compute comparisons from the local database so they work offline in `app/lib/data/local/repositories/comparison_repository.dart` (research.md R7, "Note on reporting")


> **Phase 6 verified 2026-11-01**: 8 comparison widget tests pass headlessly against a real in-memory database, covering the full figure set, all three filters, the best-profit marker, and FR-042 holding inside the comparison (an unharvested cropping shows no profit rather than a loss). Reachable from the home screen.

**Checkpoint**: User Stories 1 through 4 all work independently.

---

## Phase 7: User Story 5 - Adjust the fertilizer recommendations (Priority: P5)

**Goal**: The farmer edits the templates to follow a soil test or their local agriculturist, and those edits survive both new croppings and later published guidance.

**Independent Test**: Edit a template, confirm a new cropping uses the edit while a running cropping is unchanged, then apply a newer reference bundle and confirm the edit survives (quickstart.md Scenario 11).

- [X] T111 [P] [US5] Integration test for template editing and bundle-update survival in `app/integration_test/us5_template_edit_test.dart` per quickstart.md Scenario 11
- [X] T112 [US5] Implement the template list and editor in `app/lib/ui/fertilizer/template_editor.dart` with add, edit, remove, and reorder of steps per crop and planting method (FR-024)
- [X] T113 [US5] Mark farmer-edited templates and varieties with `source = FARMER` on save in `app/lib/data/reference/` so later bundles cannot overwrite them (FR-026c)
- [X] T114 [US5] Confirm template edits apply only to croppings started after the edit, leaving existing schedules untouched, in `app/lib/data/local/repositories/application_repository.dart` (FR-025)
- [X] T115 [US5] Implement custom variety creation with its own maturity days in `app/lib/ui/croppings/variety_form.dart` (FR-010)


> **Phase 7 verified 2026-11-01**: 13 template-editing tests pass headlessly, including quickstart Scenario 11 — a farmer's 120 kg/ha edit survives a published bundle saying 90, while an untouched template still updates. FR-023 is covered separately: editing one cropping's schedule never touches the template.

**Checkpoint**: All five user stories are independently functional in guest mode.

---

## Phase 8: Durability — Accounts, Sync, and Restore

**Purpose**: Everything that stops a lost phone from destroying a farmer's history. No story label — this serves all five stories equally.

**⚠️ Read the Durability note in Implementation Strategy before deciding when to run this phase.**

### API infrastructure

> **T116–T118 were re-implemented in Terraform on 2026-11-01** (research.md R11). The `api/infra/*.ts` paths below are the CDK files they were originally written against; that directory is deleted. The equivalents are `terraform/modules/{dynamodb,cognito,apigateway}/` and the root module `api/terraform/`. The tasks stay marked complete because the work they describe was done and then carried across — see Phase 10 for what the migration left outstanding.


- [X] T116 [P] Define the DynamoDB single table in `api/infra/table.ts` with `PK = ACCOUNT#<cognito_sub>` and the sort-key scheme from research.md R7, on-demand capacity
- [X] T117 [P] Define the Cognito User Pool with Google Sign-In and email/password fallback in `api/infra/auth.ts` (research.md R4)
- [X] T118 Define API Gateway with JWT authorization in `api/infra/api.ts`, validating the Cognito token before any Lambda runs
- [X] T119 Implement account-id derivation in `api/src/auth/account.ts` reading **only** the verified JWT `sub` claim — contracts/sync-protocol.md I5: a request body naming an account id "is rejected, not honoured"
- [X] T120 [P] Implement server-side record validation in `api/src/validation/` mirroring the domain rules

### API handlers

- [X] T121 [P] Write the account-isolation contract test in `api/tests/contract/isolation.test.ts` per quickstart.md Scenario 8 — attempt to read and write account B's records with account A's token, by id and by crafted body field; every attempt must fail (FR-062)
- [X] T122 [P] Write contract tests for all four routes against `specs/001-crop-tracking/contracts/api.openapi.yaml` in `api/tests/contract/`
- [X] T123 Implement `POST /v1/mutations` in `api/src/handlers/mutations.ts` applying mutations in array order, stopping at the first failure and returning `failedIndex`, idempotent on client-generated UUIDs
- [X] T124 Implement `GET /v1/snapshot` in `api/src/handlers/snapshot.ts` with cursor pagination and the optional `since` parameter
- [X] T125 [P] Implement `GET /v1/reference-data` in `api/src/handlers/reference.ts` — unauthenticated and cacheable, returning 304 when the client's `since` version is current (research.md R10)
- [X] T126 [P] Implement `DELETE /v1/account` in `api/src/handlers/account.ts`

### Client sync

- [X] T127 [P] Write sync drain tests in `app/test/data/sync_test.dart` against a mocked HTTP client — ordered drain, idempotent retry after an ambiguous timeout, halt-and-surface on persistent failure (contracts/sync-protocol.md I2, I3)
- [X] T128 Implement the outbox drain worker in `app/lib/data/sync/sync_worker.dart` taking batches of up to 100 in `seq` order and halting rather than skipping ahead on failure
- [X] T129 Implement the retry and backoff policy in `app/lib/data/sync/retry_policy.dart` per the contracts/sync-protocol.md table — including that a 400 `validation_failed` halts and surfaces rather than dropping the farmer's entry
- [X] T130 Implement soft deletes in `app/lib/data/local/` so a deletion made offline propagates instead of being resurrected by the next snapshot (contracts/sync-protocol.md I4)
- [ ] T131 Register the sync worker with `workmanager` under a network constraint, and also drain on app foreground for iOS, in `app/lib/data/sync/sync_registration.dart` — ***not done, and not doable on this Flutter.*** No `workmanager` version is compatible with Flutter 3.35 (see research.md R6). The periodic task was removed and replaced with resume-based reconciliation in `app/lib/data/sync/background_tasks.dart`. Reopen only if Flutter is upgraded to 3.38+.

### Accounts

- [X] T132 [P] Implement sign-in with Google and email/password fallback in `app/lib/ui/account/sign_in.dart` (FR-058, research.md R4)
- [X] T133 Implement guest mode with `accountId == null` and local-only storage in `app/lib/data/local/repositories/account_repository.dart` (FR-059, FR-060)
- [X] T134 Implement the standing guest notice that records are not protected against device loss and cannot be restored, in `app/lib/ui/account/guest_banner.dart` — FR-060 requires this be stated "plainly", and the spec notes it is deliberately a standing fact rather than a one-time dialog
- [X] T135 [P] Write the guest-to-account migration test in `app/test/data/guest_migration_test.dart` asserting 100% of records migrate with no re-entry and no figure changing (SC-016)
- [X] T136 Implement guest-to-account migration in `app/lib/data/sync/guest_migration.dart` — assign the new account id to every local row and enqueue all of them, in one transaction, with no id rewritten (FR-061)
- [X] T137 Implement sign-out leaving no records readable to a guest or another account in `app/lib/ui/account/sign_out.dart` (FR-063)
- [X] T138 Implement account recovery routing in `app/lib/ui/account/recovery.dart` so a forgotten credential does not destroy a history (FR-066)
- [X] T139 Keep an existing session fully usable offline, with no network call required to continue, in `app/lib/data/remote/session.dart` (FR-065)
- [X] T140 Limit the account prompt to once per session for guests in `app/lib/ui/account/guest_banner.dart` (FR-067)

### Restore

- [X] T141 Implement restore-on-sign-in in `app/lib/data/sync/restore.dart` paginating the snapshot into Drift (FR-052, FR-064)
- [X] T142 Re-derive every cropping's PLANTED → GROWING status after restore in `app/lib/data/sync/restore.dart` — contracts/sync-protocol.md flags this as easy to forget and load-bearing (FR-011a, FR-011b)
- [X] T143 Reschedule all pending reminders after restore in `app/lib/data/sync/restore.dart` — without it a restored device silently stops reminding the farmer (research.md R6)
- [X] T144 [P] Write the restore test in `app/test/data/restore_test.dart` asserting 100% recovery with no figure differing, statuses correct, and alarms rescheduled (SC-013)

### Sync visibility

- [X] T145 Implement the sync status indicator on the home screen in `app/lib/ui/home/sync_status.dart` showing up to date, *n* pending, not backed up, or guest — visible without opening settings (FR-053b, SC-015)
- [X] T146 Implement the persistent failure notice in `app/lib/ui/home/sync_status.dart` — FR-053c: a repeatedly failing sync must never leave the app "appearing healthy while nothing reaches remote storage"
- [X] T147 Implement periodic reference-bundle checks in `app/lib/data/reference/bundle_updater.dart` calling `GET /v1/reference-data` and applying newer bundles through the T036 merge (FR-026b)

**Checkpoint**: A farmer's history survives a lost phone. Account isolation is proven by an automated test, not a manual check.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [X] T148 [P] Verify no `double` appears anywhere in `app/lib/domain/` and add a CI check in `app/tool/check_no_double.sh` (SC-009, research.md R5)
- [X] T149 [P] Verify all farmer-facing strings live in `app/lib/l10n/` ARB files with none in logic, and add a CI check (FR-056, FR-057)
- [X] T150 [P] Audit `app/lib/domain/` and `app/lib/data/` for behaviour branching on display text and add a CI check in `app/tool/check_no_label_branching.sh` — categories, statuses, and growth stages must be identified independently of how they are shown (FR-057)
- [ ] T151 Replace any placeholder agronomy in `app/assets/reference/bundle-v1.json` with verified PhilRice / Bureau of Plant Industry figures and confirm every record carries a source attribution (research.md R9)
- [ ] T152 [P] Measure cold start and list render against the plan.md performance goals on a low-end Android device
- [ ] T153 Run quickstart.md Scenario 5 on a low-end Android handset and an iOS device past the 64-notification ceiling, and record the result — **if delivery proves unreliable, raise it rather than working around it, since SC-005 depends on it** (research.md R6)
  - **Narrowed, 2026-11-01.** The scheduling mechanism is now verified on an Android emulator (API 36) against the OS itself, not just the app: `dumpsys alarm` shows an exact `RTC_WAKEUP` (`window=0`, `exactAllowReason=policy_permission`) aimed at the plugin's boot-surviving receiver at the right instant in `Asia/Manila`, and letting one fire posted the notification on the `fertilizer_reminders` channel with the right text. Evidence in research.md R6, automated as `app/integration_test/reminders_device_test.dart` (6 cases, Android).
  - **What is left is the part an emulator cannot answer**: whether an OEM battery manager on a real low-end handset suppresses the alarm after a force-stop or overnight Doze. That is the risk R6 calls out as most likely to break FR-019 in the field, and it needs physical hardware of the kind the target farmers actually buy.
  - iOS is also still open: its reminder cases need a human to tap the authorisation prompt once per install, so they are excluded from the unattended suite and belong to this checklist.
- [X] T157 Make a blocked notification permission visible to the farmer (FR-019a) — *found while verifying T153. `settings_screen.dart` discarded the result of `requestPermissions()`, so a farmer who declined kept a reminders switch that read ON while Android silently discarded every post: the alarm still armed, the receiver still ran, and nothing surfaced. The `settingsRemindersDenied` string had been written months earlier and never rendered anywhere. Added `ReminderScheduler.notificationsEnabled()` (asked live, not cached, since the permission can be revoked in system settings long after the prompt), `notificationsPermittedProvider`, and an alert on the settings screen. Covered by `app/test/ui/reminder_permission_test.dart`; 3 of its 4 cases fail without the fix.*
- [ ] T154 Run all twelve quickstart.md scenarios on physical Android and iOS devices and complete the definition-of-done checklist
- [X] T155 [P] Write `README.md` covering local setup, the module boundaries, and the invariants a contributor must not break
- [X] T156 Review error and empty states across every screen under `app/lib/ui/` for plain language a farmer can act on, recording the pass in `specs/001-crop-tracking/quickstart.md` definition of done — *reviewed every error and empty state. Six revised: "Enter a number" now shows the expected shape (decimal commas are common locally), "Too many decimal places" became actionable, a blank text field no longer says to enter a number, the backup warning stopped shouting in caps, and two empty states that shared one string now say what to do.*

---

## Phase 10: Infrastructure Migration and Server-Side Durability

**Purpose**: Carry the Terraform decision (research.md R11) and the two-tier restore requirement (FR-053f, R12) from decided to deployed, and close the identity gap that `/speckit-plan` found on 2026-11-01. No story label — like Phase 8, this serves all five stories equally.

**Why this is its own phase rather than additions to Phase 8**: Phase 8 built the durable copy. This phase is about whether that copy is actually provisioned, actually restorable, and actually reachable by a signed-in farmer. Each of those is currently false in a different way.

### Infrastructure as code (research.md R11)

- [X] T158 Rewrite the infrastructure as Terraform modules under `terraform/modules/{dynamodb,lambda-function,apigateway,cognito}/` mirroring the `mr-billing` house interfaces, with per-environment config in `terraform/environments/dev/{backend.hcl,main.tfvars}` and the service root module in `api/terraform/` — *done. `terraform fmt -check -recursive` and `terraform validate` both pass. The `apigateway` module takes `lambda_function_names` as a list rather than a single name, because this service fans out to four functions where the service it was modelled on had one.*
- [X] T159 Replace the CDK bundling with `api/build.sh`, producing one esbuild zip per function in `api/build/` with `--external:@aws-sdk/*` — *the nodejs22.x runtime ships SDK v3, so bundling it would add megabytes to every cold start for no benefit.*
- [X] T160 Define the REST API from `api/src/docs/saka-api.json` via `templatefile`, with `x-amazon-apigateway-integration` per operation, a `cognito_user_pools` authorizer applied at the top level, and an explicit `"security": []` on `/v1/reference-data` only — *verified in the plan output: all three authenticated routes carry the authorizer, only reference-data is public, and the `reference` Lambda receives no DynamoDB policy at all.*
- [X] T161 Fix account-id derivation for API Gateway REST v1 in `api/src/auth/account.ts`, reading `requestContext.authorizer.claims` as well as `requestContext.authorizer.jwt.claims` — *a REST v1 Cognito authorizer puts claims one level higher than an HTTP v2 JWT authorizer, so the v2-only code derived no `sub` and would have 401'd every authenticated request. Pinned by three cases in `api/tests/contract/isolation.test.ts` that fail if either shape is dropped.*
- [X] T162 Apply `terraform/bootstrap` to create the `dev-saka-terraformstate` bucket, then `terraform -chdir=api/terraform init -backend-config=../../terraform/environments/dev/backend.hcl`, select workspace `dev`, and apply with `-var-file=../../terraform/environments/dev/main.tfvars` — record the outputs into `app/env.json` per quickstart.md Setup — *applied 2026-11-02 to account 251978470165, ap-southeast-1. 4 + 3 bootstrap resources, 35 service resources. Verified against the live API rather than against the plan: `/v1/snapshot`, `/v1/mutations` and `/v1/account` all 401 without a token, `/v1/reference-data` is public, the table is ACTIVE with PITR enabled and deletion protection on, the monthly backup plan holds `cron(0 16 L * ? *)` at 370 days, and the hosted UI returns 200 for the real client id and redirect URI — which is the check that matters most, because a redirect-URI mismatch fails only after the farmer has typed their password.*
- [X] T162a Set the account-level API Gateway CloudWatch Logs role in `terraform/bootstrap/main.tf` — *the apply failed partway through without it: REST API stages refuse to enable logging until it is set, and it is a singleton per account and region. It cannot live in the apigateway module, where a second service would fight this one for the same global setting, so it belongs in the module that runs once per account. **Neither `validate` nor `plan` can catch this** — it surfaced only on a real apply, after the REST API and its Lambda permissions had already been created.*
- [X] T162b Return 204 rather than 304 when no bundle is published and the caller sent no `since`, in `api/src/handlers/reference.ts` — *found by curling the deployed endpoint. A bare `GET /v1/reference-data` answered 304, which tells a caller their copy is current when they have no copy, and which `contracts/api.openapi.yaml` does not permit. 304 is now only ever an answer to `since`. Contract, OpenAPI document and client (`api_client.dart` accepted only 200/304 and would have thrown) all updated together; two cases in `api/tests/contract/routes.test.ts` pin the distinction.*
- [X] T163 Delete the orphaned S3 bucket `saka-tfstate-251978470165` — *created by the superseded first layout; its state file was deleted with `infra/`, so it exists in account 251978470165 and is managed by no Terraform state. **Confirm with the account owner before deleting**, and verify it holds no state file still referenced by anything.* — *done 2026-11-02, confirmed first. It held exactly one object: a 231-byte `.tflock` leftover, already delete-markered. No state. Versions and delete markers purged, bucket deleted, absence verified.*

### Server-side restore (FR-053f, SC-019)

- [X] T164 Add an AWS Backup plan providing monthly recovery points retained 12 months for the DynamoDB table, as a module under `terraform/modules/` wired from `api/terraform/backup.tf` — *written 2026-11-02. Vault without `force_destroy`, so it refuses deletion while it holds recovery points; `cron(0 16 L * ? *)` — midnight Asia/Manila at the turn of the month, because SC-019 is written in terms of the farmer's month end, not UTC's; 370-day retention rather than 365 so twelve copies are always present instead of the oldest expiring days before its replacement; selection by named ARN rather than by tag, because a tag selector fails open and a mistyped tag would leave a table silently unprotected. Restore permissions are attached to the same role, since SC-019 is a drill rather than a setting. **`terraform validate` passes and both managed-policy ARNs were confirmed against the account; nothing is applied, so the schedule itself is unproven — see T162 and T165.***
- [X] T164a Add `prevent_destroy` to the table in `terraform/modules/dynamodb/main.tf` — *found while wiring T164: `plan.md` and `research.md` R11 both claimed the table carried two independent delete guards, and it carried one. `prevent_destroy` was on the state bucket only. The claim is now true rather than merely written down. The two guards fail differently, which is the point: deletion protection refuses a delete issued through the AWS API, `prevent_destroy` stops Terraform planning one — including the replacement Terraform decides on by itself when an immutable attribute such as `hash_key` changes.*
- [ ] T165 Run quickstart.md Scenario 13 as a real restore drill against **dev**: damage a record, restore to a PITR timestamp into a new table, and confirm net profit, tons per hectare and cost per kilogram all match what was recorded beforehand (SC-019). Repeat against a monthly recovery point once T164 is applied — *a restore that returns the rows but changes a figure is a failure, not a partial pass*

### Identity (FR-058, FR-062)

- [X] T166 Implement a real `AuthSessionProvider` against the Cognito user pool in `app/lib/data/remote/cognito_auth_session.dart` and override `authSessionProvider` in `app/lib/main.dart` — *`LocalAuthSessionProvider` is currently the only implementation; it fabricates the account id `google-sub` and the bearer token `token-for-google-sub`, and nothing overrides it at startup. The sign-in screen (T132) is real and wired, so this is the missing layer beneath it. FR-065 constrains the implementation: reporting an already-established session must not require a network call, or a farmer is locked out of their own records exactly when they are furthest from signal.* — *done 2026-11-02. `flutter_appauth` against Cognito's hosted UI, authorization code + PKCE, session in `flutter_secure_storage`. `main.dart` now overrides the auth provider AND `apiClientProvider`, which was equally inert — the comment said "overridden at startup" and nothing overrode it, so the whole durability path was dead in the running app, not just auth. FR-065 is honoured throughout: `currentSession()` makes no network call, an expired token postpones a sync rather than ending a session, and a failed refresh keeps the session.*
  - **The screen lost its password field, deliberately.** Credentials are typed on Cognito's page, so `signInWithEmail`/`signUpWithEmail`/`startPasswordRecovery` are gone from the interface and five ARB strings with them. Keeping a password field the hosted flow cannot use would have meant collecting a password and discarding it.
  - **A new guard, because the stub is still the fallback**: `signInAvailableProvider`. An unconfigured build now says it has no account service instead of offering buttons `LocalAuthSessionProvider` would answer as success — which would tell a farmer their records were backed up while nothing had left the phone. Covered by `app/test/ui/sign_in_screen_test.dart`; forcing the screen to ignore it fails exactly that case.
  - **Configuration moved from `.env` to `--dart-define-from-file`.** A bundled `.env` has to be declared as an asset, and a declared asset must exist or the build fails — so "the app runs without configuration" would have been true only for someone who had already made the optional file. Verified: adding the asset broke `flutter test` immediately.
- [X] T166a Create the Cognito hosted UI whenever a domain prefix is set, rather than only when Google is fully configured, in `terraform/modules/cognito/` — *found while wiring T166: the domain and the OAuth flows were both gated on `google_enabled`, so an email-and-password sign-in would have had nowhere to redirect. Also fixed a sensitivity leak the same change exposed — `google_enabled` derived from the client secret, which propagated sensitivity into `hosted_ui_domain` and failed `terraform plan` with "Output refers to sensitive values" on what is a public redirect URL. `nonsensitive()` now wraps the emptiness check only, never the secret. Neither fault was visible to `terraform validate`; both needed a real plan.*
- [ ] T167 Prove account isolation end to end with real tokens (quickstart.md Scenario 8) — two Cognito accounts, each signing in from the app and failing to read or write the other's records. *`api/tests/contract/isolation.test.ts` already proves the server side with synthesised events; this proves the client actually sends a token the server accepts, which no test covers today.*

### Guarding the decisions this phase rests on

- [X] T168 [P] Extend the existing `RetryPolicy` group in `app/test/data/sync_test.dart` with a regression case asserting that no attempt count causes a queued record to be abandoned — the group currently covers backoff timing (`delayForAttempt`) but nothing asserts that retrying never stops — *done 2026-11-02. Three cases: 50 consecutive 503 drains leave both records queued and the drain still `retryable`, then the service returns and the backlog drains with no intervention; the backoff stays finite at 10⁶ attempts; `shouldSurface` latches on rather than ever becoming terminal. **Proved it can fail**: planting the obvious "give up after 10 attempts" change in `sync_worker.dart` made the behavioural case fail — and it failed by reporting `applied`, which is the dangerous symptom exactly, the app looking healthy because the queue was emptied by discarding the records rather than by sending them.* — *FR-053g. With no operator alerting by design (R12), the device retrying is the entire recovery mechanism for a service outage, so a future maximum-attempt-count would silently convert a recoverable outage into data loss. `surfaceAfterAttempts` must affect only what the farmer is told.*

---

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **blocks every user story**
- **User Stories (Phases 3–7)**: all depend on Foundational; independent of each other thereafter
- **Durability (Phase 8)**: depends on Foundational (specifically the outbox, T029–T032). Independent of the user stories, so it can run in parallel with them
- **Polish (Phase 9)**: depends on everything that will ship
- **Infrastructure & Durability (Phase 10)**: T162 depends on T158–T161 (all complete). T164 depends on T162, because there is nothing to back up until the table is applied. T165 depends on T164 for its second tier only — the PITR half can run as soon as T162 lands. T166 and T167 depend on T162 for a real user pool, and on nothing else; T167 depends on T166. T168 depends on nothing and can be done now

### User Story Dependencies

- **US1 (P1)**: Foundational only. No dependency on any other story
- **US2 (P2)**: Foundational only. Writes expenses through the US1 expense repository, but that repository is a Phase 3 task — if US2 is built first, T061 must move with it
- **US3 (P3)**: Foundational only. Surfaces data the other stories produce, so it is testable alone but most useful after US1 and US2
- **US4 (P4)**: Foundational only. Needs closed croppings to compare, which US1 produces
- **US5 (P5)**: Foundational only. Edits templates that US2 consumes

### Within Each User Story

Tests → repositories → UI → validation and edge cases. Tests are written first and must fail before implementation.

### Parallel Opportunities

- Phase 1: T003–T006, T008, T009 in parallel
- Phase 2: value types T010–T013 in parallel; test tasks T015, T021, T023, T025, T031, T035 in parallel; T034, T039, T040, T042 in parallel
- Phase 3: all five test tasks T043–T047 in parallel; repositories T048, T052, T061, T068, T071 in parallel
- Phase 8: infrastructure T116, T117 in parallel; contract tests T121, T122 in parallel; handlers T125, T126 in parallel
- Phase 9: T148, T149, T150, T152, T155 in parallel
- Phase 10: T168 is independent of everything else in the phase and can run immediately; T163 (bucket cleanup) is independent of the deploy chain
- Across phases: **Durability (Phase 8) can run alongside the user stories** by a second developer, since it touches `api/` and `app/lib/data/sync/` rather than the story UI

---

## Parallel Example: User Story 1

```bash
# All five integration tests for US1 together:
Task: "Integration test for the full P1 journey in app/integration_test/us1_bottom_line_test.dart"
Task: "Integration test for post-harvest costs and closing in app/integration_test/us1_post_harvest_test.dart"
Task: "Integration test for two open croppings in app/integration_test/us1_two_croppings_test.dart"
Task: "Integration test for the wet/dry weight basis in app/integration_test/us1_weight_basis_test.dart"
Task: "Integration test for status transitions in app/integration_test/us1_status_test.dart"

# All five repositories together:
Task: "Implement the Field repository in app/lib/data/local/repositories/field_repository.dart"
Task: "Implement the Cropping repository in app/lib/data/local/repositories/cropping_repository.dart"
Task: "Implement the Expense repository in app/lib/data/local/repositories/expense_repository.dart"
Task: "Implement the Harvest repository in app/lib/data/local/repositories/harvest_repository.dart"
Task: "Implement the Sale repository in app/lib/data/local/repositories/sale_repository.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup
2. Phase 2: Foundational — **critical, blocks everything**
3. Phase 3: User Story 1
4. **STOP and VALIDATE**: run quickstart.md Scenarios 1, 2, 3, 9, and 10, checking every figure by hand
5. Demo

### ⚠️ Durability note — read before shipping to a real farmer

Phase 8 is placed after the user stories so the phase numbers match the story priorities, **but that is not the recommended shipping order**.

The moment a real farmer starts entering a season of data, losing it becomes the worst thing the app can do — worse than lacking a comparison view or a home screen. Guest mode is fine for a demo and for your own testing; it is not fine for someone recording the costs their livelihood depends on.

**Recommended order for a real pilot**: Phase 1 → 2 → 3 (US1) → 4 (US2) → **8 (Durability)** → **10 (Infrastructure & Identity)** → 5 → 6 → 7 → 9.

**Phase 10 is not optional for a pilot, and Phase 8 alone is not enough.** Phase 8 built the durable copy and its tests pass, but as of 2026-11-01 none of it is reachable by a real farmer: the infrastructure is written and not applied (T162), and sign-in is a stub that fabricates an account id and a fake token (T166). A farmer who signs in today gets the *appearance* of a backed-up account with nothing behind it — which is worse than guest mode, because guest mode says plainly that records are device-only. Until T162, T166 and T167 are done, ship guest mode only.

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. US1 → validate → demo (MVP)
3. US2 → validate on real hardware (Scenario 5) → demo
4. Durability → the sync machinery and the API exist and are tested
5. Infrastructure & Identity (Phase 10) → the backup is actually provisioned, actually restorable, and actually reachable by a signed-in farmer → **first build safe for a real farmer**
5. US3, US4, US5 → each adds value without breaking what came before
6. Polish → ship

### Parallel Team Strategy

With two developers, after Foundational: one takes the story phases in priority order; the other takes Phase 8 end to end, since it lives almost entirely in `api/` and `app/lib/data/sync/`. They meet at T145 (sync status on the home screen), which touches US3's surface.

---

## Notes

- `[P]` = different files, no dependency on incomplete work
- `[Story]` maps a task to a user story; Setup, Foundational, Durability, and Polish phases carry none by design
- Tests are written first and must fail before implementation
- Commit after each task or logical group
- Stop at any checkpoint to validate a story independently
- Three invariants are load-bearing and easy to break silently: integer-only money (T010, T148), the one-transaction outbox write (T030), and account isolation from the token alone (T119, T121)
