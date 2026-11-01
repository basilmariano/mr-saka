/// Conversion between Drift rows and domain entities.
///
/// The persisted enums (tables.dart) are deliberately separate from the domain enums
/// (domain/model/enums.dart), so a domain rename can never silently change what is
/// already written in a farmer's database. This file is the only place the two meet.
library;

import '../../domain/model/calendar_date.dart';
import '../../domain/model/centavos.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/grams.dart';
import '../../domain/model/square_metres.dart';
import 'database.dart';
import 'tables.dart';

// ---------------------------------------------------------------- enums

CropDb cropToDb(Crop v) => switch (v) {
      Crop.rice => CropDb.rice,
      Crop.corn => CropDb.corn,
    };
Crop cropFromDb(CropDb v) => switch (v) {
      CropDb.rice => Crop.rice,
      CropDb.corn => Crop.corn,
    };

PlantingMethodDb methodToDb(PlantingMethod v) => switch (v) {
      PlantingMethod.transplanted => PlantingMethodDb.transplanted,
      PlantingMethod.directSeeded => PlantingMethodDb.directSeeded,
    };
PlantingMethod methodFromDb(PlantingMethodDb v) => switch (v) {
      PlantingMethodDb.transplanted => PlantingMethod.transplanted,
      PlantingMethodDb.directSeeded => PlantingMethod.directSeeded,
    };

SeasonDb seasonToDb(GrowingSeason v) => switch (v) {
      GrowingSeason.wet => SeasonDb.wet,
      GrowingSeason.dry => SeasonDb.dry,
    };
GrowingSeason seasonFromDb(SeasonDb v) => switch (v) {
      SeasonDb.wet => GrowingSeason.wet,
      SeasonDb.dry => GrowingSeason.dry,
    };

BasisDb basisToDb(WeightBasis v) => switch (v) {
      WeightBasis.wet => BasisDb.wet,
      WeightBasis.dry => BasisDb.dry,
    };
WeightBasis basisFromDb(BasisDb v) => switch (v) {
      BasisDb.wet => WeightBasis.wet,
      BasisDb.dry => WeightBasis.dry,
    };

StatusDb statusToDb(CroppingStatus v) => switch (v) {
      CroppingStatus.planted => StatusDb.planted,
      CroppingStatus.growing => StatusDb.growing,
      CroppingStatus.harvested => StatusDb.harvested,
      CroppingStatus.closed => StatusDb.closed,
    };
CroppingStatus statusFromDb(StatusDb v) => switch (v) {
      StatusDb.planted => CroppingStatus.planted,
      StatusDb.growing => CroppingStatus.growing,
      StatusDb.harvested => CroppingStatus.harvested,
      StatusDb.closed => CroppingStatus.closed,
    };

ApplicationState appStateFromDb(AppStateDb v) => switch (v) {
      AppStateDb.pending => ApplicationState.pending,
      AppStateDb.done => ApplicationState.done,
      AppStateDb.skipped => ApplicationState.skipped,
    };
AppStateDb appStateToDb(ApplicationState v) => switch (v) {
      ApplicationState.pending => AppStateDb.pending,
      ApplicationState.done => AppStateDb.done,
      ApplicationState.skipped => AppStateDb.skipped,
    };

CategoryDb categoryToDb(ExpenseCategory v) => switch (v) {
      ExpenseCategory.landPreparation => CategoryDb.landPreparation,
      ExpenseCategory.seeds => CategoryDb.seeds,
      ExpenseCategory.fertilizer => CategoryDb.fertilizer,
      ExpenseCategory.pesticideHerbicide => CategoryDb.pesticideHerbicide,
      ExpenseCategory.labor => CategoryDb.labor,
      ExpenseCategory.irrigation => CategoryDb.irrigation,
      ExpenseCategory.equipmentRental => CategoryDb.equipmentRental,
      ExpenseCategory.harvestingThreshing => CategoryDb.harvestingThreshing,
      ExpenseCategory.hauling => CategoryDb.hauling,
      ExpenseCategory.other => CategoryDb.other,
    };
