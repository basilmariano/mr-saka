# Feature Specification: Crop Tracking for Rice and Corn Farmers

**Feature Branch**: `001-crop-tracking` *(no git repository initialised; feature directory only)*

**Feature Directory**: `specs/001-crop-tracking`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Build a crop tracking app for rice and corn farmers. The goal is for a farmer to know, for every cropping on every field, how much they spent, how much they earned after harvest, and how many tons they harvested. v1 is for a single farmer managing their own fields (no accounts or team sharing). Covers fields, croppings, fertilizer schedules and recommendations, expenses, harvest and sales, and per-cropping results and comparisons. Out of scope for v1: multiple users/logins, weather data, market price feeds, pest and disease diagnosis, accounting or tax reports."

> The Input above is the original request, kept verbatim. Two of its statements have since been superseded by the farmer: storage is now a remote database rather than device-only, and v1 now includes sign-in with an optional guest mode. Team sharing remains out of scope. See `## Clarifications` for both decisions.

## Clarifications

### Session 2026-11-01

- Q: What should happen to a farmer's records if their phone is lost, stolen, broken, or replaced? (FR-049, FR-050) → A: Records are stored in a remote cloud database, written when the farmer saves, so a lost or replaced device does not lose the history. *(Implementation choice named by the farmer: AWS DynamoDB — carried into `plan.md`; the requirements below stay technology-agnostic.)* Consequence for offline operation is resolved in the next clarification.
- Q: When the farmer taps Save out in the field and there's no mobile signal, what should the app do? (FR-050, FR-053, SC-010) → A: Save locally immediately, then sync to the cloud in the background when signal returns; entries show as pending until stored. The app is offline-first, with remote storage as the durable copy rather than the live front-line store.
- Q: When the farmer records the harvest in sacks and kilograms, is that weight straight from the field or after drying? (FR-032, FR-033, FR-040) → A: The harvest is always recorded as fresh/wet weight — average wet kilograms per sack. A sale is recorded at the weight actually transacted, so produce sold after drying is recorded at its dry weight; whether a cropping is sold wet or dry is settled in the next clarification.
- Q: How should the remaining unsold quantity be worked out when the harvest is recorded wet but some of it was sold dry? (FR-036, FR-037) → A: Farmers normally sell a whole lot as either wet or dry, not split between the two. So the weight basis is declared once per cropping rather than per sale. Sold wet, remaining counts down from the wet harvest; sold dry, the farmer records the lot's dried weight once and remaining counts down from that. Either way both sides of the subtraction are on the same basis.
- Q: What language should the app's screens and built-in content be in? (SC-008, FR-028, FR-015) → A: English only in v1. Switching to the farmer's local language is planned for phase 2, so v1 must be built so an additional language can be added without reworking screens or behaviour.
- Q: What moves a cropping from planted to growing? (FR-011) → A: Whichever comes first — the first fertilizer application being marked done, or 10 days after the planting date.
- Q: With records in a shared remote database and no login, how is one farmer's data kept separate? (FR-054) → A: Add sign-in to v1. A farmer may also continue as a guest to try the app, with guest records kept on the device only and migrated into an account if they later sign up. Accounts establish ownership; they do not introduce team sharing, which stays out of scope.
- Q: How is the remote storage to be provisioned and run? (FR-049, FR-050, FR-062) → A: Infrastructure as code in Terraform, deploying API Gateway + Lambda + DynamoDB. *(Implementation choice named by the farmer — carried into `plan.md` and `research.md`; the requirements below stay technology-agnostic, so a different host would not change a single FR.)*
- Q: If a server-side mistake damages or deletes a farmer's cloud records, how far back must we be able to restore them? (SC-013, FR-049) → A: Any point in the last 35 days, plus a monthly copy kept for 12 months. A season runs about four months and farmers compare across seasons, so a 35-day window alone can expire before anyone notices the damage.
- Q: When syncing starts failing for many farmers at once — a bad release, an outage — how should whoever runs the service find out? (FR-053c) → A: No operator alerting in v1 — they can just resync again. A failed sync is self-healing: the record stays queued on the device and the app keeps retrying, so when the service returns the backlog drains on its own. This holds only because retries never give up and queued records are never dropped (FR-053d, FR-053g); operator-side alerting is out of scope below.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Know the bottom line for one cropping (Priority: P1)

A farmer sets up a field, starts a cropping on it, logs what they spend as the season goes, records the harvest, keeps logging the costs that land after it — threshing, drying, hauling — records the sales as the produce moves, and sees exactly how much they spent, how much they earned, whether they made or lost money, and how many tons they produced per hectare. The cropping stays open until the farmer says it is finished.

**Why this priority**: This is the stated goal of the app. Everything else exists to feed or explain these numbers. A farmer who can only do this still gets the full value proposition for one season.

**Independent Test**: Create a field, start a cropping, add several expenses across different categories, record a harvest, add a post-harvest hauling cost, record one sale, then open the cropping result. The result shows total expenses (including the post-harvest cost), total revenue, net profit or loss, total tons, tons per hectare, and cost per kilogram — all derived, with no manual arithmetic by the farmer — and is labelled provisional until the farmer closes the cropping.

**Acceptance Scenarios**:

