// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Saka';

  @override
  String get navHome => 'Home';

  @override
  String get navFields => 'Fields';

  @override
  String get navResults => 'Results';

  @override
  String get homeEmptyTitle => 'No croppings yet';

  @override
  String get homeEmptyBody =>
      'Add a field, then start a cropping to begin tracking what you spend and earn.';

  @override
  String get homeStartCropping => 'Start a cropping';

  @override
  String get homeActiveCroppings => 'Active croppings';

  @override
  String get homeUpcomingApplications => 'Fertilizer due next';

  @override
  String get homeUpcomingHarvests => 'Harvest coming up';

  @override
  String get homeAwaitingClosure => 'Harvested, not yet closed';

  @override
  String get syncUpToDate => 'All records backed up';

  @override
  String syncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records waiting to back up',
      one: '1 record waiting to back up',
    );
    return '$_temp0';
  }

  @override
  String get syncFailing => 'Records are not being backed up';

  @override
  String get syncGuest => 'Guest - saved on this phone only';

  @override
  String get fieldsTitle => 'Fields';

  @override
  String get fieldAdd => 'Add field';

  @override
  String get fieldName => 'Field name';

  @override
  String get fieldArea => 'Area (hectares)';

  @override
  String get fieldLocation => 'Location (optional)';

  @override
  String get fieldNotes => 'Notes (optional)';

  @override
  String get fieldAreaUnit => 'ha';

  @override
  String get errorFieldNameBlank => 'Enter a name for this field';

  @override
  String get errorFieldAreaNotPositive =>
      'Area must be more than zero hectares';

  @override
  String get errorAmountNotPositive => 'Enter an amount more than zero';

  @override
  String get errorPriceNotPositive => 'Enter a price more than zero';

  @override
  String get errorBuyerBlank => 'Enter who bought it';

  @override
  String get errorNotANumber => 'Enter a number, like 2.5';

  @override
  String get errorTooManyDecimals => 'Use fewer decimal places';

  @override
  String get resultExpenses => 'Total spent';

  @override
  String get resultRevenue => 'Total earned';

  @override
  String get resultProfit => 'Profit';

  @override
  String get resultLoss => 'Loss';

  @override
  String get resultYield => 'Harvest';

  @override
  String get resultYieldPerHectare => 'Tons per hectare';

  @override
  String get resultCostPerKg => 'Cost per kilo produced';

  @override
  String get resultNotApplicable => 'Not applicable';

  @override
  String get resultInProgress => 'In progress';

  @override
  String get resultProvisional => 'Provisional';

  @override
  String get resultFinal => 'Final';

  @override
  String get freshWeight => 'fresh weight';

  @override
  String get bagsUnit => 'bags';

  @override
  String get kgUnit => 'kg';

  @override
  String get tonsUnit => 'tons';

  @override
  String get guidanceDisclaimer =>
      'These are general recommendations. Adjust them to your soil test results or the advice of your local agriculturist.';

  @override
  String get guidanceUnverified =>
      'Recommended amounts are not yet available for this crop.';

  @override
  String guidanceSource(String attribution) {
    return 'Source: $attribution';
  }

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get fieldEdit => 'Edit field';

  @override
  String get fieldArchive => 'Archive field';

  @override
  String get fieldArchiveExplain =>
      'This field has croppings, so it is archived instead of deleted. Its history is kept.';

  @override
  String get fieldNoCroppings => 'No croppings on this field yet';

  @override
  String get fieldCroppingHistory => 'Cropping history';

  @override
  String get croppingStart => 'Start a cropping';

  @override
  String get croppingCrop => 'Crop';

  @override
  String get croppingCropRice => 'Rice';

  @override
  String get croppingCropCorn => 'Corn';

  @override
  String get croppingVariety => 'Variety';

  @override
  String get croppingMethod => 'Planting method';

  @override
  String get croppingMethodTransplanted => 'Transplanted';

  @override
  String get croppingMethodDirectSeeded => 'Direct-seeded';

  @override
  String get croppingSeason => 'Season planted';

  @override
  String get croppingSeasonWet => 'Wet season';

  @override
  String get croppingSeasonDry => 'Dry season';

  @override
  String get croppingPlantingDate => 'Planting date';

  @override
  String get croppingExpectedHarvest => 'Expected harvest';

  @override
  String get croppingExpectedHarvestHelp =>
      'Worked out from the variety. Change it if you expect a different date.';

  @override
  String croppingDaysSincePlanting(int days) {
    return '$days days since planting';
  }

  @override
  String get statusPlanted => 'Planted';

  @override
  String get statusGrowing => 'Growing';

  @override
  String get statusHarvested => 'Harvested';

  @override
  String get statusClosed => 'Closed';

  @override
  String get fieldBusyTitle => 'This field already has a cropping';

  @override
  String fieldBusyBody(String crop, String date) {
    return '$crop planted $date is still in the ground. Record its harvest before planting again.';
  }

  @override
  String get closePreviousTitle => 'Close the previous cropping?';

  @override
  String closePreviousBody(String crop, String date) {
    return '$crop planted $date was harvested but is still open. You can close it now, or leave it open to keep recording sales and costs.';
  }

  @override
  String get closePreviousLeaveOpen => 'Leave it open';

  @override
  String get closePreviousClose => 'Close it';

  @override
  String get closeCroppingTitle => 'Close this cropping?';

  @override
  String closeCroppingUnsold(String quantity) {
    return 'You still have $quantity kg unsold. Closing means no more costs or sales will be recorded.';
  }

  @override
  String get closeCroppingBody =>
      'Closing means no more costs or sales will be recorded on this cropping.';

  @override
  String get closeCroppingConfirm => 'Close cropping';

  @override
  String get reopenCropping => 'Reopen to make corrections';

  @override
  String get croppingClosedNotice =>
      'This cropping is closed. Reopen it to record anything more.';

  @override
  String get expensesTitle => 'Expenses';

  @override
  String get expenseAdd => 'Add expense';

  @override
  String get expenseDate => 'Date';

  @override
  String get expenseCategory => 'What for';

  @override
  String get expenseAmount => 'Amount';

  @override
  String get expenseNotes => 'Notes (optional)';

  @override
  String get expenseTotal => 'Total spent';

  @override
  String get expenseNone => 'No expenses recorded yet';

  @override
  String get categoryLandPreparation => 'Land preparation';

  @override
  String get categorySeeds => 'Seeds';

  @override
  String get categoryFertilizer => 'Fertilizer';

  @override
  String get categoryPesticideHerbicide => 'Pesticide / herbicide';

  @override
  String get categoryLabor => 'Labor';

  @override
  String get categoryIrrigation => 'Irrigation';

  @override
  String get categoryEquipmentRental => 'Equipment rental';

  @override
  String get categoryHarvestingThreshing => 'Harvesting / threshing';

  @override
  String get categoryHauling => 'Hauling';

  @override
  String get categoryOther => 'Other';

  @override
  String get whichCroppingTitle => 'Which cropping is this for?';

  @override
  String get whichCroppingBody =>
      'This field has more than one cropping open. Choose the one this belongs to.';

  @override
  String croppingLabel(String crop, String season, String date) {
    return '$crop, $season, planted $date';
  }

  @override
  String get harvestTitle => 'Harvest';

  @override
  String get harvestRecord => 'Record harvest';

  @override
  String get harvestDate => 'Harvest date';

  @override
  String get harvestBySacks => 'By sacks';

  @override
  String get harvestByTotal => 'Total weight';

  @override
  String get harvestSacks => 'Number of sacks';

  @override
  String get harvestAvgPerSack => 'Average wet kg per sack';

  @override
  String get harvestTotalKg => 'Total wet kg';

  @override
  String get harvestFreshWeightNote =>
      'Record the weight straight from the field, before drying.';

  @override
  String get harvestNone => 'No harvest recorded yet';

  @override
  String get salesTitle => 'Sales';

  @override
  String get saleAdd => 'Record a sale';

  @override
  String get saleQuantity => 'Quantity (kg)';

  @override
  String get salePricePerKg => 'Price per kg';

  @override
  String get saleBuyer => 'Buyer';

  @override
  String get saleDate => 'Date sold';

  @override
  String get saleNone => 'No sales recorded yet';

  @override
  String saleRemaining(String quantity, String basis) {
    return '$quantity kg $basis left unsold';
  }

  @override
  String get basisWet => 'wet';

  @override
  String get basisDry => 'dry';

  @override
  String get basisQuestion => 'Are you selling this wet or dry?';

  @override
  String get basisQuestionHelp =>
      'Most farmers sell the whole lot one way. You can change this while the cropping is open.';

  @override
  String get basisSellingWet => 'Selling wet';

  @override
  String get basisSellingDry => 'Selling dry';

  @override
  String get driedWeightTitle => 'Dried weight';

  @override
  String get driedWeightBody =>
      'How many kilos did the lot weigh after drying? Sales count down from this.';

  @override
  String get driedWeightField => 'Dried weight (kg)';

  @override
  String get errorSaleNoHarvest => 'Record the harvest before adding a sale';

  @override
  String errorSaleExceeds(String quantity) {
    return 'That is more than the $quantity kg left unsold';
  }

  @override
  String get errorSaleDriedWeightMissing =>
      'Enter the dried weight of the lot first';

  @override
  String get errorSaleNonPositive => 'Enter a quantity more than zero';

  @override
  String get resultTitle => 'Result';

  @override
  String get resultInProgressNote =>
      'This cropping is still growing. Only what you have spent so far is shown.';

  @override
  String get resultProvisionalNote =>
      'Still open. These figures will change as you add costs and sales.';

  @override
  String get resultBreakdown => 'Where the money went';

  @override
  String get accountTitle => 'Account';

  @override
  String get accountSignIn => 'Sign in';

  @override
  String get accountSignOut => 'Sign out';

  @override
  String get accountContinueAsGuest => 'Continue without an account';

  @override
  String get accountWithGoogle => 'Continue with Google';

  @override
  String get accountWithEmail => 'Use email and password';

  @override
  String accountSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get accountSignInFailed => 'Sign-in did not finish. Please try again.';

  @override
  String get accountOpensBrowser =>
      'Both buttons open a secure page to sign in. Your password is never typed into this app.';

  @override
  String get accountUnavailable =>
      'This copy of the app has no account service set up, so you can only continue without an account.';

  @override
  String get guestBannerTitle => 'Saved on this phone only';

  @override
  String get guestBannerBody =>
      'Your records are not backed up. If this phone is lost or broken they cannot be recovered. Create an account to keep them safe — everything you have entered comes with you.';

  @override
  String get guestBannerAction => 'Create an account';

  @override
  String get guestBannerDismiss => 'Not now';

  @override
  String get signOutTitle => 'Sign out?';

  @override
  String get signOutBody =>
      'Your records stay backed up and come back when you sign in again. They will be removed from this phone.';

  @override
  String get syncNotBackedUpTitle => 'Records are not being backed up';

  @override
  String syncNotBackedUpBody(String error) {
    return 'Something is stopping your records reaching the backup. They are still safe on this phone, but a lost phone would lose them. Last error: $error';
  }

  @override
  String syncLastBackedUp(String when) {
    return 'Last backed up $when';
  }

  @override
  String get syncNever => 'never';

  @override
  String get restoreInProgress => 'Bringing your records back…';

  @override
  String restoreDone(int count) {
    return '$count records restored';
  }

  @override
  String get scheduleTitle => 'Fertilizer';

  @override
  String get scheduleNone => 'No fertilizer steps for this cropping yet.';

  @override
  String get scheduleAddStep => 'Add a step';

  @override
  String get scheduleUpcoming => 'Coming up';

  @override
  String get scheduleDone => 'Done';

  @override
  String get scheduleSkipped => 'Skipped';

  @override
  String get scheduleOverdue => 'Overdue';

  @override
  String scheduleDueOn(String date) {
    return 'Due $date';
  }

  @override
  String scheduleDayAfterPlanting(int days) {
    return '$days days after planting';
  }

  @override
  String scheduleBuy(String bags, String kg) {
    return '$bags bags ($kg kg)';
  }

  @override
  String scheduleRate(String rate) {
    return '$rate kg per hectare';
  }

  @override
  String get scheduleAfterHarvest =>
      'The crop is off the field, so nothing more is due.';

  @override
  String get markDoneTitle => 'Mark as done';

  @override
  String get markDoneDate => 'Date applied';

  @override
  String get markDoneProduct => 'What you used';

  @override
  String get markDoneQuantity => 'How much (kg)';

  @override
  String get markDoneCost => 'What it cost';

  @override
  String get markDoneCostHelp =>
      'Leave empty if you are not recording the cost. Entering it adds a fertilizer expense to this cropping.';

  @override
  String get markDoneSkip => 'Skip this one';

  @override
  String get markSkipTitle => 'Skip this application?';

  @override
  String get markSkipReason => 'Why (optional)';

  @override
  String get markSkipConfirm => 'Skip it';

  @override
  String get markUndo => 'Undo';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsReminders => 'Fertilizer reminders';

  @override
  String get settingsRemindersHelp =>
      'Get a reminder 2 days before each application is due, and again on the day. Turn this off and you will still see what is coming up inside the app.';

  @override
  String get settingsRemindersDenied =>
      'Your phone is blocking notifications for this app. You can still see upcoming applications inside the app.';

  @override
  String get homeTitle => 'Saka';

  @override
  String homeHarvestExpected(String date) {
    return 'Harvest expected $date';
  }

  @override
  String homeUnsoldRemaining(String quantity, String basis) {
    return '$quantity kg $basis still unsold';
  }

  @override
  String get homeAwaitingClosureHelp =>
      'Harvested, but still open for sales and costs.';

  @override
  String get homeViewFields => 'All fields';

  @override
  String get homeDueToday => 'Due today';

  @override
  String homeDueIn(int days) {
    return 'Due in $days days';
  }

  @override
  String homeDueOverdue(int days) {
    return 'Overdue by $days days';
  }

  @override
  String get compareTitle => 'Compare croppings';

  @override
  String get compareNone => 'No croppings to compare yet';

  @override
  String get compareNoneFiltered => 'No croppings match these filters';

  @override
  String get compareAllFields => 'All fields';

  @override
  String get compareAllCrops => 'All crops';

  @override
  String get compareAllSeasons => 'Both seasons';

  @override
  String get compareClearFilters => 'Clear filters';

  @override
  String compareCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count croppings',
      one: '1 cropping',
    );
    return '$_temp0';
  }

  @override
  String get compareFreshWeightNote =>
      'Harvest is always recorded fresh from the field, so every yield and cost per kilo here is on the same basis and can be compared directly.';

  @override
  String get compareBestProfit => 'Best profit';

  @override
  String get compareOpen => 'Open';

  @override
  String get templatesTitle => 'Fertilizer recommendations';

  @override
  String get templatesHelp =>
      'These are the default steps used when you start a cropping. Change them to follow your soil test or your local agriculturist — your changes are kept even when new guidance arrives.';

  @override
  String get templatesNone => 'No recommendations available yet';

  @override
  String templateFor(String crop, String method) {
    return '$crop, $method';
  }

  @override
  String get templateYourEdit => 'Your version';

  @override
  String templateStepCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '1 step',
      zero: 'No steps',
    );
    return '$_temp0';
  }

  @override
  String get templateAddStep => 'Add a step';

  @override
  String get templateEditStep => 'Edit step';

  @override
  String get templateStepStage => 'Growth stage';

  @override
  String get templateStepDays => 'Days after planting';

  @override
  String get templateStepProduct => 'Fertilizer';

  @override
  String get templateStepRate => 'Rate per hectare (kg)';

  @override
  String get templateRemoveStep => 'Remove this step';

  @override
  String templateRemoveConfirm(String stage) {
    return 'Remove $stage from this recommendation?';
  }

  @override
  String get templateEditNote =>
      'Croppings you have already started keep the steps they were given. Changes here apply to croppings you start from now on.';

  @override
  String get templateMoveUp => 'Move up';

  @override
  String get templateMoveDown => 'Move down';

  @override
  String get varietyAdd => 'Add a variety';

  @override
  String get varietyName => 'Variety name';

  @override
  String get varietyMaturity => 'Days to harvest (optional)';

  @override
  String get varietyMaturityHelp =>
      'Leave empty if you do not know. You can enter the expected harvest date yourself when you start a cropping.';

  @override
  String get varietyCrop => 'Crop';

  @override
  String get scheduleEditTitle => 'Change this schedule';

  @override
  String get scheduleEditNote =>
      'This changes only this cropping. Your saved recommendations stay as they are.';

  @override
  String get scheduleAddStepHere => 'Add a step';

  @override
  String get scheduleRemoveStep => 'Remove this step';

  @override
  String scheduleRemoveConfirm(String stage) {
    return 'Remove $stage from this cropping\'s schedule?';
  }

  @override
  String get errorRequired => 'Fill this in';

  @override
  String get templatesNoSteps =>
      'No steps yet. Add one below to build this recommendation.';
}
