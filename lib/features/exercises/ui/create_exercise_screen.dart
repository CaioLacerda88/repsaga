import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../core/offline/pending_action.dart';
import '../../../core/offline/pending_sync_provider.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/enum_l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../auth/providers/auth_providers.dart';
import '../models/exercise.dart';
import '../providers/exercise_providers.dart'
    show exerciseListProvider, exerciseRepositoryProvider;

class CreateExerciseScreen extends ConsumerStatefulWidget {
  const CreateExerciseScreen({super.key});

  @override
  ConsumerState<CreateExerciseScreen> createState() =>
      _CreateExerciseScreenState();
}

class _CreateExerciseScreenState extends ConsumerState<CreateExerciseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formTipsController = TextEditingController();
  MuscleGroup? _selectedMuscleGroup;
  EquipmentType? _selectedEquipmentType;
  bool _isLoading = false;
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _formTipsController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (_nameError != null) return _nameError;
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l10n.nameRequired;
    if (value.trim().length < 2) return l10n.nameTooShort;
    return null;
  }

  Future<void> _submit() async {
    setState(() => _nameError = null);

    // Always validate the form fields to show inline errors.
    final isFormValid = _formKey.currentState?.validate() ?? false;

    final l10n = AppLocalizations.of(context);
    if (_selectedMuscleGroup == null || _selectedEquipmentType == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.selectMuscleAndEquipment)));
      return;
    }

    if (!isFormValid) return;

    setState(() => _isLoading = true);

    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.sessionExpired)));
          context.go('/login');
        }
        return;
      }
      final description = _descriptionController.text.trim();
      final formTips = _formTipsController.text.trim();
      final locale = ref.read(localeProvider).languageCode;
      final name = _nameController.text.trim();
      try {
        await ref
            .read(exerciseRepositoryProvider)
            .createExercise(
              locale: locale,
              name: name,
              muscleGroup: _selectedMuscleGroup!,
              equipmentType: _selectedEquipmentType!,
              userId: userId,
              description: description.isEmpty ? null : description,
              formTips: formTips.isEmpty ? null : formTips,
            );
      } on NetworkException {
        // BUG-003: offline create. Generate a local UUID, enqueue the
        // creation for replay, and warn the user that this exercise is
        // local-only until they reconnect. The active-workout flow scans
        // the queue at finishWorkout time and tags any `PendingSaveWorkout`
        // that references an offline-created exercise with the
        // PendingCreateExercise action's id in `dependsOn`, so replay
        // ordering keeps the FK satisfied.
        final actionId = const Uuid().v4();
        final exerciseId = const Uuid().v4();
        await ref
            .read(pendingSyncProvider.notifier)
            .enqueue(
              PendingAction.createExercise(
                id: actionId,
                exerciseId: exerciseId,
                userId: userId,
                locale: locale,
                name: name,
                muscleGroup: _selectedMuscleGroup!.name,
                equipmentType: _selectedEquipmentType!.name,
                description: description.isEmpty ? null : description,
                formTips: formTips.isEmpty ? null : formTips,
                queuedAt: DateTime.now().toUtc(),
              ),
            );
        if (mounted) {
          _invalidateExerciseList();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.exerciseCreatedOffline)));
          context.pop();
        }
        return;
      }

      // Invalidate the exercise list to trigger a refresh.
      _invalidateExerciseList();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.exerciseCreated)));
        context.pop();
      }
    } on ValidationException catch (e) {
      setState(() => _nameError = e.userMessage);
      _formKey.currentState?.validate();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _invalidateExerciseList() {
    ref.invalidate(exerciseListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createExercise),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: l10n.exerciseName,
                  controller: _nameController,
                  validator: _validateName,
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.fitness_center,
                  maxLength: 80,
                  semanticsIdentifier: 'create-exercise-name',
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text(l10n.muscleGroup, style: AppTextStyles.title),
                const SizedBox(height: 12),
                _SelectableGrid<MuscleGroup>(
                  values: MuscleGroup.values,
                  selected: _selectedMuscleGroup,
                  onSelected: (v) => setState(() => _selectedMuscleGroup = v),
                  labelFor: (v) => v.localizedName(l10n),
                  iconFor: (v) => v.svgIcon,
                  semanticPrefix: l10n.muscleGroupSemanticsPrefix,
                ),
                const SizedBox(height: 24),
                Text(l10n.equipmentType, style: AppTextStyles.title),
                const SizedBox(height: 12),
                _SelectableGrid<EquipmentType>(
                  values: EquipmentType.values,
                  selected: _selectedEquipmentType,
                  onSelected: (v) => setState(() => _selectedEquipmentType = v),
                  labelFor: (v) => v.localizedName(l10n),
                  iconFor: (v) => v.svgIcon,
                  semanticPrefix: l10n.equipmentTypeSemanticsPrefix,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _descriptionController,
                  maxLength: 300,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.description,
                    hintText: l10n.descriptionHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _formTipsController,
                  maxLength: 500,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.formTips,
                    hintText: l10n.formTipsHint,
                    helperText: l10n.formTipsHelper,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                GradientButton(
                  label: l10n.createExerciseButton,
                  onPressed: _isLoading ? null : _submit,
                  isLoading: _isLoading,
                  semanticsIdentifier: 'create-exercise-save',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectableGrid<T> extends StatelessWidget {
  const _SelectableGrid({
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.labelFor,
    required this.iconFor,
    required this.semanticPrefix,
  });

  final List<T> values;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelFor;
  final String Function(T) iconFor;
  final String semanticPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((value) {
        final isSelected = selected == value;
        return _SelectableCard(
          label: labelFor(value),
          icon: iconFor(value),
          isSelected: isSelected,
          onTap: () => onSelected(value),
          semanticLabel: '$semanticPrefix: ${labelFor(value)}',
        );
      }).toList(),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.semanticLabel,
  });

  final String label;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Semantics(
      label: semanticLabel,
      selected: isSelected,
      child: Material(
        color: isSelected
            ? primary.withValues(alpha: 0.15)
            : theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64, minWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcons.render(
                  icon,
                  size: 24,
                  color: isSelected ? primary : theme.colorScheme.onSurface,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 12,
                    color: isSelected ? primary : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
