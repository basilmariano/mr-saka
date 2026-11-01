import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// App name. Saka is Filipino for farm.
  ///
  /// In en, this message translates to:
  /// **'Saka'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navFields.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get navFields;

  /// No description provided for @navResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get navResults;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No croppings yet'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add a field, then start a cropping to begin tracking what you spend and earn.'**
  String get homeEmptyBody;

  /// No description provided for @homeStartCropping.
  ///
  /// In en, this message translates to:
  /// **'Start a cropping'**
  String get homeStartCropping;

  /// No description provided for @homeActiveCroppings.
  ///
  /// In en, this message translates to:
  /// **'Active croppings'**
  String get homeActiveCroppings;

  /// No description provided for @homeUpcomingApplications.
  ///
  /// In en, this message translates to:
  /// **'Fertilizer due next'**
  String get homeUpcomingApplications;

  /// No description provided for @homeUpcomingHarvests.
  ///
  /// In en, this message translates to:
  /// **'Harvest coming up'**
  String get homeUpcomingHarvests;

  /// No description provided for @homeAwaitingClosure.
  ///
  /// In en, this message translates to:
  /// **'Harvested, not yet closed'**
  String get homeAwaitingClosure;

  /// No description provided for @syncUpToDate.
  ///
  /// In en, this message translates to:
  /// **'All records backed up'**
  String get syncUpToDate;

  /// No description provided for @syncPending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 record waiting to back up} other{{count} records waiting to back up}}'**
  String syncPending(int count);

  /// No description provided for @syncFailing.
  ///
  /// In en, this message translates to:
  /// **'Records are not being backed up'**
  String get syncFailing;

  /// FR-060: a guest's records are not protected against losing the device, and the app says so plainly.
  ///
  /// In en, this message translates to:
  /// **'Guest - saved on this phone only'**
  String get syncGuest;

  /// No description provided for @fieldsTitle.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get fieldsTitle;

  /// No description provided for @fieldAdd.
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get fieldAdd;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get fieldName;

  /// No description provided for @fieldArea.
  ///
  /// In en, this message translates to:
  /// **'Area (hectares)'**
  String get fieldArea;

  /// No description provided for @fieldLocation.
  ///
  /// In en, this message translates to:
  /// **'Location (optional)'**
  String get fieldLocation;

  /// No description provided for @fieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get fieldNotes;

  /// No description provided for @fieldAreaUnit.
  ///
  /// In en, this message translates to:
  /// **'ha'**
  String get fieldAreaUnit;

  /// No description provided for @errorFieldNameBlank.
  ///
  /// In en, this message translates to:
  /// **'Enter a name for this field'**
  String get errorFieldNameBlank;

  /// No description provided for @errorFieldAreaNotPositive.
  ///
  /// In en, this message translates to:
  /// **'Area must be more than zero hectares'**
  String get errorFieldAreaNotPositive;

  /// No description provided for @errorAmountNotPositive.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount more than zero'**
  String get errorAmountNotPositive;

  /// No description provided for @errorPriceNotPositive.
  ///
  /// In en, this message translates to:
  /// **'Enter a price more than zero'**
  String get errorPriceNotPositive;

  /// No description provided for @errorBuyerBlank.
  ///
  /// In en, this message translates to:
  /// **'Enter who bought it'**
  String get errorBuyerBlank;

  /// No description provided for @errorNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number, like 2.5'**
  String get errorNotANumber;

  /// No description provided for @errorTooManyDecimals.
  ///
  /// In en, this message translates to:
  /// **'Use fewer decimal places'**
  String get errorTooManyDecimals;

  /// No description provided for @resultExpenses.
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get resultExpenses;

  /// No description provided for @resultRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total earned'**
  String get resultRevenue;

  /// No description provided for @resultProfit.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get resultProfit;

  /// No description provided for @resultLoss.
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get resultLoss;

  /// No description provided for @resultYield.
  ///
  /// In en, this message translates to:
  /// **'Harvest'**
  String get resultYield;

  /// No description provided for @resultYieldPerHectare.
  ///
  /// In en, this message translates to:
  /// **'Tons per hectare'**
  String get resultYieldPerHectare;

  /// No description provided for @resultCostPerKg.
  ///
  /// In en, this message translates to:
  /// **'Cost per kilo produced'**
  String get resultCostPerKg;

  /// No description provided for @resultNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'Not applicable'**
  String get resultNotApplicable;

  /// No description provided for @resultInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get resultInProgress;

  /// FR-042a: a harvested but open cropping recalculates as costs and sales land.
  ///
  /// In en, this message translates to:
  /// **'Provisional'**
  String get resultProvisional;

  /// No description provided for @resultFinal.
  ///
  /// In en, this message translates to:
  /// **'Final'**
  String get resultFinal;

  /// No description provided for @freshWeight.
  ///
  /// In en, this message translates to:
  /// **'fresh weight'**
  String get freshWeight;

  /// No description provided for @bagsUnit.
  ///
  /// In en, this message translates to:
  /// **'bags'**
  String get bagsUnit;

  /// No description provided for @kgUnit.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get kgUnit;

  /// No description provided for @tonsUnit.
  ///
  /// In en, this message translates to:
  /// **'tons'**
  String get tonsUnit;

  /// FR-026, shown wherever a fertilizer recommendation appears.
  ///
  /// In en, this message translates to:
  /// **'These are general recommendations. Adjust them to your soil test results or the advice of your local agriculturist.'**
  String get guidanceDisclaimer;

  /// Shown when the reference bundle is still a placeholder - research.md R9.
  ///
  /// In en, this message translates to:
  /// **'Recommended amounts are not yet available for this crop.'**
  String get guidanceUnverified;

  /// No description provided for @guidanceSource.
  ///
  /// In en, this message translates to:
  /// **'Source: {attribution}'**
  String guidanceSource(String attribution);

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @fieldEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit field'**
  String get fieldEdit;

  /// No description provided for @fieldArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive field'**
  String get fieldArchive;

  /// No description provided for @fieldArchiveExplain.
  ///
  /// In en, this message translates to:
  /// **'This field has croppings, so it is archived instead of deleted. Its history is kept.'**
  String get fieldArchiveExplain;

  /// No description provided for @fieldNoCroppings.
  ///
  /// In en, this message translates to:
  /// **'No croppings on this field yet'**
  String get fieldNoCroppings;

  /// No description provided for @fieldCroppingHistory.
  ///
  /// In en, this message translates to:
  /// **'Cropping history'**
  String get fieldCroppingHistory;

  /// No description provided for @croppingStart.
  ///
  /// In en, this message translates to:
  /// **'Start a cropping'**
  String get croppingStart;

  /// No description provided for @croppingCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get croppingCrop;

  /// No description provided for @croppingCropRice.
  ///
  /// In en, this message translates to:
  /// **'Rice'**
  String get croppingCropRice;

  /// No description provided for @croppingCropCorn.
  ///
  /// In en, this message translates to:
  /// **'Corn'**
  String get croppingCropCorn;

  /// No description provided for @croppingVariety.
  ///
  /// In en, this message translates to:
  /// **'Variety'**
  String get croppingVariety;

  /// No description provided for @croppingMethod.
  ///
  /// In en, this message translates to:
  /// **'Planting method'**
  String get croppingMethod;

  /// No description provided for @croppingMethodTransplanted.
  ///
  /// In en, this message translates to:
  /// **'Transplanted'**
  String get croppingMethodTransplanted;

  /// No description provided for @croppingMethodDirectSeeded.
  ///
  /// In en, this message translates to:
  /// **'Direct-seeded'**
  String get croppingMethodDirectSeeded;

  /// No description provided for @croppingSeason.
  ///
  /// In en, this message translates to:
  /// **'Season planted'**
  String get croppingSeason;

  /// No description provided for @croppingSeasonWet.
  ///
  /// In en, this message translates to:
  /// **'Wet season'**
  String get croppingSeasonWet;

  /// No description provided for @croppingSeasonDry.
  ///
  /// In en, this message translates to:
  /// **'Dry season'**
  String get croppingSeasonDry;

  /// No description provided for @croppingPlantingDate.
  ///
  /// In en, this message translates to:
  /// **'Planting date'**
  String get croppingPlantingDate;

  /// No description provided for @croppingExpectedHarvest.
  ///
  /// In en, this message translates to:
  /// **'Expected harvest'**
  String get croppingExpectedHarvest;

  /// No description provided for @croppingExpectedHarvestHelp.
  ///
  /// In en, this message translates to:
  /// **'Worked out from the variety. Change it if you expect a different date.'**
  String get croppingExpectedHarvestHelp;

  /// No description provided for @croppingDaysSincePlanting.
  ///
  /// In en, this message translates to:
  /// **'{days} days since planting'**
  String croppingDaysSincePlanting(int days);

  /// No description provided for @statusPlanted.
  ///
  /// In en, this message translates to:
  /// **'Planted'**
  String get statusPlanted;

  /// No description provided for @statusGrowing.
  ///
  /// In en, this message translates to:
  /// **'Growing'**
  String get statusGrowing;

  /// No description provided for @statusHarvested.
  ///
  /// In en, this message translates to:
  /// **'Harvested'**
  String get statusHarvested;

  /// No description provided for @statusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosed;

  /// No description provided for @fieldBusyTitle.
  ///
  /// In en, this message translates to:
  /// **'This field already has a cropping'**
  String get fieldBusyTitle;

  /// No description provided for @fieldBusyBody.
  ///
  /// In en, this message translates to:
  /// **'{crop} planted {date} is still in the ground. Record its harvest before planting again.'**
  String fieldBusyBody(String crop, String date);

  /// No description provided for @closePreviousTitle.
  ///
  /// In en, this message translates to:
  /// **'Close the previous cropping?'**
  String get closePreviousTitle;

  /// No description provided for @closePreviousBody.
  ///
  /// In en, this message translates to:
  /// **'{crop} planted {date} was harvested but is still open. You can close it now, or leave it open to keep recording sales and costs.'**
  String closePreviousBody(String crop, String date);

  /// No description provided for @closePreviousLeaveOpen.
  ///
  /// In en, this message translates to:
  /// **'Leave it open'**
  String get closePreviousLeaveOpen;

  /// No description provided for @closePreviousClose.
  ///
  /// In en, this message translates to:
  /// **'Close it'**
  String get closePreviousClose;

  /// No description provided for @closeCroppingTitle.
  ///
  /// In en, this message translates to:
  /// **'Close this cropping?'**
  String get closeCroppingTitle;

  /// No description provided for @closeCroppingUnsold.
  ///
  /// In en, this message translates to:
  /// **'You still have {quantity} kg unsold. Closing means no more costs or sales will be recorded.'**
  String closeCroppingUnsold(String quantity);

  /// No description provided for @closeCroppingBody.
  ///
  /// In en, this message translates to:
  /// **'Closing means no more costs or sales will be recorded on this cropping.'**
  String get closeCroppingBody;

  /// No description provided for @closeCroppingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Close cropping'**
  String get closeCroppingConfirm;

  /// No description provided for @reopenCropping.
  ///
  /// In en, this message translates to:
  /// **'Reopen to make corrections'**
  String get reopenCropping;

  /// No description provided for @croppingClosedNotice.
  ///
  /// In en, this message translates to:
  /// **'This cropping is closed. Reopen it to record anything more.'**
  String get croppingClosedNotice;

  /// No description provided for @expensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesTitle;

  /// No description provided for @expenseAdd.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get expenseAdd;

  /// No description provided for @expenseDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get expenseDate;

  /// No description provided for @expenseCategory.
  ///
  /// In en, this message translates to:
  /// **'What for'**
  String get expenseCategory;

  /// No description provided for @expenseAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get expenseAmount;

  /// No description provided for @expenseNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get expenseNotes;

  /// No description provided for @expenseTotal.
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get expenseTotal;

  /// No description provided for @expenseNone.
  ///
  /// In en, this message translates to:
  /// **'No expenses recorded yet'**
  String get expenseNone;

  /// No description provided for @categoryLandPreparation.
  ///
  /// In en, this message translates to:
  /// **'Land preparation'**
  String get categoryLandPreparation;

  /// No description provided for @categorySeeds.
  ///
  /// In en, this message translates to:
  /// **'Seeds'**
  String get categorySeeds;

  /// No description provided for @categoryFertilizer.
  ///
  /// In en, this message translates to:
  /// **'Fertilizer'**
  String get categoryFertilizer;

  /// No description provided for @categoryPesticideHerbicide.
  ///
  /// In en, this message translates to:
  /// **'Pesticide / herbicide'**
  String get categoryPesticideHerbicide;

  /// No description provided for @categoryLabor.
  ///
  /// In en, this message translates to:
  /// **'Labor'**
  String get categoryLabor;

  /// No description provided for @categoryIrrigation.
  ///
  /// In en, this message translates to:
  /// **'Irrigation'**
  String get categoryIrrigation;

  /// No description provided for @categoryEquipmentRental.
  ///
  /// In en, this message translates to:
  /// **'Equipment rental'**
  String get categoryEquipmentRental;

  /// No description provided for @categoryHarvestingThreshing.
  ///
  /// In en, this message translates to:
  /// **'Harvesting / threshing'**
  String get categoryHarvestingThreshing;

  /// No description provided for @categoryHauling.
  ///
  /// In en, this message translates to:
  /// **'Hauling'**
  String get categoryHauling;

  /// No description provided for @categoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOther;

  /// No description provided for @whichCroppingTitle.
  ///
  /// In en, this message translates to:
  /// **'Which cropping is this for?'**
  String get whichCroppingTitle;

  /// No description provided for @whichCroppingBody.
  ///
  /// In en, this message translates to:
  /// **'This field has more than one cropping open. Choose the one this belongs to.'**
  String get whichCroppingBody;

  /// No description provided for @croppingLabel.
  ///
  /// In en, this message translates to:
  /// **'{crop}, {season}, planted {date}'**
  String croppingLabel(String crop, String season, String date);

  /// No description provided for @harvestTitle.
  ///
  /// In en, this message translates to:
  /// **'Harvest'**
  String get harvestTitle;

  /// No description provided for @harvestRecord.
  ///
  /// In en, this message translates to:
  /// **'Record harvest'**
  String get harvestRecord;

  /// No description provided for @harvestDate.
  ///
  /// In en, this message translates to:
  /// **'Harvest date'**
  String get harvestDate;

  /// No description provided for @harvestBySacks.
  ///
  /// In en, this message translates to:
  /// **'By sacks'**
  String get harvestBySacks;

  /// No description provided for @harvestByTotal.
  ///
  /// In en, this message translates to:
  /// **'Total weight'**
  String get harvestByTotal;

  /// No description provided for @harvestSacks.
  ///
  /// In en, this message translates to:
  /// **'Number of sacks'**
  String get harvestSacks;

  /// No description provided for @harvestAvgPerSack.
  ///
  /// In en, this message translates to:
  /// **'Average wet kg per sack'**
  String get harvestAvgPerSack;

  /// No description provided for @harvestTotalKg.
  ///
  /// In en, this message translates to:
  /// **'Total wet kg'**
  String get harvestTotalKg;

  /// No description provided for @harvestFreshWeightNote.
  ///
  /// In en, this message translates to:
  /// **'Record the weight straight from the field, before drying.'**
  String get harvestFreshWeightNote;

  /// No description provided for @harvestNone.
  ///
  /// In en, this message translates to:
  /// **'No harvest recorded yet'**
  String get harvestNone;

  /// No description provided for @salesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesTitle;

  /// No description provided for @saleAdd.
  ///
  /// In en, this message translates to:
  /// **'Record a sale'**
  String get saleAdd;

  /// No description provided for @saleQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity (kg)'**
  String get saleQuantity;

  /// No description provided for @salePricePerKg.
  ///
  /// In en, this message translates to:
  /// **'Price per kg'**
  String get salePricePerKg;

  /// No description provided for @saleBuyer.
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get saleBuyer;

  /// No description provided for @saleDate.
  ///
  /// In en, this message translates to:
  /// **'Date sold'**
  String get saleDate;

  /// No description provided for @saleNone.
  ///
  /// In en, this message translates to:
  /// **'No sales recorded yet'**
  String get saleNone;

  /// No description provided for @saleRemaining.
  ///
  /// In en, this message translates to:
  /// **'{quantity} kg {basis} left unsold'**
  String saleRemaining(String quantity, String basis);

  /// No description provided for @basisWet.
  ///
  /// In en, this message translates to:
  /// **'wet'**
  String get basisWet;

  /// No description provided for @basisDry.
  ///
  /// In en, this message translates to:
  /// **'dry'**
  String get basisDry;

  /// No description provided for @basisQuestion.
  ///
  /// In en, this message translates to:
  /// **'Are you selling this wet or dry?'**
  String get basisQuestion;

  /// No description provided for @basisQuestionHelp.
  ///
  /// In en, this message translates to:
  /// **'Most farmers sell the whole lot one way. You can change this while the cropping is open.'**
  String get basisQuestionHelp;

  /// No description provided for @basisSellingWet.
  ///
  /// In en, this message translates to:
  /// **'Selling wet'**
  String get basisSellingWet;

  /// No description provided for @basisSellingDry.
  ///
  /// In en, this message translates to:
  /// **'Selling dry'**
  String get basisSellingDry;

  /// No description provided for @driedWeightTitle.
  ///
  /// In en, this message translates to:
  /// **'Dried weight'**
  String get driedWeightTitle;

  /// No description provided for @driedWeightBody.
  ///
  /// In en, this message translates to:
  /// **'How many kilos did the lot weigh after drying? Sales count down from this.'**
  String get driedWeightBody;

  /// No description provided for @driedWeightField.
  ///
  /// In en, this message translates to:
  /// **'Dried weight (kg)'**
  String get driedWeightField;

  /// No description provided for @errorSaleNoHarvest.
  ///
  /// In en, this message translates to:
  /// **'Record the harvest before adding a sale'**
  String get errorSaleNoHarvest;

  /// No description provided for @errorSaleExceeds.
  ///
  /// In en, this message translates to:
  /// **'That is more than the {quantity} kg left unsold'**
  String errorSaleExceeds(String quantity);

  /// No description provided for @errorSaleDriedWeightMissing.
  ///
  /// In en, this message translates to:
  /// **'Enter the dried weight of the lot first'**
  String get errorSaleDriedWeightMissing;

  /// No description provided for @errorSaleNonPositive.
  ///
  /// In en, this message translates to:
  /// **'Enter a quantity more than zero'**
  String get errorSaleNonPositive;

  /// No description provided for @resultTitle.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get resultTitle;

  /// No description provided for @resultInProgressNote.
  ///
  /// In en, this message translates to:
  /// **'This cropping is still growing. Only what you have spent so far is shown.'**
  String get resultInProgressNote;

  /// No description provided for @resultProvisionalNote.
  ///
  /// In en, this message translates to:
  /// **'Still open. These figures will change as you add costs and sales.'**
  String get resultProvisionalNote;

  /// No description provided for @resultBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Where the money went'**
  String get resultBreakdown;

  /// No description provided for @accountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountTitle;

  /// No description provided for @accountSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get accountSignIn;

  /// No description provided for @accountSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountSignOut;

  /// No description provided for @accountContinueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue without an account'**
  String get accountContinueAsGuest;

  /// No description provided for @accountWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get accountWithGoogle;

  /// No description provided for @accountWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Use email and password'**
  String get accountWithEmail;

  /// No description provided for @accountSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String accountSignedInAs(String email);

  /// No description provided for @accountSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in did not finish. Please try again.'**
  String get accountSignInFailed;

  /// No description provided for @accountOpensBrowser.
  ///
  /// In en, this message translates to:
  /// **'Both buttons open a secure page to sign in. Your password is never typed into this app.'**
  String get accountOpensBrowser;

  /// No description provided for @accountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This copy of the app has no account service set up, so you can only continue without an account.'**
  String get accountUnavailable;

  /// No description provided for @guestBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone only'**
  String get guestBannerTitle;

  /// No description provided for @guestBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Your records are not backed up. If this phone is lost or broken they cannot be recovered. Create an account to keep them safe — everything you have entered comes with you.'**
  String get guestBannerBody;

  /// No description provided for @guestBannerAction.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get guestBannerAction;

  /// No description provided for @guestBannerDismiss.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get guestBannerDismiss;

  /// No description provided for @signOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutTitle;

  /// No description provided for @signOutBody.
  ///
  /// In en, this message translates to:
  /// **'Your records stay backed up and come back when you sign in again. They will be removed from this phone.'**
  String get signOutBody;

  /// No description provided for @syncNotBackedUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Records are not being backed up'**
  String get syncNotBackedUpTitle;

  /// No description provided for @syncNotBackedUpBody.
  ///
  /// In en, this message translates to:
  /// **'Something is stopping your records reaching the backup. They are still safe on this phone, but a lost phone would lose them. Last error: {error}'**
  String syncNotBackedUpBody(String error);

  /// No description provided for @syncLastBackedUp.
  ///
  /// In en, this message translates to:
  /// **'Last backed up {when}'**
  String syncLastBackedUp(String when);

  /// No description provided for @syncNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get syncNever;

  /// No description provided for @restoreInProgress.
  ///
  /// In en, this message translates to:
  /// **'Bringing your records back…'**
  String get restoreInProgress;

  /// No description provided for @restoreDone.
  ///
  /// In en, this message translates to:
  /// **'{count} records restored'**
  String restoreDone(int count);

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Fertilizer'**
  String get scheduleTitle;

  /// No description provided for @scheduleNone.
  ///
  /// In en, this message translates to:
  /// **'No fertilizer steps for this cropping yet.'**
  String get scheduleNone;

  /// No description provided for @scheduleAddStep.
  ///
  /// In en, this message translates to:
  /// **'Add a step'**
  String get scheduleAddStep;

  /// No description provided for @scheduleUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Coming up'**
  String get scheduleUpcoming;

  /// No description provided for @scheduleDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get scheduleDone;

  /// No description provided for @scheduleSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get scheduleSkipped;

  /// No description provided for @scheduleOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get scheduleOverdue;

  /// No description provided for @scheduleDueOn.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String scheduleDueOn(String date);

  /// No description provided for @scheduleDayAfterPlanting.
  ///
  /// In en, this message translates to:
  /// **'{days} days after planting'**
  String scheduleDayAfterPlanting(int days);

  /// No description provided for @scheduleBuy.
  ///
  /// In en, this message translates to:
  /// **'{bags} bags ({kg} kg)'**
  String scheduleBuy(String bags, String kg);

  /// No description provided for @scheduleRate.
  ///
  /// In en, this message translates to:
  /// **'{rate} kg per hectare'**
  String scheduleRate(String rate);

  /// No description provided for @scheduleAfterHarvest.
  ///
  /// In en, this message translates to:
  /// **'The crop is off the field, so nothing more is due.'**
  String get scheduleAfterHarvest;

  /// No description provided for @markDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark as done'**
  String get markDoneTitle;

  /// No description provided for @markDoneDate.
  ///
  /// In en, this message translates to:
  /// **'Date applied'**
  String get markDoneDate;

  /// No description provided for @markDoneProduct.
  ///
  /// In en, this message translates to:
  /// **'What you used'**
  String get markDoneProduct;

  /// No description provided for @markDoneQuantity.
  ///
  /// In en, this message translates to:
  /// **'How much (kg)'**
  String get markDoneQuantity;

  /// No description provided for @markDoneCost.
  ///
  /// In en, this message translates to:
  /// **'What it cost'**
  String get markDoneCost;

  /// No description provided for @markDoneCostHelp.
  ///
  /// In en, this message translates to:
  /// **'Leave empty if you are not recording the cost. Entering it adds a fertilizer expense to this cropping.'**
  String get markDoneCostHelp;

  /// No description provided for @markDoneSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip this one'**
  String get markDoneSkip;

  /// No description provided for @markSkipTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip this application?'**
  String get markSkipTitle;

  /// No description provided for @markSkipReason.
  ///
  /// In en, this message translates to:
  /// **'Why (optional)'**
  String get markSkipReason;

  /// No description provided for @markSkipConfirm.
  ///
  /// In en, this message translates to:
  /// **'Skip it'**
  String get markSkipConfirm;

  /// No description provided for @markUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get markUndo;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsReminders.
  ///
  /// In en, this message translates to:
  /// **'Fertilizer reminders'**
  String get settingsReminders;

  /// No description provided for @settingsRemindersHelp.
  ///
  /// In en, this message translates to:
  /// **'Get a reminder 2 days before each application is due, and again on the day. Turn this off and you will still see what is coming up inside the app.'**
  String get settingsRemindersHelp;

  /// No description provided for @settingsRemindersDenied.
  ///
  /// In en, this message translates to:
  /// **'Your phone is blocking notifications for this app. You can still see upcoming applications inside the app.'**
  String get settingsRemindersDenied;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Saka'**
  String get homeTitle;

  /// No description provided for @homeHarvestExpected.
  ///
  /// In en, this message translates to:
  /// **'Harvest expected {date}'**
  String homeHarvestExpected(String date);

  /// No description provided for @homeUnsoldRemaining.
  ///
  /// In en, this message translates to:
  /// **'{quantity} kg {basis} still unsold'**
  String homeUnsoldRemaining(String quantity, String basis);

  /// No description provided for @homeAwaitingClosureHelp.
  ///
  /// In en, this message translates to:
  /// **'Harvested, but still open for sales and costs.'**
  String get homeAwaitingClosureHelp;

  /// No description provided for @homeViewFields.
  ///
  /// In en, this message translates to:
  /// **'All fields'**
  String get homeViewFields;

  /// No description provided for @homeDueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get homeDueToday;

  /// No description provided for @homeDueIn.
  ///
  /// In en, this message translates to:
  /// **'Due in {days} days'**
  String homeDueIn(int days);

  /// No description provided for @homeDueOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue by {days} days'**
  String homeDueOverdue(int days);

  /// No description provided for @compareTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare croppings'**
  String get compareTitle;

  /// No description provided for @compareNone.
  ///
  /// In en, this message translates to:
  /// **'No croppings to compare yet'**
  String get compareNone;

  /// No description provided for @compareNoneFiltered.
  ///
  /// In en, this message translates to:
  /// **'No croppings match these filters'**
  String get compareNoneFiltered;

  /// No description provided for @compareAllFields.
  ///
  /// In en, this message translates to:
  /// **'All fields'**
  String get compareAllFields;

  /// No description provided for @compareAllCrops.
  ///
  /// In en, this message translates to:
  /// **'All crops'**
  String get compareAllCrops;

  /// No description provided for @compareAllSeasons.
  ///
  /// In en, this message translates to:
  /// **'Both seasons'**
  String get compareAllSeasons;

  /// No description provided for @compareClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get compareClearFilters;

  /// No description provided for @compareCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 cropping} other{{count} croppings}}'**
  String compareCount(int count);

  /// No description provided for @compareFreshWeightNote.
  ///
  /// In en, this message translates to:
  /// **'Harvest is always recorded fresh from the field, so every yield and cost per kilo here is on the same basis and can be compared directly.'**
  String get compareFreshWeightNote;

  /// No description provided for @compareBestProfit.
  ///
  /// In en, this message translates to:
  /// **'Best profit'**
  String get compareBestProfit;

  /// No description provided for @compareOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get compareOpen;

  /// No description provided for @templatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Fertilizer recommendations'**
  String get templatesTitle;

  /// No description provided for @templatesHelp.
  ///
  /// In en, this message translates to:
  /// **'These are the default steps used when you start a cropping. Change them to follow your soil test or your local agriculturist — your changes are kept even when new guidance arrives.'**
  String get templatesHelp;

  /// No description provided for @templatesNone.
  ///
  /// In en, this message translates to:
  /// **'No recommendations available yet'**
  String get templatesNone;

  /// No description provided for @templateFor.
  ///
  /// In en, this message translates to:
  /// **'{crop}, {method}'**
  String templateFor(String crop, String method);

  /// No description provided for @templateYourEdit.
  ///
  /// In en, this message translates to:
  /// **'Your version'**
  String get templateYourEdit;

  /// No description provided for @templateStepCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No steps} =1{1 step} other{{count} steps}}'**
  String templateStepCount(int count);

  /// No description provided for @templateAddStep.
  ///
  /// In en, this message translates to:
  /// **'Add a step'**
  String get templateAddStep;

  /// No description provided for @templateEditStep.
  ///
  /// In en, this message translates to:
  /// **'Edit step'**
  String get templateEditStep;

  /// No description provided for @templateStepStage.
  ///
  /// In en, this message translates to:
  /// **'Growth stage'**
  String get templateStepStage;

  /// No description provided for @templateStepDays.
  ///
  /// In en, this message translates to:
  /// **'Days after planting'**
  String get templateStepDays;

  /// No description provided for @templateStepProduct.
  ///
  /// In en, this message translates to:
  /// **'Fertilizer'**
  String get templateStepProduct;

  /// No description provided for @templateStepRate.
  ///
  /// In en, this message translates to:
  /// **'Rate per hectare (kg)'**
  String get templateStepRate;

  /// No description provided for @templateRemoveStep.
  ///
  /// In en, this message translates to:
  /// **'Remove this step'**
  String get templateRemoveStep;

  /// No description provided for @templateRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {stage} from this recommendation?'**
  String templateRemoveConfirm(String stage);

  /// No description provided for @templateEditNote.
  ///
  /// In en, this message translates to:
  /// **'Croppings you have already started keep the steps they were given. Changes here apply to croppings you start from now on.'**
  String get templateEditNote;

  /// No description provided for @templateMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get templateMoveUp;

  /// No description provided for @templateMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get templateMoveDown;

  /// No description provided for @varietyAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a variety'**
  String get varietyAdd;

  /// No description provided for @varietyName.
  ///
  /// In en, this message translates to:
  /// **'Variety name'**
  String get varietyName;

  /// No description provided for @varietyMaturity.
  ///
  /// In en, this message translates to:
  /// **'Days to harvest (optional)'**
  String get varietyMaturity;

  /// No description provided for @varietyMaturityHelp.
  ///
  /// In en, this message translates to:
  /// **'Leave empty if you do not know. You can enter the expected harvest date yourself when you start a cropping.'**
  String get varietyMaturityHelp;

  /// No description provided for @varietyCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get varietyCrop;

  /// No description provided for @scheduleEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Change this schedule'**
  String get scheduleEditTitle;

  /// No description provided for @scheduleEditNote.
  ///
  /// In en, this message translates to:
  /// **'This changes only this cropping. Your saved recommendations stay as they are.'**
  String get scheduleEditNote;

  /// No description provided for @scheduleAddStepHere.
  ///
  /// In en, this message translates to:
  /// **'Add a step'**
  String get scheduleAddStepHere;

  /// No description provided for @scheduleRemoveStep.
  ///
  /// In en, this message translates to:
  /// **'Remove this step'**
  String get scheduleRemoveStep;

  /// No description provided for @scheduleRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {stage} from this cropping\'s schedule?'**
  String scheduleRemoveConfirm(String stage);

  /// No description provided for @errorRequired.
  ///
  /// In en, this message translates to:
  /// **'Fill this in'**
  String get errorRequired;

  /// No description provided for @templatesNoSteps.
  ///
  /// In en, this message translates to:
  /// **'No steps yet. Add one below to build this recommendation.'**
  String get templatesNoSteps;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
