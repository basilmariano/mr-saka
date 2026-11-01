# Specification Quality Checklist: Crop Tracking for Rice and Corn Farmers

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-11-01
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`

### Validation iteration 1 — 2026-11-01

**Failing item**: "No [NEEDS CLARIFICATION] markers remain" — 2 markers outstanding:

1. **FR-008** (field occupancy): is a field free for the next cropping once the previous one is marked *harvested*, or only once it is *closed*?
2. **FR-019** (reminder delivery): must the reminder reach the farmer outside the app, and with what lead time?

All other criteria passed.

### Validation iteration 2 — 2026-11-01

Both markers resolved by documented default rather than by the farmer, so the spec is complete and unblocked. **Revisit these two first in `/speckit-clarify` if either default is wrong** — each is cheap to change now and expensive to change after planning.

1. **Field occupancy → a field is free once its cropping is marked harvested** (FR-008, FR-008a, FR-008b). Recording sales never blocks the next planting; the farmer is prompted but not forced to close the previous cropping. Chosen because the alternative (free only once closed) blocks a farmer who has not finished selling, which pushes them to close early and lose sales tracking.
2. **Reminders are device-scheduled, 2 days before the due date and again on the due date, switchable off** (FR-019, FR-019a, FR-019b). Chosen because an alert that only appears when the farmer opens the app is not a reminder, and SC-005 (90% of applications actioned within 3 days of due) is not credible without out-of-app delivery.

Both decisions are recorded in the Assumptions section, and are covered by acceptance scenarios and edge cases.

### Validation iteration 3 — 2026-11-01

**Decision 1 confirmed by the farmer, with a correction**: freeing the field at harvest must not be read as finishing the cropping. A harvested cropping keeps accepting post-harvest expenses (threshing, drying, hauling, storage) and sales until the farmer closes it. The spec was extended accordingly:

- **FR-012a–FR-012c**: a harvested cropping stays open for recording; closing is a deliberate act meaning no further costs or sales are expected; closing with unsold quantity warns first.
- **FR-031a–FR-031c**, **FR-038a–FR-038b**: post-harvest expenses and sales are accepted while the cropping is open, and when a field has two open croppings the farmer must pick which one a cost or sale belongs to — identified by crop, season, and planting date, never by field alone. This is the direct consequence of allowing replanting before closing, and the main correctness risk in the feature.
- **FR-042a–FR-042b**: a harvested but open cropping's result is labelled provisional and recalculates as costs and sales arrive; only a closed cropping's result is final.
- **FR-046a–FR-046b**: harvested-but-unclosed croppings stay on the home screen with their unsold quantity so they are not forgotten after the field is replanted.
- **SC-011**, **SC-012**: no cost lands on the wrong cropping; no provisional result is presented as final.

Spec now carries 66 functional requirements and 12 success criteria. Re-validated: all 16 criteria still pass.

**Items passed with a note**:

- *No implementation details*: "home screen", "offline / no network connection", "device-scheduled reminder" and "50 kg bags" are user-facing concepts in the farmer's own vocabulary, not technology choices. No platform, framework, storage mechanism, or API is named anywhere in the spec.
- *Requirements testable and unambiguous*: verified across all 54 functional requirements.

**Result**: 16/16 pass. Ready for `/speckit-plan`.

### Re-validation after `/speckit-clarify` — 2026-11-01

Five clarifications integrated (see `## Clarifications` in spec.md). All 16 checkbox items re-evaluated against the updated spec: **16/16 still passing, no regressions, no newly passing items** (the checklist was already full before this session).

Notes on items that came close to regressing:

- *No implementation details*: the farmer named AWS DynamoDB as the storage technology. That name is confined to the `## Clarifications` record and marked as a `plan.md` concern; the requirements it produced (FR-051 to FR-054, FR-053a to FR-053e) describe durability, restore, sync, and isolation as capabilities, naming no vendor, product, or protocol. Item still passes.
- *Requirements testable and unambiguous*: re-verified across all 84 functional requirements, including the 19 added or rewritten this session.
- *Scope is clearly bounded*: Out of Scope (v1) gained three entries — non-English languages and the in-app language switch (phase 2), and mixed wet/dry disposal of one cropping.

**Known gap, not covered by a checklist item** — the question quota was reached before it could be asked:

- **FR-011** lists four statuses advancing planted → growing → harvested → closed. FR-012 sets *harvested* when a harvest is recorded, and the farmer sets *closed* deliberately (FR-012b), but nothing in the spec says what moves a cropping from *planted* to *growing*. Resolve before or during `/speckit-plan`: either the farmer advances it, it advances automatically after a set number of days, or *growing* becomes a display state derived from the planting date rather than a stored status.

### Re-validation after post-quota clarifications — 2026-11-01

Two items flagged as unresolved in the previous pass were answered by the farmer and integrated. All 16 checkbox items re-evaluated: **16/16 still passing, no regressions.**

