# Phase 1 Data Model: Crop Tracking for Rice and Corn Farmers

**Feature**: `001-crop-tracking` | **Date**: 2026-11-01 | **Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

All identifiers are client-generated UUIDv4, assigned on the device before the record is saved. This is what makes sync retries idempotent (R3) and what lets guest records migrate into an account without being rewritten (FR-061).

Types below are Dart. `int` is 64-bit on Android and iOS; see the warning under *Units and value types*.

## Units and value types

Defined once in `lib/domain/model`, used everywhere. No raw `int` or `double` crosses a layer boundary for these quantities — each is a wrapper type, so a bare number cannot be passed where a currency was meant.

| Type | Stored as | Display | Why |
|---|---|---|---|
| `Centavos` | `int` | PHP with 2 decimals | SC-009 — binary floating point drifts on repeated addition and the farmer's calculator is right (R5) |
| `Grams` | `int` | kg (1 dp), tons (2 dp) | FR-032 allows non-whole average kg per sack |
| `SquareMetres` | `int` | hectares (2 dp) | FR-001 allows 2.5 ha; FR-016 multiplies area by a rate, so area must be exact |
| `DateTime` (date-only) | ISO-8601 string | locale-formatted | Dates are calendar dates; no time-of-day anywhere (spec Assumptions) |

**Rounding rule** (stated once, in `lib/domain/calc`): all arithmetic is exact integer arithmetic; rounding happens only when formatting for display, half-up. No intermediate result is ever rounded.

> ⚠️ **Dart `int` is 64-bit on Android and iOS, but is a JavaScript double on Flutter web.** Every type in this table depends on that. Compiling this app for web would silently convert all money and weight values to floating point and break SC-009 with no error anywhere. **Do not add a web target without replacing these types first** (research.md R1, R5).

---

## Entities

### FarmerAccount
FR-058 to FR-067. Not stored in DynamoDB — it *is* the Cognito user; the local row caches what the app needs offline.

| Field | Type | Rules |
|---|---|---|
| `accountId` | String? | Cognito `sub`. **Null means guest** (FR-059). Every other table carries this value. |
| `signInMethod` | Enum | `GOOGLE`, `EMAIL`, `GUEST` |
| `lastSyncedAt` | Instant? | Drives FR-053b ("last successful sync") |

**Guest → account migration (FR-061)**: on sign-up, set `accountId` on every local row and enqueue all of them to the outbox. Nothing is re-keyed, because ids were client-generated from the start.

---

### Field
FR-001 to FR-005.

| Field | Type | Rules |
|---|---|---|
| `id` | UUID | |
| `name` | String | Required, non-blank. Duplicates allowed (spec edge case) |
| `areaSqm` | SquareMetres | **> 0** (FR-002) |
| `location`, `notes` | String? | Optional (FR-001) |
| `archived` | Boolean | FR-004 — a field with croppings is archived, never deleted |

**Relationship**: one Field → many Croppings.

---

### Cropping
FR-006 to FR-013. The central entity.

| Field | Type | Rules |
|---|---|---|
| `id` | UUID | |
| `fieldId` | UUID | |
| `crop` | Enum | `RICE`, `CORN` |
| `varietyId` | UUID | |
| `plantingMethod` | Enum | `TRANSPLANTED`, `DIRECT_SEEDED`. Rice offers both; corn offers `DIRECT_SEEDED` only (FR-007, spec Assumptions) |
| `growingSeason` | Enum | `WET`, `DRY` — **when it was planted** |
| `plantingDate` | LocalDate | |
| `expectedHarvestDate` | LocalDate | Derived (FR-009); `expectedHarvestOverridden` records farmer override |
| `status` | Enum | See state machine below |
| `saleWeightBasis` | Enum? | `WET`, `DRY` — **how the produce was sold**. Null until the first sale (FR-034a) |
| `driedWeightGrams` | Grams? | Required when `saleWeightBasis == DRY` (FR-034b) |

> **`growingSeason` and `saleWeightBasis` are both "wet or dry" and are independent.** A dry-season cropping can be sold wet. They are never stored in, or read from, the same column, and the UI labels each (spec Assumptions: "Season has two meanings, kept distinct"). This is the single most likely place to introduce a silent bug.

**Derived, never stored** (recomputed so they cannot drift):
- `sellableQuantityGrams` = harvest fresh weight when sold wet, `driedWeightGrams` when sold dry (FR-034c)
- `remainingQuantityGrams` = `sellableQuantity − Σ sales` (FR-036)
- totals, profit, yield, cost per kg (FR-039, FR-040)

#### Status state machine (FR-011 to FR-013)

