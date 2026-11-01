import 'package:flutter/material.dart' show showDatePicker;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/model/centavos.dart';
import '../../domain/model/decimal_text.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/enums.dart';
import '../../domain/rules/validation.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/field_error.dart';

/// Log an expense against a cropping. FR-027, FR-031, FR-031a.
///
/// Built for the under-30-seconds target in SC-002: amount first and autofocused,
/// category as a single tap, date defaulting to today, and the save action pinned so
/// a farmer never scrolls past ten categories to reach it.
class ExpenseForm extends ConsumerStatefulWidget {
  const ExpenseForm({required this.croppingId, this.existing, super.key});

  final String croppingId;
  final ExpenseEntity? existing;

  @override
  ConsumerState<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<ExpenseForm> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : formatScaled(widget.existing!.amount.value, 2),
  );
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late ExpenseCategory _category =
      widget.existing?.category ?? ExpenseCategory.labor;
  late CalendarDate _date = widget.existing?.date ?? ref.read(todayProvider);
  final _amountError = FieldError();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    _amountError.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(_amountError.clear);

    Centavos amount;
    try {
      amount = Centavos.parse(_amount.text);
    } on DecimalFormatException catch (e) {
      setState(() => _amountError.set(e.reason.contains('decimal place')
          ? l10n.errorTooManyDecimals
          : l10n.errorNotANumber));
      return;
    }

    final failures = Validation.expense(amount: amount);
    if (failures.isNotEmpty) {
      setState(() => _amountError.set(l10n.validationFailure(failures.first)));
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(expenseRepositoryProvider);
    if (widget.existing == null) {
      await repository.create(
        croppingId: widget.croppingId,
        date: _date,
        category: _category,
        amount: amount,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
    } else {
      await repository.update(
        ExpenseEntity(
          id: widget.existing!.id,
          croppingId: widget.existing!.croppingId,
          date: _date,
          category: _category,
          amount: amount,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          linkedApplicationId: widget.existing!.linkedApplicationId,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.expenseAdd),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).pop())],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FButton(
          key: const Key('save-button'),
          onPress: _saving ? null : _save,
          child: ButtonLabel(l10n.actionSave),
        ),
      ),
      child: ListView(
        children: [
          FTextField(
            key: const Key('expense-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.expenseAmount),
            hint: '₱',
            statesController: _amountError.states,
            error: _amountError.widget,
          ),
          const SizedBox(height: 20),
          Text(l10n.expenseCategory, style: theme.typography.sm),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in ExpenseCategory.values)
                FButton(
                  key: ValueKey('category-${category.name}'),
                  mainAxisSize: MainAxisSize.min,
                  style: _category == category
                      ? FButtonStyle.secondary()
                      : FButtonStyle.outline(),
                  onPress: () => setState(() => _category = category),
                  child: ButtonLabel(l10n.categoryLabel(category)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FTileGroup(
            children: [
              FTile(
                title: Text(l10n.expenseDate),
                subtitle: Text(l10n.formatDate(_date)),
                suffix: const Icon(FIcons.calendar),
                // FR-031a: no date restriction. Land prep precedes planting and
                // hauling follows harvest; both are normal and neither warns.
                onPress: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date.toDateTime(),
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _date = CalendarDate.fromDateTime(picked));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('expense-notes'),
            controller: _notes,
            label: Text(l10n.expenseNotes),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