1. **Given** no fields exist, **When** the farmer adds a field named "Field 1" with area 2.5 ha, **Then** the field appears in the field list showing its name and area.
2. **Given** a field with no active cropping, **When** the farmer starts a cropping choosing crop, variety, planting method, season, and planting date, **Then** the cropping is created with status "planted" and shows a calculated expected harvest date.
3. **Given** an active cropping, **When** the farmer logs an expense of PHP 3,500 in the "labor" category, **Then** the cropping's running expense total increases by exactly PHP 3,500 and the labor category shows PHP 3,500 in the breakdown.
4. **Given** an active cropping on a 2.5 ha field, **When** the farmer records a harvest of 100 sacks at an average of 50 kg per sack, **Then** the cropping shows 5 tons total and 2 tons per hectare, and the status becomes "harvested".
5. **Given** a harvested cropping with 5,000 kg and total expenses of PHP 60,000, **When** the farmer records a sale of 4,000 kg at PHP 20.00 per kg, **Then** revenue shows PHP 80,000, net profit shows PHP 20,000, remaining unsold quantity shows 1,000 kg, and cost per kilogram produced shows PHP 12.00.
6. **Given** a cropping with no harvest recorded yet, **When** the farmer opens its result, **Then** expenses to date are shown and the result is clearly labelled as in progress rather than showing a misleading loss.
7. **Given** a harvested cropping showing a provisional profit of PHP 20,000, **When** the farmer logs PHP 4,000 of hauling 5 days after the harvest date, **Then** the expense is accepted, total expenses rise to PHP 64,000, and the provisional profit falls to PHP 16,000.
8. **Given** a field with a harvested-but-open cropping and a newly planted cropping, **When** the farmer logs an expense on that field, **Then** the app asks which of the two croppings it belongs to, identifying each by crop, season, and planting date.
9. **Given** a harvested cropping with 1,000 kg still unsold, **When** the farmer closes it, **Then** the app shows the 1,000 kg and asks for confirmation, and after closing the result is marked final and rejects further expenses and sales.

---

### User Story 2 - Follow a fertilizer schedule sized to the field (Priority: P2)

When a cropping starts, the farmer gets a ready-made fertilizer schedule for that crop and planting method, with each application already converted from a per-hectare rate into the number of 50 kg bags to buy for that specific field. The farmer is reminded before each application is due, and marks each one done with what was actually applied and what it cost.

**Why this priority**: This is what turns the app from a ledger into a daily tool. It removes the arithmetic farmers get wrong most often (per-hectare rate to bags) and captures the single largest input cost without the farmer having to remember to log it separately.

**Independent Test**: Start a cropping on a 2.5 ha field and open its fertilizer schedule. Every step shows a growth stage, a due date derived from the planting date, and a quantity in both kilograms and 50 kg bags scaled to 2.5 ha. Mark one step done with a cost and confirm a matching fertilizer expense appears on the cropping without being entered twice.

**Acceptance Scenarios**:

1. **Given** a new cropping of transplanted rice on a 2.5 ha field, **When** the farmer opens the fertilizer schedule, **Then** the schedule lists steps from the matching template, each with its growth stage, days after planting, recommended product, and per-hectare rate.
2. **Given** a schedule step recommending 100 kg/ha of Urea 46-0-0 on a 2.5 ha field, **When** the farmer views that step, **Then** it shows 250 kg and 5.0 bags of 50 kg.
3. **Given** a cropping planted on 1 March with a step timed at 14 days after planting, **When** the farmer views the schedule, **Then** that step shows a due date of 15 March.
4. **Given** a pending step due on 15 March, **When** 13 March arrives, **Then** the farmer is reminded that the application is due in 2 days, without having to open the app first.
5. **Given** a pending schedule step, **When** the farmer marks it done with actual date, product, quantity, and a cost of PHP 7,500, **Then** the step shows as completed and a PHP 7,500 expense appears in the fertilizer category of that cropping.
6. **Given** a completed step with a recorded cost, **When** the farmer edits the cost to PHP 8,000, **Then** the linked expense updates to PHP 8,000 and the cropping's expense total reflects the change exactly once.
7. **Given** a step whose due date has passed and which is not marked done, **When** the farmer views the schedule, **Then** that step is flagged as overdue.
8. **Given** any screen showing a fertilizer recommendation, **When** the farmer views it, **Then** a statement is visible that the recommendation is general guidance and should be adjusted to soil test results or local agricultural advice.

---

### User Story 3 - See what needs attention right now (Priority: P3)

Opening the app shows the farmer, without any navigation, which croppings are active, which fertilizer applications are due next, and which harvests are coming up.

**Why this priority**: The schedule and reminders in P2 only change behaviour if the farmer encounters them without going looking. This is the surface that makes the app worth opening daily, but it has no value until there are croppings and schedules to surface.

**Independent Test**: With two active croppings on different fields, open the home screen and confirm both appear with their status, that the nearest-due fertilizer applications across both are listed in date order, and that a cropping whose expected harvest date is approaching is shown.

**Acceptance Scenarios**:

1. **Given** two active croppings and one closed cropping, **When** the farmer opens the home screen, **Then** only the two active croppings are shown, each with its field name, crop, status, and days since planting.
2. **Given** pending fertilizer applications across several croppings, **When** the farmer opens the home screen, **Then** the next applications due are listed in due-date order with field name, product, and quantity in bags.
3. **Given** a cropping whose expected harvest date falls within the upcoming window, **When** the farmer opens the home screen, **Then** that cropping is listed under upcoming harvests with its expected date.
4. **Given** no active croppings, **When** the farmer opens the home screen, **Then** an empty state invites the farmer to start a cropping rather than showing blank sections.

---

### User Story 4 - Compare seasons and fields (Priority: P4)

The farmer looks back across past croppings to answer questions like "did direct-seeding beat transplanting on Field 1?", "was the dry season better than the wet season?", and "which field actually makes money?".

**Why this priority**: This is the long-term payoff for keeping records, and the reason a farmer keeps using the app past the first season. It depends entirely on P1 having accumulated closed croppings.

**Independent Test**: With at least three closed croppings spanning two fields and two seasons, open the comparison view and confirm each cropping's expenses, revenue, profit, tons, tons per hectare, and cost per kilogram can be seen side by side and filtered by field, crop, and season.

**Acceptance Scenarios**:

