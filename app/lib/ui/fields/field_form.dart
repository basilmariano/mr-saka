import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/decimal_text.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/square_metres.dart';
import '../../domain/rules/validation.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/field_error.dart';

/// Add or edit a field. FR-001, FR-002, FR-003.
class FieldForm extends ConsumerStatefulWidget {
  const FieldForm({this.existing, super.key});

  final FieldEntity? existing;

  @override
  ConsumerState<FieldForm> createState() => _FieldFormState();
}

class _FieldFormState extends ConsumerState<FieldForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _area = TextEditingController(
    text: widget.existing == null
        ? ''
        : formatScaled(widget.existing!.area.value, 4),
  );
  late final TextEditingController _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  final _nameError = FieldError();
  final _areaError = FieldError();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _location.dispose();
    _notes.dispose();
    _nameError.dispose();
    _areaError.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _nameError.clear();
      _areaError.clear();
    });

    SquareMetres? area;
    try {
      area = SquareMetres.parseHectares(_area.text);
    } on DecimalFormatException catch (e) {
      setState(() => _areaError.set(e.reason.contains('decimal place')
          ? l10n.errorTooManyDecimals
          : l10n.errorNotANumber));
      return;
    }

    final failures = Validation.field(name: _name.text, area: area);
    if (failures.isNotEmpty) {
      setState(() {
        for (final failure in failures) {
          final message = l10n.validationFailure(failure);
          if (failure == ValidationFailure.fieldNameBlank) {
            _nameError.set(message);
          } else {
            _areaError.set(message);
          }
        }
      });
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(fieldRepositoryProvider);
    if (widget.existing == null) {
      await repository.create(
        name: _name.text,
        area: area,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
    } else {
      await repository.update(
        widget.existing!.copyWith(
          name: _name.text.trim(),
          area: area,
          location: _location.text.trim().isEmpty ? null : _location.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: FHeader.nested(
        title: Text(widget.existing == null ? l10n.fieldAdd : l10n.fieldEdit),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).pop())],
      ),
      // The primary action stays pinned, so it is reachable on a phone regardless
      // of screen height or keyboard state — a farmer should never scroll to save.
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
            key: const Key('field-name'),
            controller: _name,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.words,
            label: Text(l10n.fieldName),
            statesController: _nameError.states,
            error: _nameError.widget,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('field-area'),
            controller: _area,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.fieldArea),
            hint: l10n.fieldAreaUnit,
            statesController: _areaError.states,
            error: _areaError.widget,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('field-location'),
            controller: _location,
            label: Text(l10n.fieldLocation),
          ),
          const SizedBox(height: 16),
          FTextField.multiline(
            key: const Key('field-notes'),
            controller: _notes,
            // The .multiline factory sets minLines: 4; a smaller maxLines asserts.
            label: Text(l10n.fieldNotes),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
