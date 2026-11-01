import '../../../domain/calc/date_calc.dart';
import '../../../domain/model/calendar_date.dart';
import '../../../domain/model/entities.dart';
import '../../../domain/model/enums.dart';
import '../../../domain/model/square_metres.dart';
import '../../../domain/rules/weight_basis.dart';
import 'application_repository.dart';
import 'cropping_repository.dart';
import 'field_repository.dart';
import 'sale_repository.dart';

/// A cropping currently in the ground. FR-044.
class ActiveCropping {
  const ActiveCropping({
    required this.cropping,
    required this.fieldName,
    required this.daysSincePlanting,
  });

  final CroppingEntity cropping;
  final String fieldName;
  final int daysSincePlanting;
}

/// A fertilizer application coming due. FR-045.
class UpcomingApplication {
  const UpcomingApplication({
    required this.application,
    required this.croppingId,
    required this.fieldName,
    required this.dueDate,
    required this.quantityBags,
    required this.quantityKg,
    required this.daysUntilDue,
  });

  final ScheduledApplicationEntity application;
  final String croppingId;
  final String fieldName;
  final CalendarDate dueDate;
  final String quantityBags;
  final String quantityKg;

  /// Negative when overdue.
  final int daysUntilDue;

  bool get isOverdue => daysUntilDue < 0;
}

/// A cropping whose expected harvest is near. FR-046.
class UpcomingHarvest {
  const UpcomingHarvest({
    required this.cropping,
    required this.fieldName,
    required this.expectedDate,
  });

  final CroppingEntity cropping;
  final String fieldName;
  final CalendarDate expectedDate;
}

/// Harvested but not yet closed. FR-046a.
class AwaitingClosure {
  const AwaitingClosure({
    required this.cropping,
    required this.fieldName,
    required this.remaining,
  });

  final CroppingEntity cropping;
  final String fieldName;

  /// Null when the cropping is sold dry and the dried weight is not recorded yet.
  final Lot? remaining;
}

/// Everything the home screen shows.
class HomeSummary {
  const HomeSummary({
    required this.active,
    required this.upcomingApplications,
    required this.upcomingHarvests,
    required this.awaitingClosure,
  });

  final List<ActiveCropping> active;
  final List<UpcomingApplication> upcomingApplications;
  final List<UpcomingHarvest> upcomingHarvests;
  final List<AwaitingClosure> awaitingClosure;

  bool get isEmpty =>
      active.isEmpty &&
      upcomingApplications.isEmpty &&
      upcomingHarvests.isEmpty &&
      awaitingClosure.isEmpty;
}

/// Assembles the home screen. FR-044 to FR-046b.
///
/// Computed entirely from the local database, so the home screen works offline —
/// which matters because it is the surface the farmer opens first, often in the
/// field with no signal.
class HomeRepository {
  HomeRepository({
    required this.croppings,
    required this.applications,
    required this.fields,
    required this.sales,
  });

  final CroppingRepository croppings;
  final ApplicationRepository applications;
  final FieldRepository fields;
  final SaleRepository sales;

  /// How far ahead an expected harvest counts as "coming up".
  static const int harvestHorizonDays = 21;

  /// How far ahead a fertilizer application counts as "due next".
  static const int applicationHorizonDays = 14;

  Future<HomeSummary> load({required CalendarDate today}) async {
    final open = await croppings.allOpen();

    final active = <ActiveCropping>[];
    final upcomingApplications = <UpcomingApplication>[];
    final upcomingHarvests = <UpcomingHarvest>[];
    final awaiting = <AwaitingClosure>[];

    for (final cropping in open) {
      final field = await fields.byId(cropping.fieldId);
      if (field == null) continue;

      if (cropping.status == CroppingStatus.harvested) {
        // FR-046a: keep these visible with their unsold quantity, so outstanding
        // sales and post-harvest costs are not forgotten once the field has been
        // replanted and the farmer has mentally moved on.
        awaiting.add(
          AwaitingClosure(
            cropping: cropping,
            fieldName: field.name,
            remaining: await sales.remaining(cropping),
          ),
        );
        continue;
      }

      active.add(
        ActiveCropping(
          cropping: cropping,
          fieldName: field.name,
          daysSincePlanting: DateCalc.daysSincePlanting(
            plantingDate: cropping.plantingDate,
            today: today,
          ),
        ),
      );

      _collectApplications(
        into: upcomingApplications,
        cropping: cropping,
        fieldName: field.name,
        area: field.area,
        schedule: await applications.forCropping(cropping.id),
        today: today,
      );

      final expected = cropping.expectedHarvestDate;
      if (expected != null) {
        final days = today.daysUntil(expected);
        if (days >= 0 && days <= harvestHorizonDays) {
          upcomingHarvests.add(
            UpcomingHarvest(
              cropping: cropping,
              fieldName: field.name,
              expectedDate: expected,
            ),
          );
        }
      }
    }

    // FR-045: due-date order, so the next thing to do is the first thing seen.
    upcomingApplications.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    upcomingHarvests.sort((a, b) => a.expectedDate.compareTo(b.expectedDate));
    active.sort((a, b) => b.daysSincePlanting.compareTo(a.daysSincePlanting));

    return HomeSummary(
      active: active,
      upcomingApplications: upcomingApplications,
      upcomingHarvests: upcomingHarvests,
      awaitingClosure: awaiting,
    );
  }

  void _collectApplications({
    required List<UpcomingApplication> into,
    required CroppingEntity cropping,
    required String fieldName,
    required SquareMetres area,
    required List<ScheduledApplicationEntity> schedule,
    required CalendarDate today,
  }) {
    for (final application in schedule) {
      if (!application.isPending) continue;
      final due = application.dueDate(cropping.plantingDate);
      final days = today.daysUntil(due);
      // Overdue entries stay, however old: FR-018 flags them and the home screen
      // is where a farmer notices one they missed.
      if (days > applicationHorizonDays) continue;
      into.add(
        UpcomingApplication(
          application: application,
          croppingId: cropping.id,
          fieldName: fieldName,
          dueDate: due,
          quantityBags: application.recommendedQuantity(area).formatBags(),
          quantityKg: application.recommendedQuantity(area).formatKg(),
          daysUntilDue: days,
        ),
      );
    }
  }
}