```
          ┌─────────┐
          │ PLANTED │
          └────┬────┘
               │  first fertilizer application marked done
               │  OR 10 days after plantingDate — whichever first   (FR-011a)
               ▼
          ┌─────────┐
          │ GROWING │
          └────┬────┘
               │  harvest recorded                                  (FR-012)
               ▼
          ┌───────────┐   farmer closes, deliberately    ┌────────┐
          │ HARVESTED │ ────────────────────────────────▶│ CLOSED │
          └───────────┘                      (FR-012b)   └───┬────┘
                ▲                                            │
                └────────────────────────────────────────────┘
                              farmer reopens (FR-013)
```

Rules the implementation must enforce:

- **`PLANTED → GROWING` is evaluated on-device with no network** (FR-011b) — a date comparison plus an application check, run on app open and by the daily reconciliation worker.
- **A cropping created with a planting date already >10 days past starts in `GROWING`** (FR-011c).
- **`HARVESTED` frees the field but does not close the books** (FR-012a). The field accepts a new cropping; this one keeps accepting expenses and sales.
- **Closing is never automatic** — not on harvest, not on a date, not when remaining hits zero (FR-012b). Closing with unsold stock warns first (FR-012c).
- **`CLOSED` rejects writes** until reopened (FR-013).

#### Field occupancy (FR-008, FR-008a, FR-008b)

A field may hold **at most one cropping in `PLANTED` or `GROWING`** — that is "in the ground". It may *simultaneously* hold one in `HARVESTED`. So a field can legitimately have two open croppings, which is why **expenses and sales attach to a cropping, never to a field** (FR-031b, FR-038b). Any picker showing an open cropping must disambiguate by crop + growing season + planting date (FR-031c).

---

### Variety
FR-010. Bundled set (R9) plus farmer additions.

| Field | Type | Rules |
|---|---|---|
| `id` | UUID | |
| `name` | String | |
| `crop` | Enum | `RICE`, `CORN` |
| `maturityDays` | Int? | **Null is meaningful** — the farmer must then enter the expected harvest date manually (spec edge case) |
| `source` | Enum | `SEED`, `PUBLISHED`, `FARMER` — see provenance rule below |
| `sourceAttribution` | String? | e.g. "PhilRice, 2026 rice varietal guide". Required for `SEED` and `PUBLISHED` |
| `bundleVersion` | Int? | Which reference bundle supplied it; null for `FARMER`

---

### FertilizerTemplate / FertilizerTemplateStep
FR-014, FR-015, FR-024, FR-025.

Template is keyed by `(crop, plantingMethod)`. Steps carry `daysAfterPlanting`, `growthStage`, `product`, `ratePerHectareGrams`, `sortOrder`. The template also carries `source`, `sourceAttribution`, and `bundleVersion`, as Variety does.

**Template edits are forward-looking only** (FR-025): a cropping's schedule is a snapshot taken at creation. Editing a template must never touch an existing `ScheduledApplication` row.

---

### ReferenceBundle
R9, R10. Versioned agronomic data published by PhilRice / BPI.

| Field | Type | Rules |
|---|---|---|
| `version` | Int | Monotonically increasing. Immutable once published |
| `publishedAt` | DateTime | |
| `varieties`, `templates` | collections | The payload |

**The provenance rule — the single most important rule in this file after the wet/dry distinction:**

```
applying bundle N:
  rows with source == FARMER   → untouched, always
  rows with source == SEED     → replaced
  rows with source == PUBLISHED→ replaced
  applied in ONE transaction — a half-applied template produces wrong bag counts
```

A farmer who followed their agriculturist's advice and edited a template (FR-024) must never have that edit silently discarded by a routine data refresh. Combined with FR-025 (running croppings keep their snapshot), a farmer's deliberate choices survive both template edits and bundle updates.

**Out of scope here**: the CRM that lets PhilRice and BPI author these bundles is **feature 002**. v1 consumes bundles; it does not produce them.

---

### ScheduledApplication
FR-014 to FR-023. A template step instantiated for one cropping.

| Field | Type | Rules |
|---|---|---|
| `id` | UUID | |
| `croppingId` | UUID | |
| `daysAfterPlanting` | Int | |
| `growthStage`, `recommendedProduct` | String | Snapshot from the template |
| `ratePerHectareGrams` | Grams | Snapshot |
| `state` | Enum | `PENDING`, `DONE`, `SKIPPED` |
| `actualDate`, `actualProduct`, `actualQuantityGrams`, `costCentavos` | nullable | Set when `DONE` (FR-020) |
| `skipReason` | String? | FR-022 |
| `linkedExpenseId` | UUID? | FR-021 |

**Derived**: `dueDate` = `plantingDate + daysAfterPlanting` (FR-017); `recommendedQuantityGrams` = `ratePerHectare × fieldArea` (FR-016), displayed in kg **and** 50 kg bags to 1 dp.

**The expense link (FR-021) is the sharpest correctness rule here.** Recording a cost creates exactly one Expense in the `FERTILIZER` category; editing the cost updates that same Expense; deleting the application deletes it. The cost must never be counted twice and must never be orphaned — SC-006 asserts exactly this.