1. **Given** several closed croppings, **When** the farmer opens the comparison view, **Then** each cropping is listed with field, crop, variety, season, planting date, expenses, revenue, net profit or loss, tons, tons per hectare, and cost per kilogram.
2. **Given** the comparison view, **When** the farmer filters to a single field, **Then** only that field's croppings are shown, ordered by planting date.
3. **Given** the comparison view, **When** the farmer filters to the dry season, **Then** only dry-season croppings across all fields are shown.
4. **Given** a field with past croppings, **When** the farmer opens that field, **Then** its full cropping history is shown with each cropping's result summary.

---

### User Story 5 - Adjust the fertilizer recommendations (Priority: P5)

The farmer's soil test or local agriculturist says something different from the built-in recommendation, so the farmer changes the template so future croppings follow their own practice.

**Why this priority**: Important for trust and for farmers who already have specific advice, but the built-in templates are usable as shipped, so this can follow the core loop.

**Independent Test**: Edit a crop's fertilizer template — change a rate, add a step, remove a step — then start a new cropping for that crop and confirm the new schedule reflects the edits while an already-running cropping's schedule is unchanged.

**Acceptance Scenarios**:

1. **Given** the template for direct-seeded rice, **When** the farmer changes a step's rate from 100 kg/ha to 120 kg/ha, **Then** a newly started direct-seeded rice cropping shows the step at 120 kg/ha scaled to its field area.
2. **Given** an edited template, **When** the farmer views an already-active cropping started before the edit, **Then** that cropping's schedule is unchanged.
3. **Given** an active cropping, **When** the farmer edits one of its own schedule steps, **Then** only that cropping's schedule changes and the template is unaffected.
4. **Given** a template, **When** the farmer adds a step with a growth stage, timing, product, and rate, **Then** the step appears in the template in timing order.

---

### Edge Cases

- **Field already busy**: The farmer tries to start a cropping on a field whose previous cropping is still growing. The system refuses and explains which cropping is occupying the field.
- **Replanting before closing the books**: The farmer harvests, then plants the next season while still selling the previous harvest. The new cropping is allowed, the farmer is prompted (but not forced) to close the old one, and both croppings remain distinguishable everywhere the field is shown.
- **Post-harvest cost charged to the wrong cropping**: The farmer pays for hauling the previous harvest a week after replanting the same field. Because the field has two open croppings, the app makes the farmer pick which one the cost belongs to, identifying each by crop, season, and planting date rather than by field alone.
- **Profit figure moves after harvest**: A cropping shows a profit the day it is harvested, then drops as threshing, drying, and hauling costs are recorded. The result is labelled provisional until the cropping is closed, so the earlier figure is never presented as final.
- **Closing with produce still unsold**: The farmer closes a cropping with 1,000 kg kept for home use. The app shows the remaining quantity and asks for confirmation; once closed, that quantity stays on the record as unsold rather than being treated as a loss or as revenue.
- **First fertilizer application before day 10**: The farmer marks the basal application done on day 3. The cropping moves to growing that day rather than waiting for day 10.
- **No fertilizer applications at all**: A farmer who skips every scheduled application still sees the cropping move to growing on day 10, so a cropping never sits in planted for a whole season.
- **Guest loses their device**: A guest's records exist only on that device, so they are gone. The app says this plainly while the farmer is a guest rather than only at the moment of loss.
- **Guest signs up mid-season**: A guest with two fields and a season of expenses creates an account. Every record moves into the account unchanged and is then protected against device loss; nothing is re-entered.
- **Signing in on a second device**: A farmer signs in on a replacement phone and their full history appears. Because v1 has one farmer and no sharing, the app does not attempt to merge concurrent edits from two devices used at once.
- **Credentials forgotten**: A farmer who cannot sign in recovers the account rather than losing several seasons of records.
- **Reminders while offline**: A reminder falls due while the device has no connection. It still reaches the farmer, because reminders are scheduled on the device rather than sent from a server.
- **A season's worth of entries made offline**: The farmer works a field with no signal for weeks. Every entry saves normally and all of them sync once a connection returns, in the order they were made, with no entry lost and no duplicate created.
- **Device lost before entries sync**: Entries still pending sync when a device is lost are not recoverable, since remote storage has not yet received them. The app therefore syncs at the earliest opportunity and shows the pending count, so the farmer can see what is not yet protected rather than assuming everything is.
- **Sync fails repeatedly**: A sync keeps failing — expired access, a server error, a full account. The farmer is told plainly that records are not being backed up, rather than the app appearing healthy while nothing reaches remote storage.
- **Total crop failure**: The farmer records a harvest of 0 kg. Yield and tons per hectare show 0, cost per kilogram is shown as not applicable rather than a division error, and the result shows the full expenses as a loss.
- **Expenses before planting**: Land preparation is paid for weeks before the planting date. Expenses dated before the cropping's planting date are accepted without warning, because that is normal practice.
- **Planting date corrected after the schedule exists**: Changing a cropping's planting date shifts the due dates of all steps not yet marked done, and shifts the expected harvest date unless the farmer has overridden it. Completed steps keep their recorded actual dates.
- **Field area corrected mid-season**: Changing a field's area recalculates the recommended quantities of schedule steps not yet marked done and recalculates tons per hectare. Already-recorded actual quantities and costs are unchanged.
- **Selling more than was harvested**: A sale whose quantity exceeds the remaining unsold quantity is rejected with the remaining quantity shown.
- **Selling before harvesting**: Sales cannot be recorded on a cropping with no harvest recorded.
- **Pending steps at harvest time**: When a cropping is marked harvested, fertilizer steps still pending are no longer shown as due or overdue; they remain visible in the schedule as not done.
- **Variety with unknown maturity**: If the chosen variety has no typical maturity in days, the system asks the farmer to enter the expected harvest date rather than calculating one.
- **Correcting a closed cropping**: A closed cropping rejects new expenses and sales until the farmer explicitly reopens it; reopening restores editing and recalculates the result.
- **Duplicate field names**: Two fields may share a name; the system does not block it, and lists disambiguate by area and location where available.
- **Harvest recorded in sacks of uneven weight**: The farmer enters total wet kilograms directly instead of sacks × average wet kg, and all downstream figures use that total.
- **Sold dry after harvesting wet**: The farmer harvests 5,000 kg wet, dries the lot down to 4,200 kg, and sells 4,000 kg dry. The cropping is marked sold dry, its dried weight of 4,200 kg becomes the sellable quantity, remaining shows 200 kg dry, and yield and cost per kilogram stay on the 5,000 kg fresh-weight basis so the cropping remains comparable with every other cropping.
- **Basis chosen before the lot is dried**: The farmer marks a cropping as sold dry but has not yet weighed the dried lot. The app asks for the dried weight before the first dry sale can be recorded, rather than guessing a conversion.