ExpenseCategory categoryFromDb(CategoryDb v) => switch (v) {
      CategoryDb.landPreparation => ExpenseCategory.landPreparation,
      CategoryDb.seeds => ExpenseCategory.seeds,
      CategoryDb.fertilizer => ExpenseCategory.fertilizer,
      CategoryDb.pesticideHerbicide => ExpenseCategory.pesticideHerbicide,
      CategoryDb.labor => ExpenseCategory.labor,
      CategoryDb.irrigation => ExpenseCategory.irrigation,
      CategoryDb.equipmentRental => ExpenseCategory.equipmentRental,
      CategoryDb.harvestingThreshing => ExpenseCategory.harvestingThreshing,
      CategoryDb.hauling => ExpenseCategory.hauling,
      CategoryDb.other => ExpenseCategory.other,
    };

// ---------------------------------------------------------------- rows

FieldEntity fieldFromRow(Field r) => FieldEntity(
      id: r.id,
      name: r.name,
      area: SquareMetres(r.areaSqm),
      location: r.location,
      notes: r.notes,
      archived: r.archived,
    );

CroppingEntity croppingFromRow(Cropping r) => CroppingEntity(
      id: r.id,
      fieldId: r.fieldId,
      crop: cropFromDb(r.crop),
      varietyId: r.varietyId,
      plantingMethod: methodFromDb(r.plantingMethod),
      growingSeason: seasonFromDb(r.growingSeason),
      plantingDate: CalendarDate.parseIso(r.plantingDate),
      expectedHarvestDate: r.expectedHarvestDate == null
          ? null
          : CalendarDate.parseIso(r.expectedHarvestDate!),
      expectedHarvestOverridden: r.expectedHarvestOverridden,
      status: statusFromDb(r.status),
      saleWeightBasis:
          r.saleWeightBasis == null ? null : basisFromDb(r.saleWeightBasis!),
      driedWeight:
          r.driedWeightGrams == null ? null : Grams(r.driedWeightGrams!),
    );

ExpenseEntity expenseFromRow(Expense r) => ExpenseEntity(
      id: r.id,
      croppingId: r.croppingId,
      date: CalendarDate.parseIso(r.date),
      category: categoryFromDb(r.category),
      amount: Centavos(r.amountCentavos),
      notes: r.notes,
      linkedApplicationId: r.linkedApplicationId,
    );

HarvestEntity harvestFromRow(Harvest r) => HarvestEntity(
      id: r.id,
      croppingId: r.croppingId,
      date: CalendarDate.parseIso(r.date),
      totalWet: Grams(r.totalWetGrams),
      sacks: r.sacks,
      avgWetPerSack:
          r.avgWetGramsPerSack == null ? null : Grams(r.avgWetGramsPerSack!),
    );

SaleEntity saleFromRow(Sale r) => SaleEntity(
      id: r.id,
      croppingId: r.croppingId,
      quantity: Grams(r.quantityGrams),
      pricePerKg: Centavos(r.pricePerKgCentavos),
      buyer: r.buyer,
      date: CalendarDate.parseIso(r.date),
    );

ScheduledApplicationEntity applicationFromRow(ScheduledApplication r) =>
    ScheduledApplicationEntity(
      id: r.id,
      croppingId: r.croppingId,
      daysAfterPlanting: r.daysAfterPlanting,
      growthStage: r.growthStage,
      recommendedProduct: r.recommendedProduct,
      ratePerHectare: Grams(r.ratePerHectareGrams),
      sortOrder: r.sortOrder,
      state: appStateFromDb(r.state),
      actualDate:
          r.actualDate == null ? null : CalendarDate.parseIso(r.actualDate!),
      actualProduct: r.actualProduct,
      actualQuantity: r.actualQuantityGrams == null
          ? null
          : Grams(r.actualQuantityGrams!),
      cost: r.costCentavos == null ? null : Centavos(r.costCentavos!),
      skipReason: r.skipReason,
      linkedExpenseId: r.linkedExpenseId,
    );

SourceDb sourceToDb(ReferenceSource v) => switch (v) {
      ReferenceSource.seed => SourceDb.seed,
      ReferenceSource.published => SourceDb.published,
      ReferenceSource.farmer => SourceDb.farmer,
    };

ReferenceSource sourceFromDb(SourceDb v) => switch (v) {
      SourceDb.seed => ReferenceSource.seed,
      SourceDb.published => ReferenceSource.published,
      SourceDb.farmer => ReferenceSource.farmer,
    };
