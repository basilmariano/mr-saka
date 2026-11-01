import '../../domain/model/calendar_date.dart';
import '../../domain/model/enums.dart';
import '../../domain/rules/validation.dart';
import '../../domain/rules/weight_basis.dart';
import '../../l10n/app_localizations.dart';

/// Enum-to-text lookups.
///
/// FR-057: behaviour never branches on display text. Every switch here goes
/// constant -> string and never the reverse, so adding the phase-2 local language
/// means translating ARB entries and changing nothing else.
extension Labels on AppLocalizations {
  String crop(Crop value) => switch (value) {
        Crop.rice => croppingCropRice,
        Crop.corn => croppingCropCorn,
      };

  String plantingMethod(PlantingMethod value) => switch (value) {
        PlantingMethod.transplanted => croppingMethodTransplanted,
        PlantingMethod.directSeeded => croppingMethodDirectSeeded,
      };

  String growingSeason(GrowingSeason value) => switch (value) {
        GrowingSeason.wet => croppingSeasonWet,
        GrowingSeason.dry => croppingSeasonDry,
      };

  String weightBasis(WeightBasis value) => switch (value) {
        WeightBasis.wet => basisWet,
        WeightBasis.dry => basisDry,
      };

  String croppingStatus(CroppingStatus value) => switch (value) {
        CroppingStatus.planted => statusPlanted,
        CroppingStatus.growing => statusGrowing,
        CroppingStatus.harvested => statusHarvested,
        CroppingStatus.closed => statusClosed,
      };

  String categoryLabel(ExpenseCategory value) => switch (value) {
        ExpenseCategory.landPreparation => categoryLandPreparation,
        ExpenseCategory.seeds => categorySeeds,
        ExpenseCategory.fertilizer => categoryFertilizer,
        ExpenseCategory.pesticideHerbicide => categoryPesticideHerbicide,
        ExpenseCategory.labor => categoryLabor,
        ExpenseCategory.irrigation => categoryIrrigation,
        ExpenseCategory.equipmentRental => categoryEquipmentRental,
        ExpenseCategory.harvestingThreshing => categoryHarvestingThreshing,
        ExpenseCategory.hauling => categoryHauling,
        ExpenseCategory.other => categoryOther,
      };

  String validationFailure(ValidationFailure value) => switch (value) {
        ValidationFailure.fieldNameBlank => errorFieldNameBlank,
        ValidationFailure.fieldAreaNotPositive => errorFieldAreaNotPositive,
        ValidationFailure.expenseAmountNotPositive => errorAmountNotPositive,
        ValidationFailure.pricePerKgNotPositive => errorPriceNotPositive,
        ValidationFailure.buyerBlank => errorBuyerBlank,
        ValidationFailure.maturityDaysNotPositive => errorAmountNotPositive,
        ValidationFailure.ratePerHectareNotPositive => errorAmountNotPositive,
      };

  String saleRejection(SaleRejection value, {String? remaining}) =>
      switch (value) {
        SaleRejection.noHarvest => errorSaleNoHarvest,
        SaleRejection.driedWeightMissing => errorSaleDriedWeightMissing,
        SaleRejection.exceedsRemaining =>
          errorSaleExceeds(remaining ?? '0'),
        SaleRejection.nonPositiveQuantity => errorSaleNonPositive,
      };

  /// FR-031c: a cropping must be identifiable by crop, season, and planting date —
  /// never by field alone, because a field can hold two open croppings.
  String croppingDescriptor({
    required Crop cropValue,
    required GrowingSeason season,
    required CalendarDate plantingDate,
  }) =>
      croppingLabel(
        crop(cropValue),
        growingSeason(season),
        formatDate(plantingDate),
      );

  String formatDate(CalendarDate date) => date.toIso();
}