## Requirements *(mandatory)*

### Functional Requirements

#### Fields

- **FR-001**: System MUST allow the farmer to create a field with a name and an area in hectares, and optionally a location and notes.
- **FR-002**: System MUST reject a field area that is zero, negative, or non-numeric.
- **FR-003**: System MUST allow the farmer to view and edit a field's name, area, location, and notes.
- **FR-004**: System MUST prevent permanent deletion of a field that has one or more croppings, offering to archive it instead so its history is preserved.
- **FR-005**: System MUST show, for each field, the chronological history of all its croppings with each cropping's crop, variety, season, planting date, status, and result summary.

#### Croppings

- **FR-006**: System MUST allow the farmer to start a cropping by selecting a field and specifying crop (rice or corn), variety, planting method, season (wet or dry), and planting date.
- **FR-007**: System MUST offer the planting methods valid for the chosen crop — for rice, transplanted or direct-seeded.
- **FR-008**: System MUST prevent a field from having more than one cropping in the ground at a time, where a cropping occupies its field from planting until it is marked harvested.
- **FR-008a**: System MUST allow the farmer to start a new cropping on a field whose previous cropping is harvested but not yet closed, so replanting is never blocked by outstanding sales records.
- **FR-008b**: System MUST prompt the farmer to close the previous cropping when they start a new one on the same field, while allowing them to decline and leave it open.
- **FR-009**: System MUST calculate the expected harvest date as the planting date plus the chosen variety's typical maturity in days, and MUST allow the farmer to override that date.
- **FR-010**: System MUST provide a selectable list of rice and corn varieties, each with a typical maturity in days, and MUST allow the farmer to add a custom variety with its own maturity.
- **FR-011**: System MUST track each cropping's status as one of planted, growing, harvested, or closed, advancing in that order.
- **FR-011a**: System MUST move a cropping from planted to growing at whichever comes first: the first fertilizer application on that cropping being marked done, or 10 days elapsing since the planting date.
- **FR-011b**: System MUST determine the planted-to-growing transition on the device without needing a network connection, so a cropping advances on time while the farmer is offline.
- **FR-011c**: System MUST create a cropping directly in the growing status when the farmer records it with a planting date already more than 10 days in the past.
- **FR-012**: System MUST set a cropping's status to harvested when a harvest is recorded.
- **FR-012a**: System MUST keep a harvested cropping open for recording — accepting post-harvest expenses and sales — until the farmer explicitly closes it. Being harvested frees the field; it does not close the books.
- **FR-012b**: System MUST treat closing a cropping as the farmer's declaration that no further costs or sales are expected on it, and MUST require the farmer to close it deliberately rather than closing it automatically on harvest, on a date, or when the remaining quantity reaches zero.
- **FR-012c**: System MUST warn the farmer, when they close a cropping that still has unsold remaining quantity, showing that quantity so they can confirm it is kept for home use or stock rather than unrecorded sales.
- **FR-013**: System MUST reject new expenses, sales, and schedule changes on a closed cropping, and MUST allow the farmer to reopen a closed cropping to make corrections.

#### Fertilizer schedule and recommendations

- **FR-014**: System MUST generate a fertilizer schedule for a cropping, when the cropping is started, from the template matching that crop and planting method.
- **FR-015**: Each schedule step MUST carry a timing in days after planting, a growth stage label, a recommended fertilizer product, and a recommended rate per hectare.
- **FR-016**: System MUST calculate each step's recommended quantity as the per-hectare rate multiplied by the field's area, and MUST display that quantity both in kilograms and as a number of 50 kg bags.
- **FR-017**: System MUST derive each step's due date as the cropping's planting date plus the step's days after planting.
- **FR-018**: System MUST show the farmer upcoming fertilizer applications with their due dates and MUST flag applications whose due date has passed without being marked done.
- **FR-019**: System MUST remind the farmer of each scheduled application without requiring the app to be open, delivering the reminder 2 days before the due date and again on the due date.
- **FR-019a**: System MUST allow the farmer to turn reminders off, and MUST continue to show upcoming and overdue applications in the app when reminders are off.
- **FR-019b**: System MUST NOT send a reminder for an application already marked done or skipped, or for a cropping already marked harvested or closed.
- **FR-020**: System MUST allow the farmer to mark a scheduled application as done, recording the actual date, the actual product, the actual quantity, and the cost.
- **FR-021**: System MUST create an expense in the fertilizer category on the same cropping when a cost is recorded against a completed application, and MUST keep that expense in step with later edits or deletion of the application so the cost is never counted twice or orphaned.
- **FR-022**: System MUST allow the farmer to mark a scheduled application as skipped, with an optional reason, without creating an expense.
- **FR-023**: System MUST allow the farmer to add, edit, remove, and reorder the steps of an individual cropping's schedule without affecting the template.
- **FR-024**: System MUST allow the farmer to edit the fertilizer templates — adding, editing, removing, and reordering steps — for each crop and planting method.
- **FR-025**: System MUST apply template edits only to croppings started after the edit; schedules of existing croppings MUST remain unchanged.
- **FR-026**: System MUST display, wherever a fertilizer recommendation is shown, a statement that recommendations are general guidance and should be adjusted to soil test results or local agricultural advice.
- **FR-026a**: System MUST show, for each built-in variety and fertilizer template, where its figures came from and when they were published, so a farmer can tell published agronomic guidance from their own edits.
- **FR-026b**: System MUST be able to receive updated varieties and fertilizer templates without the farmer installing a new version of the app, so corrected agronomic guidance reaches farmers who never update.
- **FR-026c**: System MUST preserve the farmer's own template and variety edits when updated guidance arrives, replacing only records the farmer has not changed.
- **FR-026d**: System MUST apply an update to varieties and templates completely or not at all, never leaving a partially updated template that would produce wrong quantities.
- **FR-026e**: System MUST provide built-in varieties and fertilizer recommendations to a farmer using the app as a guest, without an account.