1. **`planted` → `growing` transition closed** (FR-011a to FR-011c): whichever comes first, the first fertilizer application marked done or 10 days after the planting date. The 10-day fallback means a cropping never sits in *planted* all season because the farmer skipped the basal application. Determined on-device so it still advances offline. Two edge cases added.

2. **Sign-in added to v1, with guest mode** (FR-058 to FR-067): this resolves the ownership gap that cloud storage opened — records are tied to an account (FR-054, FR-062) rather than to whichever device created them. Guest mode keeps the trial path open, with guest records device-only and migrated intact on sign-up (FR-061, SC-016).

**Scope boundary moved, deliberately and narrowly**: the original description put "multiple users/logins" out of scope. Accounts are now in scope; *team sharing* — multiple people on one farm, roles, permissions, shared fields — remains out. Out of Scope (v1) and FR-048 were rewritten to draw that line, and a note was added under the Input block so the superseded original text cannot mislead a later reader. The *Scope is clearly bounded* item was re-checked specifically against this change and still passes.

**Consequences now specified rather than left implicit**: guest records have no device-loss protection and the app must say so (FR-060); a forgotten credential must not destroy a history (FR-066); an existing session must keep working offline (FR-065), which matters because sign-in would otherwise undermine the offline-first decision from the clarify session.

**Open decision carried to `plan.md`, not a spec gap**: the sign-in *method*. The spec requires an account and a recovery route without naming a mechanism. Many Philippine farmers have a phone number and no email address, so phone-based or social sign-in likely fits better than email and password. Recorded under Assumptions.

Spec now carries 97 functional requirements and 18 success criteria.

### Re-validation after `/speckit-plan` revisions — 2026-11-01

Two decisions landed after the plan was first written. Spec re-checked against both: **16/16 still passing, no regressions.**

1. **Flutter for Android and iOS**, replacing the Android-only native recommendation. This is a plan-level choice and touched no requirement — the spec names no platform, which is why the reversal cost nothing in `spec.md`. `research.md` R1 records the superseded reasoning rather than deleting it, so the trade-off being accepted stays visible.

2. **Agronomic data becomes published, attributed, updatable content** rather than hardcoded constants. This *did* add farmer-visible behaviour, so five requirements were added (FR-026a to FR-026e): provenance shown to the farmer, updates without an app release, farmer edits preserved across updates, all-or-nothing application, and reference data available to guests.

**Scope boundary drawn, deliberately**: the CRM through which PhilRice and BPI would author this data is **not** in feature 001. It is now listed under Out of Scope (v1) and flagged as planned feature 002. The reasoning: it serves a different class of user (agronomists publishing for everyone, not one farmer managing their own fields), it is a separate web surface rather than a screen in the phone app, and v1 ships usefully without it. Folding a multi-tenant editorial tool into a spec that explicitly excludes team access would have broken a boundary this checklist has been holding since the first pass. The *Scope is clearly bounded* item was re-checked specifically against this and still passes.

**Risk newly on the record, not newly created**: FR-026c is the rule that stops a routine data refresh from silently discarding the advice a farmer's local agriculturist gave them. Quickstart Scenario 11 exists solely to test it.

Spec now carries 102 functional requirements and 18 success criteria.

### Re-validation after `/speckit-clarify` session 2 — 2026-11-01

Two clarifications integrated (infrastructure-as-code and server-side restore were recorded first; this pass covers the restore window and sync-outage recovery). All 16 checkbox items re-evaluated: **16/16 still passing, no regressions, no newly passing items.**

Notes on the items that came closest to regressing:

- *No implementation details*: the farmer named Terraform, API Gateway, Lambda and DynamoDB. As with the earlier DynamoDB mention, those names are confined to the `## Clarifications` record and explicitly marked a `plan.md` concern. The requirements they produced (FR-053f, FR-053g, SC-014, SC-019) describe restore depth and outage recovery as capabilities — a different host or a different IaC tool would not change a single word of them. Item still passes.
- *Success criteria are measurable*: SC-019 names both restore depths (any moment in 35 days, any month end in 12 months) and the completeness bar (100% of a test account's records unchanged), so it can be failed by a real restore drill rather than by opinion. SC-014's new sentence does the same for an outage of any length.
- *Scope is clearly bounded*: Out of Scope (v1) gained one entry — operator-side alerting and on-call monitoring of sync health. Re-checked specifically: the boundary holds because recovery does not depend on anyone noticing (FR-053g), and the one person who can act during an outage — the farmer holding the unsynced records — is still told (FR-053c).

**No implementation work is owed by FR-053g**: `RetryPolicy` already backs off to a six-hour cap and retries indefinitely, and `attempts` is used only to decide when to warn the farmer, never to abandon a record. The requirement pins behaviour that exists rather than asking for new behaviour.

**Implementation work IS owed by FR-053f**: the Terraform currently configures point-in-time recovery (35 days) only. The monthly copies kept for 12 months are not provisioned yet.

Spec now carries 104 functional requirements and 19 success criteria.
