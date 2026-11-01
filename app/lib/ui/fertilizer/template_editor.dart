import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/decimal_text.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/grams.dart';
import '../../domain/model/reference.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/confirm.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/field_error.dart';

/// The list of fertilizer templates. FR-024.
class TemplateListScreen extends ConsumerWidget {
  const TemplateListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final templates = ref.watch(templatesProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.templatesTitle),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).pop())],
      ),
      child: templates.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => Center(child: Text('$error')),
        data: (list) => ListView(
          children: [
            Text(l10n.templatesHelp, style: theme.typography.sm),
            const SizedBox(height: 16),
            if (list.isEmpty)
              Text(
                l10n.templatesNone,
                style: theme.typography.sm
                    .copyWith(color: theme.colors.mutedForeground),
              )
            else
              FTileGroup(
                children: [
                  for (final template in list)
                    FTile(
                      key: ValueKey('template-${template.id}'),
                      title: Text(
                        l10n.templateFor(
                          l10n.crop(template.crop),
                          l10n.plantingMethod(template.plantingMethod),
                        ),
                      ),
                      subtitle: Text(l10n.templateStepCount(template.steps.length)),
                      // FR-026c made visible: the farmer can see which
                      // recommendations are theirs and so protected from updates.
                      details: template.source == ReferenceSource.farmer
                          ? FBadge(
                              style: FBadgeStyle.secondary(),
                              child: Text(l10n.templateYourEdit),
                            )
                          : null,
                      suffix: const Icon(FIcons.chevronRight),
                      onPress: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                TemplateEditorScreen(templateId: template.id),
                          ),
                        );
                        ref.invalidate(templatesProvider);
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Editing one template's steps. FR-024, FR-025, FR-026c.
class TemplateEditorScreen extends ConsumerWidget {
  const TemplateEditorScreen({required this.templateId, super.key});

  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final template = ref.watch(templateByIdProvider(templateId));

    void refresh() => ref
      ..invalidate(templateByIdProvider(templateId))
      ..invalidate(templatesProvider)
      ..invalidate(guidanceIsPlaceholderProvider);

    return template.when(
      loading: () => const FScaffold(child: Center(child: FCircularProgress())),
      error: (error, _) => FScaffold(child: Center(child: Text('$error'))),
      data: (t) {
        if (t == null) return const FScaffold(child: SizedBox.shrink());
        return FScaffold(
          header: FHeader.nested(
            title: Text(
              l10n.templateFor(
                l10n.crop(t.crop),
                l10n.plantingMethod(t.plantingMethod),
              ),
            ),
            prefixes: [
              FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
            ],
          ),
          footer: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FButton(
              key: const Key('add-step-button'),
              prefix: const Icon(FIcons.plus),
              onPress: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StepEditorScreen(templateId: templateId),
                  ),
                );
                refresh();
              },
              child: ButtonLabel(l10n.templateAddStep),
            ),
          ),
          child: ListView(
            children: [
              // FR-025 said plainly, because it is not obvious: a farmer who
              // edits mid-season would otherwise expect their running cropping
              // to change.
              FAlert(
                icon: const Icon(FIcons.info),
                title: Text(l10n.templateEditNote),
              ),
              const SizedBox(height: 16),
              if (t.steps.isEmpty)
                Text(
                  l10n.templatesNoSteps,
                  style: theme.typography.sm
                      .copyWith(color: theme.colors.mutedForeground),
                )
              else
                FTileGroup(
                  children: [
                    for (var i = 0; i < t.steps.length; i++)
                      _StepTile(
                        templateId: templateId,
                        step: t.steps[i],
                        index: i,
                        total: t.steps.length,
                        allStepIds: [
                          for (final step in t.steps)
                            if (step.id != null) step.id!,
                        ],
                        onChanged: refresh,
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StepTile extends ConsumerWidget with FTileMixin {
  const _StepTile({
    required this.templateId,
    required this.step,
    required this.index,
    required this.total,
    required this.allStepIds,
    required this.onChanged,
  });

  final String templateId;
  final TemplateStepRef step;
  final int index;
  final int total;
  final List<String> allStepIds;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(templateRepositoryProvider);

    Future<void> move(int delta) async {
      final reordered = [...allStepIds];
      final from = reordered.indexOf(step.id ?? '');
      final to = from + delta;
      if (from < 0 || to < 0 || to >= reordered.length) return;
      reordered.insert(to, reordered.removeAt(from));
      await repository.reorderSteps(
        templateId: templateId,
        stepIdsInOrder: reordered,
      );
      onChanged();
    }

    return FTile(
      key: ValueKey('template-step-${step.id}'),
      title: Text(step.growthStage),
      subtitle: Text(
        '${l10n.scheduleDayAfterPlanting(step.daysAfterPlanting)}\n'
        '${step.product} · ${l10n.scheduleRate(step.ratePerHectare.formatKg())}',
      ),
      details: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (index > 0)
            GestureDetector(
              key: ValueKey('step-up-${step.id}'),
              onTap: () => move(-1),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(FIcons.chevronUp, size: 18),
              ),
            ),
          if (index < total - 1)
            GestureDetector(
              key: ValueKey('step-down-${step.id}'),
              onTap: () => move(1),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(FIcons.chevronDown, size: 18),
              ),
            ),
        ],
      ),
      onPress: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StepEditorScreen(
              templateId: templateId,
              existing: step,
            ),
          ),
        );
        onChanged();
      },
    );
  }
}