#### Expenses

- **FR-027**: System MUST allow the farmer to log an expense against a cropping with a date, a category, an amount in Philippine pesos, and optional notes.
- **FR-028**: System MUST offer these expense categories: land preparation, seeds, fertilizer, pesticide/herbicide, labor, irrigation, equipment rental, harvesting/threshing, hauling, and other.
- **FR-029**: System MUST show a running total of expenses for each cropping.
- **FR-030**: System MUST show a breakdown of a cropping's expenses by category, with each category's total amount and its share of the overall total.
- **FR-031**: System MUST allow the farmer to edit and delete expenses, with the running total and category breakdown updating accordingly.
- **FR-031a**: System MUST accept expenses dated on or after a cropping's harvest date for as long as the cropping is open, so post-harvest costs such as threshing, drying, hauling, storage, and the labour attached to them are charged to the cropping that produced the harvest.
- **FR-031b**: System MUST require the farmer to choose which cropping an expense belongs to whenever the chosen field has more than one open cropping — one in the ground and one harvested but not yet closed — and MUST NOT silently default to either.
- **FR-031c**: System MUST identify each open cropping unambiguously wherever the farmer picks one, using field name together with crop, season, and planting date, so a newly planted cropping is never confused with the harvested one it follows.

#### Harvest and sales

- **FR-032**: System MUST allow the farmer to record a harvest for a cropping with a date and either a number of sacks together with an average **wet** kilograms per sack, or a total in **wet** kilograms. Harvest weight is always fresh weight as taken from the field.
- **FR-032a**: System MUST label harvest weight as fresh weight wherever it is entered or displayed, so the farmer is never unsure which basis a figure is on.
- **FR-033**: System MUST calculate the total harvest in tons and the yield in tons per hectare on the fresh-weight basis, using the field's area, and MUST label both as fresh weight.
- **FR-034**: System MUST allow the farmer to record one or more sales against a harvested cropping, each with a quantity in kilograms, a price per kilogram, a buyer, and a date.
- **FR-034a**: System MUST record, once per cropping, whether that cropping's produce is being sold wet or dry, asked when the first sale is recorded and changeable while the cropping is open.
- **FR-034b**: System MUST require the farmer to record the lot's dried weight when the cropping is sold dry, and MUST treat that dried weight as the quantity available to sell.
- **FR-034c**: System MUST define a cropping's sellable quantity as its fresh harvest weight when sold wet, and as its recorded dried weight when sold dry, so sales always count down from a quantity on their own basis.
- **FR-034d**: System MUST display the cropping's weight basis alongside its sales, quantities, and prices per kilogram, so a high price per kilogram on dry weight is not mistaken for a better deal than a lower price on wet weight.
- **FR-035**: System MUST calculate a cropping's revenue as the sum across its sales of quantity multiplied by price per kilogram.
- **FR-036**: System MUST calculate and display the remaining unsold quantity as the cropping's sellable quantity minus the total kilograms sold, with both sides on the same weight basis, and MUST show which basis that is.
- **FR-037**: System MUST reject a sale whose quantity exceeds the remaining unsold quantity, and MUST reject sales on a cropping with no recorded harvest.
- **FR-037a**: System MUST NOT subtract dry kilograms from a fresh harvest weight or the reverse, in any figure it shows the farmer.
- **FR-038**: System MUST allow the farmer to edit and delete harvest and sales records, with all derived figures updating accordingly.
- **FR-038a**: System MUST accept sales against a harvested cropping for as long as it remains open, including after a new cropping has been started on the same field.
- **FR-038b**: System MUST require the farmer to choose which cropping a sale belongs to whenever the chosen field has more than one open cropping, on the same terms as FR-031b.

#### Results and reports

