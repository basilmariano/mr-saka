# Contract: Offline-First Sync Protocol

**Feature**: `001-crop-tracking` | **Companion to**: [api.openapi.yaml](./api.openapi.yaml) | **Research**: [research.md](./research.md) R3

This is the contract between the Android client's local store and the sync API. It exists because the ordering and idempotency rules below are not expressible in OpenAPI, and getting any of them wrong corrupts the farmer's totals silently — the worst failure mode this feature has.

## The invariants

### I1 — A save never waits for the network (FR-053)

A domain write and its outbox append happen inside **one Drift transaction**. Both commit or neither does.

```
saveExpense(e):
  transaction {
    expenses.upsert(e)
    outbox.append(seq = next(), op = UPSERT, type = expense, id = e.id, payload = e)
  }
  // returns here — the farmer sees "saved". No network was involved.
  syncWorker.enqueue()   // best-effort nudge; the save already succeeded
```

A save is **never** rejected, deferred, or queued-but-not-applied because the device is offline. The UI reflects the local state immediately.

### I2 — Strict ordering (FR-053e)

The outbox drains in ascending `seq`. On any failure the worker **halts** — it does not skip ahead.

This matters concretely: a farmer records an expense of ₱3,500, then corrects it to ₱3,000. Both are outbox entries. If they were applied out of order, DynamoDB would end up holding ₱3,500, and the device would show ₱3,000. The farmer's durable copy would be wrong and nothing would report an error.

### I3 — Idempotent retries

Every record's primary key is a **client-generated UUIDv4**, assigned before the first save. An `upsert` is therefore a `PutItem` on a known key.

This is the defence against the ambiguous timeout: the request reached DynamoDB, the write succeeded, the response was lost. The device retries. Without a stable client-side id the retry creates a second expense row and the farmer's season total is quietly overstated. With one, the retry overwrites the identical record and nothing changes.

### I4 — Deletes are soft

A delete sets `deleted = true` and keeps the row. A hard delete would be resurrected by the next snapshot, because the snapshot has no way to know the record ever existed.

### I5 — Ownership is never client-supplied (FR-062)

The account partition key is built from the verified JWT `sub` claim. A request body containing an account id is **rejected**, not honoured. This is the one rule in the whole feature whose violation exposes another person's data rather than producing a wrong number.

## Flows

### Normal drain

```
while outbox not empty:
    batch = outbox.take(100, orderBy = seq ASC)
    response = POST /v1/mutations { mutations: batch }

    if response.failedIndex == null:
        outbox.delete(batch)                    # all applied
    else:
        outbox.delete(batch[0 ..< failedIndex]) # partial: keep the rest
        recordError(batch[failedIndex], response.error)
        halt                                    # I2 — never skip ahead
```

### Retry and backoff (FR-053c, FR-053g)

| Failure | Behaviour |
|---|---|
| No connectivity | Not an attempt — the worker waits rather than counting a failure |
| 5xx / timeout | Exponential backoff from 30 s to 6 h; retry indefinitely |
| 401 | Refresh the token once; if it still fails, prompt re-sign-in and halt |
| 400 `validation_failed` | **Halt and surface.** Do not drop the entry — a client bug must not silently discard the farmer's data |
| Same entry fails 5 times | Surface persistently in the UI: "records are not being backed up" (FR-053c) |

A sync that keeps failing must never leave the app looking healthy while nothing reaches remote storage.

**There is no maximum attempt count, and adding one would be a defect.** FR-053g makes indefinite retry a requirement rather than a convention, because v1 runs with no operator alerting (research.md R12): the device retrying is the entire recovery mechanism for a service outage. The attempt counter exists only to decide when to tell the farmer.

### Restore on a new device (FR-052, FR-064)

```
signIn() → GET /v1/snapshot (paginate on cursor)
         → write all records into Drift in one transaction per page
         → set lastSyncedAt = serverTime
         → derive PLANTED→GROWING for every cropping (FR-011a, FR-011b)
         → reschedule all pending alarms (R6)
```

The last two steps are easy to forget and both are load-bearing: a restored cropping whose status was stale would display wrongly, and a restored device with no alarms registered would silently stop reminding the farmer.

### Guest sign-up migration (FR-061)

```
transaction {
    all local rows: accountId = newAccountId
    outbox.appendAll(every row, op = UPSERT)
}
```

No ids change, because they were client-generated from the start (I3). The farmer loses nothing and re-enters nothing — SC-016.

## Visible sync state (FR-053b)

The home screen surfaces, without entering a settings screen (SC-015):

| State | Shown when |
|---|---|
| Up to date | outbox empty |
| *n* pending | outbox non-empty, no persistent error |
| Not backed up | an entry has failed repeatedly |
| Guest — on this phone only | `accountId == null` (FR-060) |

The guest state is deliberately phrased as a standing fact rather than a one-time dialog. A guest's records are genuinely unprotected, and they should know that while they are deciding, not after losing the phone.

## What this protocol does NOT do

- **No conflict resolution.** One farmer, one device at a time (FR-048). Last write wins, which is correct here. If multi-device editing ever enters scope, this contract needs revisiting — not patching.
- **No server-side calculation.** The device computes every figure offline. The server validates shape and invariants and stores what it is given.
- **No partial-record merging.** Mutations carry whole records, not field-level patches.