/// Add or edit one step. FR-024.
class StepEditorScreen extends ConsumerStatefulWidget {
  const StepEditorScreen({required this.templateId, this.existing, super.key});

  final String templateId;
  final TemplateStepRef? existing;

  @override
  ConsumerState<StepEditorScreen> createState() => _StepEditorState();
}

class _StepEditorState extends ConsumerState<StepEditorScreen> {
  late final TextEditingController _stage =
      TextEditingController(text: widget.existing?.growthStage ?? '');
  late final TextEditingController _days = TextEditingController(
    text: widget.existing?.daysAfterPlanting.toString() ?? '',
  );
  late final TextEditingController _product =
      TextEditingController(text: widget.existing?.product ?? '');
  late final TextEditingController _rate = TextEditingController(
    text: widget.existing == null
        ? ''
        : formatScaled(rescale(widget.existing!.ratePerHectare.value, 3, 1), 1),
  );
  final _error = FieldError();
  bool _saving = false;

  @override
  void dispose() {
    _stage.dispose();
    _days.dispose();
    _product.dispose();
    _rate.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error.clear();
      _saving = true;
    });

    if (_stage.text.trim().isEmpty || _product.text.trim().isEmpty) {
      setState(() {
        _saving = false;
        _error.set(l10n.errorRequired);
      });
      return;
    }
    final days = int.tryParse(_days.text.trim());
    if (days == null || days < 0) {
      setState(() {
        _saving = false;
        _error.set(l10n.errorNotANumber);
      });
      return;
    }

    try {
      final rate = Grams.parseKg(_rate.text);
      final repository = ref.read(templateRepositoryProvider);
      if (widget.existing?.id == null) {
        await repository.addStep(
          templateId: widget.templateId,
          daysAfterPlanting: days,
          growthStage: _stage.text,
          product: _product.text,
          ratePerHectare: rate,
        );
      } else {
        await repository.updateStep(
          templateId: widget.templateId,
          stepId: widget.existing!.id!,
          daysAfterPlanting: days,
          growthStage: _stage.text,
          product: _product.text,
          ratePerHectare: rate,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on DecimalFormatException {
      setState(() {
        _saving = false;
        _error.set(l10n.errorNotANumber);
      });
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirm(
      context: context,
      title: l10n.templateRemoveStep,
      body: l10n.templateRemoveConfirm(widget.existing!.growthStage),
      confirmLabel: l10n.actionDelete,
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(templateRepositoryProvider).removeStep(
          templateId: widget.templateId,
          stepId: widget.existing!.id!,
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existing?.id != null;

    return FScaffold(
      header: FHeader.nested(
        title: Text(isEdit ? l10n.templateEditStep : l10n.templateAddStep),
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
            key: const Key('step-stage'),
            controller: _stage,
            label: Text(l10n.templateStepStage),
            statesController: _error.states,
            error: _error.widget,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('step-days'),
            controller: _days,
            keyboardType: TextInputType.number,
            label: Text(l10n.templateStepDays),
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('step-product'),
            controller: _product,
            label: Text(l10n.templateStepProduct),
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('step-rate'),
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.templateStepRate),
          ),
          if (isEdit) ...[
            const SizedBox(height: 24),
            FButton(
              key: const Key('remove-step-button'),
              style: FButtonStyle.destructive(),
              onPress: _saving ? null : _remove,
              child: ButtonLabel(l10n.templateRemoveStep),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