- **FR-039**: System MUST show, for each cropping, its total expenses, total revenue, net profit or loss, total yield in tons, yield in tons per hectare, and cost per kilogram produced.
- **FR-040**: System MUST calculate net profit or loss as revenue minus expenses, and cost per kilogram produced as total expenses divided by total harvested kilograms on the fresh-weight basis, labelled as such.
- **FR-041**: System MUST show cost per kilogram produced as not applicable, rather than an error, when the harvested quantity is zero.
- **FR-042**: System MUST show results for a cropping that has not been harvested as expenses to date, clearly labelled as in progress, without presenting the absence of revenue as a loss.
- **FR-042a**: System MUST label the result of a harvested but open cropping as provisional, and MUST recalculate every figure in FR-039 — including net profit and cost per kilogram — as post-harvest expenses and further sales are recorded.
- **FR-042b**: System MUST treat a cropping's result as final only once it is closed, and MUST mark it as such.
- **FR-043**: System MUST allow the farmer to compare croppings against each other on the metrics in FR-039, with filters for field, crop, and season. Because every cropping's yield and cost per kilogram are on the same fresh-weight basis, these comparisons are like-for-like across seasons and fields.
- **FR-044**: System MUST present, on the home screen, the croppings currently in progress with their field, crop, status, and days since planting.
- **FR-045**: System MUST present, on the home screen, the fertilizer applications due next across all active croppings, in due-date order, with field, product, and quantity in bags.
- **FR-046**: System MUST present, on the home screen, croppings whose expected harvest date is approaching.
- **FR-046a**: System MUST present, on the home screen, harvested croppings that are not yet closed, showing their unsold remaining quantity, so outstanding sales and post-harvest costs are not forgotten once the field has been replanted.
- **FR-046b**: System MUST show both croppings distinctly when a field appears on the home screen with one cropping in the ground and one harvested but open.

#### Accounts and access

- **FR-058**: System MUST allow the farmer to create an account and sign in, and MUST use that identity to determine which records they may read and write.
- **FR-059**: System MUST allow a farmer to use the app as a guest without an account, with every feature in this specification available for their own records on that device.
- **FR-060**: System MUST store a guest's records on the device only, and MUST state plainly to a guest that those records are not protected against loss of the device and cannot be restored onto another one.
- **FR-061**: System MUST allow a guest to create an account at any time, and MUST move every record they created as a guest into that account without losing or altering anything.
- **FR-062**: System MUST keep the records of one account unreadable and unwritable by any other account and by any guest.
- **FR-063**: System MUST allow a signed-in farmer to sign out, and MUST leave none of their records readable on the device to a guest or to another account afterwards.
- **FR-064**: System MUST restore a signed-in farmer's complete history when they sign in on a new or reinstalled device, satisfying FR-052.
- **FR-065**: System MUST let a farmer who is already signed in keep using every feature offline; an existing session MUST NOT require a network connection to continue working.
- **FR-066**: System MUST allow a farmer who has lost access to their sign-in credentials to recover their account, so a forgotten credential does not destroy their history.
- **FR-067**: System MUST NOT require a guest to see or dismiss an account prompt more than once per session, so trialling the app is not obstructed.

#### General

- **FR-047**: System MUST express all monetary amounts in Philippine pesos (PHP).
- **FR-048**: System MUST serve one farmer managing their own fields. v1 has no team members, no roles or permissions, and no way to view or edit another farmer's records.
- **FR-049**: System MUST retain all field, cropping, schedule, expense, harvest, and sales records indefinitely until the farmer deletes them.
- **FR-050**: System MUST remain usable for viewing records and entering data while the device has no network connection.
- **FR-051**: System MUST hold a signed-in farmer's records in remote storage so that loss, theft, damage, or replacement of the device does not lose any history. Guest records are device-only (FR-060).
- **FR-052**: System MUST restore the farmer's complete history — fields, croppings, schedules, expenses, harvests, and sales — onto a new or reinstalled device without the farmer re-entering anything.
- **FR-053**: System MUST complete a save on the device the moment the farmer saves, without waiting for a network connection, and MUST never reject or discard an entry because the device is offline.
- **FR-053a**: System MUST send each saved record to remote storage in the background as soon as a connection is available, without the farmer having to trigger it.
- **FR-053b**: System MUST show the farmer which entries are still pending sync and when the last successful sync happened, so the farmer can tell what is protected against device loss and what is not yet.
- **FR-053c**: System MUST retry a failed sync automatically, and MUST surface a persistent sync failure to the farmer rather than failing silently.
- **FR-053d**: System MUST preserve pending entries across app restarts and device restarts until they have been stored remotely.
- **FR-053e**: System MUST apply pending changes to remote storage in the order the farmer made them, so a later correction never loses to the earlier value it replaced.
- **FR-053g**: System MUST recover from a remote-storage outage with no action by the farmer and no intervention by whoever runs the service: retries MUST continue indefinitely rather than giving up after a number of attempts, and a queued record MUST never be discarded because an attempt failed, so the backlog drains by itself once the service is reachable again.
- **FR-053f**: System MUST be able to restore remotely stored records to any point within the previous 35 days, and MUST additionally keep a monthly copy for 12 months, so damage caused on the server side — a faulty release, a defect, or an accidental deletion — does not destroy a farmer's history. This covers damage to the stored copy itself and is separate from restoring onto a new device (FR-052).
- **FR-054**: System MUST tie every stored record to the account that owns it, so ownership is established by identity rather than by which device created the record (see FR-058, FR-062).
- **FR-055**: System MUST present all farmer-facing text in English in v1.
- **FR-056**: System MUST keep all farmer-facing text — including expense categories, growth stage labels, status names, and built-in variety names — separable from behaviour, so a further language can be added in phase 2 without changing how any feature works.
- **FR-057**: System MUST NOT depend on the text of a label to decide behaviour; categories, statuses, and growth stages are identified independently of how they are displayed.

### Key Entities

