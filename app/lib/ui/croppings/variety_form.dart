import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/enums.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/field_error.dart';

/// Add a custom variety. FR-010.
///
/// Maturity is optional on purpose: a farmer planting a local variety often does
/// not know the figure, and the spec's "Variety with unknown maturity" edge case
/// says the app should ask for the expected harvest date rather than invent one.
///
/// Saved as the farmer's own (FR-026c), so a later published variety list leaves
/// it alone.
class VarietyForm extends ConsumerStatefulWidget {
  const VarietyForm({required this.crop, super.key});

  final Crop crop;

  @override
  ConsumerState<VarietyForm> createState() => _VarietyFormState();
}

class _VarietyFormState extends ConsumerState<VarietyForm> {
  final _name = TextEditingController();
  final _maturity = TextEditingController();
  late Crop _crop = widget.crop;
  final _error = FieldError();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _maturity.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error.clear();
      _saving = true;
    });

    if (_name.text.trim().isEmpty) {
      setState(() {
        _saving = false;
        _error.set(l10n.errorFieldNameBlank);
      });
      return;
    }

    int? maturity;
    if (_maturity.text.trim().isNotEmpty) {
      maturity = int.tryParse(_maturity.text.trim());
      if (maturity == null || maturity <= 0) {
        setState(() {
          _saving = false;
          _error.set(l10n.errorNotANumber);
        });
        return;
      }
    }

    final id = await ref.read(templateRepositoryProvider).createVariety(
          name: _name.text,
          crop: _crop,
          maturityDays: maturity,
        );
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.varietyAdd),
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
            key: const Key('variety-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            label: Text(l10n.varietyName),
            statesController: _error.states,
            error: _error.widget,
          ),
          const SizedBox(height: 20),
          Text(l10n.varietyCrop, style: theme.typography.sm),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final crop in Crop.values) ...[
                Expanded(
                  child: FButton(
                    key: ValueKey('variety-crop-${crop.name}'),
                    style: crop == _crop
                        ? FButtonStyle.secondary()
                        : FButtonStyle.outline(),
                    onPress: () => setState(() => _crop = crop),
                    child: ButtonLabel(l10n.crop(crop)),
                  ),
                ),
                if (crop != Crop.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 20),
          FTextField(
            key: const Key('variety-maturity'),
            controller: _maturity,
            keyboardType: TextInputType.number,
            label: Text(l10n.varietyMaturity),
            description: Text(l10n.varietyMaturityHelp),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
