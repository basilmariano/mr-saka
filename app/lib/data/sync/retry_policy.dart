/// What to do when a sync attempt fails.
///
/// contracts/sync-protocol.md, Retry and backoff. The rule that matters most:
/// a 400 `validation_failed` HALTS AND SURFACES rather than dropping the entry.
/// A client bug must never silently discard the farmer's data.
enum SyncOutcome {
  /// Everything in the batch landed.
  applied,

  /// No connectivity. Not counted as an attempt — the worker simply waits.
  offline,

  /// Transient: 5xx or a timeout. Back off and retry indefinitely.
  retryable,

  /// The token expired. Refresh once, then prompt re-sign-in.
  unauthorized,

  /// The server refused the record. Halt and tell the farmer; never drop it.
  rejected,
}

class RetryPolicy {
  const RetryPolicy({
    this.initial = const Duration(seconds: 30),
    this.max = const Duration(hours: 6),
    this.surfaceAfterAttempts = 5,
  });

  final Duration initial;
  final Duration max;

  /// FR-053c: after this many failures the farmer is told plainly that records are
  /// not being backed up, rather than the app looking healthy while nothing
  /// reaches remote storage.
  final int surfaceAfterAttempts;

  /// Exponential backoff, capped.
  Duration delayForAttempt(int attempt) {
    if (attempt <= 0) return initial;
    var delay = initial;
    for (var i = 0; i < attempt && delay < max; i++) {
      delay *= 2;
    }
    return delay > max ? max : delay;
  }

  bool shouldSurface(int attempts) => attempts >= surfaceAfterAttempts;

  /// Whether the worker keeps draining after this outcome.
  ///
  /// Anything other than [SyncOutcome.applied] halts the drain. FR-053e: skipping
  /// ahead past a failure would let a later correction reach remote storage before
  /// the value it replaces.
  bool shouldContinue(SyncOutcome outcome) => outcome == SyncOutcome.applied;
}