- **Farmer Account**: The identity that owns a set of records. Sign-in credentials and a recovery route. A farmer may instead operate as a guest, in which case records are device-only and unowned until the guest signs up.
- **Field**: A parcel the farmer plants, owned by one account. Name, area in hectares, optional location and notes, archived flag. Has many croppings over time.
- **Cropping**: One planting season on one field. Crop (rice or corn), variety, planting method, growing season (wet or dry), planting date, expected harvest date and whether it was overridden, status, sale weight basis (wet or dry) and, when dry, the lot's dried weight. Reaches growing on the first completed fertilizer application or 10 days after planting, whichever is first. Belongs to one field; has one fertilizer schedule, many expenses, one harvest, and many sales.
- **Variety**: A named rice or corn variety with a typical maturity in days. Either built in or added by the farmer.
- **Fertilizer Template**: The default schedule for a crop and planting method combination. Editable by the farmer. Has many template steps.
- **Fertilizer Template Step**: Timing in days after planting, growth stage label, recommended product, recommended rate per hectare.
- **Scheduled Application**: A template step instantiated for one cropping. Carries the recommendation scaled to the field's area, a due date, a state (pending, done, skipped), and, when done, the actual date, product, quantity, and cost. Linked to at most one expense.
- **Expense**: A cost against a cropping. Date, category, amount in PHP, optional notes, and an optional link to the scheduled application that generated it.
- **Harvest**: The output of a cropping. Date, sacks and average wet kilograms per sack or a total in wet kilograms, derived total in tons. Always fresh weight.
- **Sale**: A disposal of harvested produce. Quantity in kilograms on the cropping's declared weight basis, price per kilogram, buyer, date.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A farmer can add a field and start a cropping on it in under 3 minutes on their first attempt, without written instructions.
- **SC-002**: Logging a single expense takes under 30 seconds from opening the app.
- **SC-003**: Once a harvest and at least one sale are recorded, the cropping's total expenses, revenue, net profit or loss, tons, tons per hectare, and cost per kilogram are all visible on one screen with no manual calculation by the farmer.
- **SC-004**: For any upcoming fertilizer application, the farmer can read off how many 50 kg bags to buy for that specific field without converting a per-hectare rate themselves.
- **SC-005**: At least 90% of scheduled fertilizer applications are marked done or skipped within 3 days of their due date, showing that reminders reach the farmer in time.
- **SC-006**: Recording a cost against a fertilizer application increases that cropping's expense total by exactly that amount, with the cost appearing once and only once in the category breakdown.
- **SC-007**: A farmer can compare the net profit of the same field across two seasons in under 1 minute.
- **SC-008**: A farmer who reads basic English and has never used the app completes a full cycle — field, cropping, expenses, harvest, sale, result — unaided on the first attempt.
- **SC-009**: Every figure the app reports for a completed cropping matches the farmer's own hand calculation from the same inputs, for 100% of test croppings.
- **SC-010**: All data entry and record viewing works with the device offline, with zero features unavailable other than any that depend on an external service.
- **SC-011**: A cost paid after harvest can be charged to the cropping that produced it even after the same field has been replanted, in 100% of cases, with no cost landing on the wrong cropping.
- **SC-012**: No cropping reports a final profit while costs or sales are still outstanding — every harvested, unclosed cropping is visibly marked provisional and reachable from the home screen.
- **SC-013**: A farmer who replaces or reinstalls on a new device recovers 100% of their previous records, with no re-entry and no figure differing from before.
- **SC-014**: Every save attempted with no connection succeeds on the device, and 100% of those entries reach remote storage once a connection returns, with no loss and no duplicates. The same holds when the remote service itself is unavailable rather than the connection: after an outage of any length, 100% of the queued entries reach remote storage once it returns, with no farmer action and no operator intervention.
- **SC-015**: The farmer can tell at a glance whether their records are fully backed up, without opening a settings screen.
- **SC-016**: A guest who creates an account keeps 100% of the records they entered during the trial, with no re-entry and no figure changing.
- **SC-017**: A farmer can start using the app and record their first field without creating an account.
- **SC-018**: A signed-in farmer who loses their credentials recovers their full history, with no season of records lost to a forgotten password.
- **SC-019**: Records damaged or deleted on the server side can be restored to their state at any chosen moment in the previous 35 days, and to the state at any month end within the previous 12 months, with 100% of a test account's croppings, expenses, harvests, and sales present and unchanged after the restore.

## Out of Scope (v1)

The following are explicitly excluded from this version and must not be designed into it:

- Team sharing of any kind — multiple people on one farm, roles and permissions, or sharing fields and croppings with family members, workers, or cooperatives. *(Accounts and sign-in are in scope as of 2026-11-01: they establish who owns a record, not who it is shared with.)*
- Weather data, forecasts, or rainfall tracking.
- Market price feeds or price suggestions.
- Pest and disease identification, diagnosis, or treatment recommendations.
- Accounting exports, tax reports, or bookkeeping integrations.
- Crops other than rice and corn.
- The agronomy CRM itself — the tool through which PhilRice, the Bureau of Plant Industry, or other agronomists author and publish variety and fertilizer data. v1 *consumes* published guidance (FR-026a to FR-026e); it does not produce it. **Planned as feature 002**, which serves a different class of user and needs its own specification.
- Loan, credit, or subsidy tracking.
- Valuing unsold harvest as revenue or as inventory worth a peso amount.
- Languages other than English, and any in-app language switch — planned for phase 2. v1 must not make that addition harder (FR-056, FR-057), but ships English only.
- Mixed wet and dry disposal of a single cropping's produce.
- Operator-side alerting and on-call monitoring of sync health — dashboards, alarms, or a pager that tells whoever runs the service that syncs are failing across farmers. Recovery does not depend on anyone noticing: the records stay queued on each device and resend themselves (FR-053g), and the farmer is told directly when their own backup is failing (FR-053c). *(Decided 2026-11-01. The residual exposure is recorded under Assumptions.)*

## Assumptions

