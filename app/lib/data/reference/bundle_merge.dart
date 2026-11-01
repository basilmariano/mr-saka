import '../../domain/model/enums.dart';

/// Applying a published bundle without discarding the farmer's own work.
///
/// research.md R9, FR-026c. This is the rule that stops a routine data refresh from
/// silently throwing away the advice a farmer's local agriculturist gave them — the
/// failure most likely to destroy trust in the recommendations.
abstract final class BundleMerge {
  /// Whether an existing row may be replaced by an incoming published one.
  ///
  /// `seed` and `published` rows are replaceable. `farmer` rows never are.
  static bool mayReplace(ReferenceSource existing) =>
      existing != ReferenceSource.farmer;

  /// Partitions existing rows into those a bundle may replace and those it must not.
  ///
  /// FR-026d requires the whole update be applied "completely or not at all", so the
  /// caller performs the replacement inside one transaction.
  static MergePlan<T> plan<T>({
    required Iterable<T> existing,
    required ReferenceSource Function(T) sourceOf,
    required String Function(T) keyOf,
    required Iterable<T> incoming,
  }) {
    final protectedKeys = <String>{
      for (final row in existing)
        if (!mayReplace(sourceOf(row))) keyOf(row),
    };
    final replaceable = <T>[
      for (final row in existing) if (mayReplace(sourceOf(row))) row,
    ];
    final toApply = <T>[
      for (final row in incoming) if (!protectedKeys.contains(keyOf(row))) row,
    ];
    final skipped = <T>[
      for (final row in incoming) if (protectedKeys.contains(keyOf(row))) row,
    ];
    return MergePlan<T>(
      toRemove: replaceable,
      toApply: toApply,
      skippedBecauseFarmerEdited: skipped,
    );
  }
}

class MergePlan<T> {
  const MergePlan({
    required this.toRemove,
    required this.toApply,
    required this.skippedBecauseFarmerEdited,
  });

  /// Existing `seed`/`published` rows the bundle supersedes.
  final List<T> toRemove;

  /// Incoming rows to write.
  final List<T> toApply;

  /// Incoming rows deliberately NOT applied, because the farmer edited that record.
  final List<T> skippedBecauseFarmerEdited;
}