**Recalculation triggers**: changing `plantingDate` shifts `dueDate` for non-`DONE` steps and reschedules their alarms; changing the field's `areaSqm` recalculates `recommendedQuantityGrams` for non-`DONE` steps. Neither touches recorded actuals (spec edge cases).

---

### Expense
FR-027 to FR-031c.

| Field | Type | Rules |
|---|---|---|
| `id` | UUID | |
| `croppingId` | UUID | **Never `fieldId`** — see field occupancy above |
| `date` | LocalDate | May precede `plantingDate` (land prep) and may follow the harvest date (FR-031a). Both are normal; neither warns |
| `category` | Enum | The ten in FR-028. Post-harvest costs reuse them (spec Assumptions) |
| `amountCentavos` | Centavos | > 0 |
| `notes` | String? | |
| `linkedApplicationId` | UUID? | Set when auto-created by FR-021 |

---

### Harvest
FR-032, FR-033. **One per cropping** (spec Assumptions).

| Field | Type | Rules |
|---|---|---|
| `id`, `croppingId` | UUID | |
| `date` | LocalDate | |
| `sacks` / `avgWetGramsPerSack` **or** `totalWetGrams` | | Either input form; both resolve to `totalWetGrams` |
| `totalWetGrams` | Grams | **Always fresh weight** (FR-032, FR-032a). ≥ 0 — zero is a valid total crop failure |

**Derived**: tons = `totalWetGrams / 1_000_000`; tons/ha = tons ÷ hectares (FR-033) — both labelled fresh weight.

---

### Sale
FR-034 to FR-038b.

| Field | Type | Rules |
|---|---|---|
| `id`, `croppingId` | UUID | |
| `quantityGrams` | Grams | On the cropping's `saleWeightBasis` — **not** its own basis |
| `pricePerKgCentavos` | Centavos | |
| `buyer` | String | |
| `date` | LocalDate | |

**Validation**: rejected if the cropping has no Harvest (FR-037); rejected if `quantityGrams` exceeds `remainingQuantityGrams` (FR-037); if basis is `DRY`, rejected until `driedWeightGrams` is recorded (spec edge case). **Dry grams are never subtracted from a fresh harvest weight** (FR-037a).

---

### OutboxEntry
R3. Local only — never leaves the device as data.

| Field | Type | Purpose |
|---|---|---|
| `seq` | `int`, autoincrement | Strict ordering (FR-053e) |
| `entityType`, `entityId` | | What to send |
| `operation` | Enum | `UPSERT`, `DELETE` |
| `payload` | JSON | Snapshot at write time |
| `attempts`, `lastError` | | Drives FR-053c surfacing **only**. Never a give-up threshold — FR-053g requires retries to continue indefinitely |

**Invariant**: the domain write and the outbox append happen in **one Drift transaction**. If either fails, both roll back. This is what makes "saved" and "queued" atomic (R3).

---

## Calculations (all in `lib/domain/calc`, all integer)

| Output | Formula | Spec |
|---|---|---|
| Recommended quantity | `ratePerHectareGrams × areaSqm / 10_000` | FR-016 |
| Bags | `quantityGrams × 10 / 50_000` → scaled by 10, giving 1 dp | FR-016 |
| Due date | `plantingDate + daysAfterPlanting` | FR-017 |
| Expected harvest | `plantingDate + variety.maturityDays` | FR-009 |
| Total expenses | `Σ expense.amountCentavos` | FR-029 |
| Category share | `categoryTotal × 100 / total` | FR-030 |
| Tons | `totalWetGrams / 1_000_000` | FR-033 |
| Tons per hectare | `tons ÷ (areaSqm / 10_000)` | FR-033 |
| Revenue | `Σ (quantityGrams × pricePerKgCentavos / 1000)` | FR-035 |
| Remaining | `sellableQuantityGrams − Σ sale.quantityGrams` | FR-036 |
| Net profit | `revenue − totalExpenses` | FR-040 |
| Cost per kg | `totalExpenses × 1000 / totalWetGrams` | FR-040 |
| Cost per kg when harvest = 0 | **Not applicable** — never a division error | FR-041 |

**Result state** (FR-042, FR-042a, FR-042b): `IN_PROGRESS` before harvest (expenses only, never shown as a loss) → `PROVISIONAL` while harvested and open (recalculates as costs and sales land) → `FINAL` once closed.

---

## Persistence mapping

Drift tables mirror these entities one-to-one, plus `outbox`. DynamoDB uses the single-table design in R7, with `PK = ACCOUNT#<sub>` built **only** from the verified JWT claim (FR-062) — never from the request body.

Every synced record also carries `accountId`, `updatedAt`, and `deleted` (soft delete, so a deletion made offline propagates rather than being lost on the next full download).