- **One farmer, with an account, remote durable copy** *(clarified 2026-11-01)*: all data belongs to one farmer. The device holds the working copy and a remote database holds the durable copy for signed-in farmers, so the history survives device loss and can be restored onto a replacement. Because there is one farmer using one device at a time, sync is one-way in practice and no merge-conflict resolution is assumed. Accounts exist to establish ownership and protect records, not to enable sharing — team access remains out of scope.
- **Guest mode is a trial, not a tier** *(clarified 2026-11-01)*: a guest gets every feature but no remote copy, so no device-loss protection and no restore. The app says so plainly rather than letting a farmer discover it after losing a phone, and signing up migrates everything the guest entered.
- **Sign-in method is a plan decision**: the spec requires an account and a recovery route (FR-058, FR-066) without naming a method. Many Philippine farmers have a phone number and no email address, so phone-based or social sign-in is likely to fit better than email and password — to be settled in `plan.md`.
- **Offline first** *(clarified 2026-11-01)*: the device is the front-line store and every save succeeds locally without a connection; remote storage is the durable copy the app syncs to in the background. Farmers enter data in the field, where connectivity is worst, so no feature may depend on being online at the moment of entry.
- **Built-in reference data ships with the app and can be updated** *(clarified 2026-11-01)*: a list of common Philippine rice and corn varieties with typical maturity in days, and default fertilizer templates per crop and planting method, ship with the app, sourced from PhilRice and Bureau of Plant Industry published guidance with attribution recorded per record. The farmer can add to or edit both, and their edits always outrank later published updates (FR-026c). Updates arrive without an app update (FR-026b).
- **Corn planting method**: The description enumerates planting methods only for rice. Corn is assumed to offer direct-seeded as its planting method.
- **Fertilizer bag size**: Bags are assumed to be 50 kg, as stated in the description. Bag counts are displayed to one decimal place so partial bags are visible (for example 5.5 bags), with the kilogram figure shown alongside.
- **One harvest per cropping**: Each cropping has a single harvest record, editable if the quantity turns out different. Multiple partial harvests and ratoon crops are not modelled in v1.
- **Unsold harvest is not revenue**: As stated in the description, revenue is the sum of actual sales. Produce kept for home use or stock is reported as a remaining quantity only, and is deliberately not assigned a peso value in profit.
- **Cost per kilogram produced** is total expenses divided by total kilograms harvested on the fresh-weight basis, not kilograms sold, so it measures production efficiency rather than sales performance.
- **Fresh weight is the yield basis** *(clarified 2026-11-01)*: harvest is always recorded wet, so yield, tons per hectare, and cost per kilogram are on one consistent basis and comparable across every cropping. The app never converts between wet and dry weight and does not model moisture content.
- **One weight basis per cropping** *(clarified 2026-11-01)*: a farmer sells a lot either wet or dry, not split between the two, so the basis is declared once per cropping rather than per sale. Mixed wet and dry disposal within a single cropping is not supported in v1; a farmer who genuinely splits a lot records it on the basis most of it was sold on.
- **English in v1, more languages in phase 2** *(clarified 2026-11-01)*: the app ships in English. Fertilizer products and variety names are already used in their English form in practice, so they stay as they are in any language. Farmer-facing text is kept separable from behaviour so a local-language option can be added in phase 2 without reworking screens.
- **Season has two meanings, kept distinct**: a cropping's *growing season* is wet or dry (when it was planted), and a cropping's *weight basis* is wet or dry (how the produce was sold). They are independent — a dry-season cropping can be sold wet — and the app labels each so they are never confused.
- **Template edits are forward-looking**: A cropping's schedule is a snapshot taken when the cropping starts. Editing a template changes future croppings only; an active cropping's schedule is edited directly on that cropping.
- **Field occupancy ends at harvest, but the books stay open** *(confirmed with the farmer)*: a field is free to replant once its cropping is marked harvested, so recording sales never blocks the next planting. Freeing the field is **not** the same as finishing the cropping — a harvested cropping keeps accepting post-harvest expenses (threshing, drying, hauling, storage) and sales until the farmer closes it. At most one cropping per field is in the ground at a time, but a field may have one growing cropping and one harvested-but-open cropping simultaneously, which is why expenses and sales are attributed to a cropping rather than to a field.
- **Post-harvest costs use the existing categories**: threshing and drying fall under harvesting/threshing, transport under hauling, and anything else such as storage under other. No new expense category is introduced beyond the ten listed.
- **Reminders are device-scheduled** *(resolved default, not stated in the description)*: reminders fire 2 days before an application is due and again on the due date, reach the farmer whether or not the app is open, work offline, and can be switched off. No server, SMS, or email delivery is assumed.
- **Season is declared, not derived**: The farmer states whether a cropping is wet or dry season; the app does not infer it from the planting date.
- **Expected harvest date is informational**: Reaching it does not automatically change a cropping's status; the farmer records the harvest when it happens.
- **Growing is a real stored status, reached automatically** *(clarified 2026-11-01)*: the first completed fertilizer application or 10 days after planting, whichever comes first. The 10-day fallback exists so a cropping never sits in planted all season just because the farmer skipped the basal application. Harvested and closed remain farmer-driven.
- **Dates are calendar dates** in the farmer's local time; no time-of-day precision is needed anywhere in the feature.
- **Currency is PHP only**: No multi-currency support, exchange rates, or inflation adjustment.
- **A sync outage heals itself; nobody is paged** *(clarified 2026-11-01)*: a failed sync costs nothing but time, because the record is already saved on the device and the app keeps retrying until it lands (FR-053g). So v1 runs with no operator alerting: whoever runs the service learns of an outage from farmers, not from a pager. The exposure this accepts is narrow and worth naming — during an outage the queued records exist only on the phone, so a farmer who loses or breaks the handset in that window loses what had not yet synced. The farmer is warned their records are not backed up after repeated failures (FR-053c), which is what makes that window visible to the person who can act on it.
- **Growth stage labels are crop-specific**: Rice uses stages such as basal, early tillering, and panicle initiation; corn uses its own equivalents. These come from the built-in templates.
- **Recommendations are guidance, not agronomy**: The app does not perform soil nutrient calculations. It scales a stored rate by area and says so.
