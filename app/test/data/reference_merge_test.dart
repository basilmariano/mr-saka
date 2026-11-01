import 'package:saka/data/reference/bundle_merge.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:test/test.dart';

/// quickstart.md Scenario 11 and FR-026c.
///
/// "A farmer who followed their agriculturist's advice and edited a template must
/// never have that edit silently discarded by a routine data refresh."
class Row {
  const Row(this.key, this.source, this.rate);
  final String key;
  final ReferenceSource source;
  final int rate;
}

void main() {
  MergePlan<Row> planFor(List<Row> existing, List<Row> incoming) => BundleMerge.plan(
        existing: existing,
        sourceOf: (r) => r.source,
        keyOf: (r) => r.key,
        incoming: incoming,
      );

  test('a farmer-edited row survives a bundle update', () {
    // Scenario 11: farmer changed 100 kg/ha to 120; the bundle says 90.
    final plan = planFor(
      [const Row('rice-transplanted-basal', ReferenceSource.farmer, 120)],
      [const Row('rice-transplanted-basal', ReferenceSource.published, 90)],
    );

    expect(plan.toRemove, isEmpty, reason: 'farmer rows are never removed');
    expect(plan.toApply, isEmpty, reason: 'the bundle must not overwrite it');
    expect(plan.skippedBecauseFarmerEdited, hasLength(1));
  });

  test('an unedited seed row is replaced by the bundle', () {
    final plan = planFor(
      [const Row('rice-transplanted-basal', ReferenceSource.seed, 100)],
      [const Row('rice-transplanted-basal', ReferenceSource.published, 90)],
    );

    expect(plan.toRemove, hasLength(1));
    expect(plan.toApply.single.rate, 90);
    expect(plan.skippedBecauseFarmerEdited, isEmpty);
  });

  test('a previously published row is replaced by a newer one', () {
    final plan = planFor(
      [const Row('k', ReferenceSource.published, 90)],
      [const Row('k', ReferenceSource.published, 95)],
    );
    expect(plan.toApply.single.rate, 95);
  });

  test('a mixed set protects only the farmer rows', () {
    final plan = planFor(
      [
        const Row('a', ReferenceSource.seed, 100),
        const Row('b', ReferenceSource.farmer, 120),
        const Row('c', ReferenceSource.published, 80),
      ],
      [
        const Row('a', ReferenceSource.published, 90),
        const Row('b', ReferenceSource.published, 90),
        const Row('c', ReferenceSource.published, 90),
      ],
    );

    expect(plan.toApply.map((r) => r.key).toList(), ['a', 'c']);
    expect(plan.skippedBecauseFarmerEdited.single.key, 'b');
    expect(plan.toRemove.map((r) => r.key).toList(), ['a', 'c']);
  });

  test('a brand new row from the bundle is applied', () {
    final plan = planFor(
      const [],
      [const Row('new', ReferenceSource.published, 70)],
    );
    expect(plan.toApply, hasLength(1));
  });

  test('mayReplace encodes the rule directly', () {
    expect(BundleMerge.mayReplace(ReferenceSource.seed), isTrue);
    expect(BundleMerge.mayReplace(ReferenceSource.published), isTrue);
    expect(BundleMerge.mayReplace(ReferenceSource.farmer), isFalse);
  });
}
