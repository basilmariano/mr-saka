/// Domain entities. One-to-one with data-model.md.
///
/// These are plain immutable Dart objects with no persistence concern. The Drift
/// rows in data/local/tables.dart mirror them; data/local/mappers.dart converts.
library;

import 'calendar_date.dart';
import 'centavos.dart';
import 'enums.dart';
import 'grams.dart';
import 'square_metres.dart';

class FieldEntity {
  const FieldEntity({
    required this.id,
    required this.name,
    required this.area,
    this.location,
    this.notes,
    this.archived = false,
  });

  final String id;
  final String name;
  final SquareMetres area;
  final String? location;
  final String? notes;

  /// FR-004: a field with croppings is archived, never deleted.
  final bool archived;

  FieldEntity copyWith({
    String? name,
    SquareMetres? area,
    String? location,
    String? notes,
    bool? archived,
  }) =>
      FieldEntity(
        id: id,
        name: name ?? this.name,
        area: area ?? this.area,
        location: location ?? this.location,
        notes: notes ?? this.notes,
        archived: archived ?? this.archived,
      );
}

class CroppingEntity {
  const CroppingEntity({
    required this.id,
    required this.fieldId,
    required this.crop,
    required this.varietyId,
    required this.plantingMethod,
    required this.growingSeason,
    required this.plantingDate,
    required this.status,
    this.expectedHarvestDate,
    this.expectedHarvestOverridden = false,
    this.saleWeightBasis,
    this.driedWeight,
  });

  final String id;
  final String fieldId;
  final Crop crop;
  final String varietyId;
  final PlantingMethod plantingMethod;

  /// When it was planted. NOT [saleWeightBasis], which is also wet/dry.
  final GrowingSeason growingSeason;

  final CalendarDate plantingDate;
  final CalendarDate? expectedHarvestDate;
  final bool expectedHarvestOverridden;
  final CroppingStatus status;

  /// How the produce was sold. Independent of [growingSeason] — a dry-season
  /// cropping can be sold wet (spec Assumptions).
  final WeightBasis? saleWeightBasis;

  /// FR-034b: required once sold dry.
  final Grams? driedWeight;

  CroppingEntity copyWith({
    CalendarDate? plantingDate,
    CalendarDate? expectedHarvestDate,
    bool? expectedHarvestOverridden,
    CroppingStatus? status,
    WeightBasis? saleWeightBasis,
    Grams? driedWeight,
  }) =>
      CroppingEntity(
        id: id,
        fieldId: fieldId,
        crop: crop,
        varietyId: varietyId,
        plantingMethod: plantingMethod,
        growingSeason: growingSeason,
        plantingDate: plantingDate ?? this.plantingDate,
        expectedHarvestDate: expectedHarvestDate ?? this.expectedHarvestDate,
        expectedHarvestOverridden:
            expectedHarvestOverridden ?? this.expectedHarvestOverridden,
        status: status ?? this.status,
        saleWeightBasis: saleWeightBasis ?? this.saleWeightBasis,
        driedWeight: driedWeight ?? this.driedWeight,
      );
}

class ExpenseEntity {
  const ExpenseEntity({
    required this.id,
    required this.croppingId,
    required this.date,
    required this.category,
    required this.amount,
    this.notes,
    this.linkedApplicationId,
  });

  final String id;

  /// FR-031b: an expense belongs to a CROPPING, never a field — a field can hold two
  /// open croppings at once.
  final String croppingId;

  /// May precede planting (land prep) or follow harvest (hauling). Both normal.
  final CalendarDate date;
  final ExpenseCategory category;
  final Centavos amount;
  final String? notes;

  /// FR-021: set when auto-created from a completed fertilizer application.
  final String? linkedApplicationId;
}

class HarvestEntity {
  const HarvestEntity({
    required this.id,
    required this.croppingId,
    required this.date,
    required this.totalWet,
    this.sacks,
    this.avgWetPerSack,
  });

  final String id;
  final String croppingId;
  final CalendarDate date;

  /// Always FRESH weight (FR-032a). Zero is valid — a total crop failure.
  final Grams totalWet;

  /// The farmer's own input, kept so it can be shown back to them.
  final int? sacks;
  final Grams? avgWetPerSack;
}

class SaleEntity {
  const SaleEntity({
    required this.id,
    required this.croppingId,
    required this.quantity,
    required this.pricePerKg,
    required this.buyer,
    required this.date,
  });

  final String id;
  final String croppingId;

  /// On the CROPPING's declared weight basis, not its own.
  final Grams quantity;
  final Centavos pricePerKg;
  final String buyer;
  final CalendarDate date;
}

/// A template step instantiated for one cropping. FR-014 to FR-023.
///
/// FR-025: this is a SNAPSHOT taken when the cropping starts. Editing the template
/// it came from must never touch this row — a farmer's running schedule does not
/// shift under them because guidance was updated mid-season.
class ScheduledApplicationEntity {
  const ScheduledApplicationEntity({
    required this.id,
    required this.croppingId,
    required this.daysAfterPlanting,
    required this.growthStage,
    required this.recommendedProduct,
    required this.ratePerHectare,
    required this.sortOrder,
    required this.state,
    this.actualDate,
    this.actualProduct,
    this.actualQuantity,
    this.cost,
    this.skipReason,
    this.linkedExpenseId,
  });

  final String id;
  final String croppingId;
  final int daysAfterPlanting;
  final String growthStage;
  final String recommendedProduct;
  final Grams ratePerHectare;
  final int sortOrder;
  final ApplicationState state;

  // Set when done (FR-020).
  final CalendarDate? actualDate;
  final String? actualProduct;
  final Grams? actualQuantity;
  final Centavos? cost;

  /// FR-022.
  final String? skipReason;

  /// FR-021: at most one expense, kept in step so the cost is never counted twice
  /// and never orphaned.
  final String? linkedExpenseId;

  bool get isPending => state == ApplicationState.pending;

  /// FR-017: due date is the cropping's planting date plus days after planting.
  CalendarDate dueDate(CalendarDate plantingDate) =>
      plantingDate.addDays(daysAfterPlanting);

  /// FR-016: the recommendation scaled to this field.
  Grams recommendedQuantity(SquareMetres area) => Grams(
        ratePerHectare.value * area.value ~/ SquareMetres.sqmPerHectare,
      );

  ScheduledApplicationEntity copyWith({
    ApplicationState? state,
    CalendarDate? actualDate,
    String? actualProduct,
    Grams? actualQuantity,
    Centavos? cost,
    String? skipReason,
    String? linkedExpenseId,
    bool clearLink = false,
  }) =>
      ScheduledApplicationEntity(
        id: id,
        croppingId: croppingId,
        daysAfterPlanting: daysAfterPlanting,
        growthStage: growthStage,
        recommendedProduct: recommendedProduct,
        ratePerHectare: ratePerHectare,
        sortOrder: sortOrder,
        state: state ?? this.state,
        actualDate: actualDate ?? this.actualDate,
        actualProduct: actualProduct ?? this.actualProduct,
        actualQuantity: actualQuantity ?? this.actualQuantity,
        cost: cost ?? this.cost,
        skipReason: skipReason ?? this.skipReason,
        linkedExpenseId: clearLink ? null : (linkedExpenseId ?? this.linkedExpenseId),
      );
}
