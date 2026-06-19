import 'package:flutter/material.dart';

import '../../../../core/theme/dialog_button_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../utils/cardio_format.dart';

/// Tap-to-type dialogs shared by the active cardio card (`DurationStepper` /
/// `CardioEntryCard._editDistance`) and the routine builder's cardio target
/// slots. Both return the PARSED value (seconds / canonical meters) or null
/// on cancel / empty input — the caller decides whether to mutate a notifier
/// (active card) or local entry state (builder), so the dialog stays
/// dependency-free and reusable.
///
/// **Validate-before-close (Phase 38h).** On OK with a NON-EMPTY field that
/// fails to parse the dialog does NOT pop — it shows an inline `errorText`
/// and stays open. Previously an unparseable entry popped `null`, which the
/// caller's `if (x != null)` treats identically to Cancel — a silent no-op
/// that reads as a broken OK button. An EMPTY field on OK pops `null` (the
/// no-op / no-change behavior preserved from before — no caller has ever
/// distinguished empty from cancel, so there is no "clear to null" path to
/// break here).

/// Prompts for a duration (`mm:ss` or bare minutes) and returns the parsed
/// total seconds, or null if cancelled / left empty. [initialSeconds]
/// pre-fills the field in `mm:ss`.
Future<int?> showCardioDurationDialog(
  BuildContext context, {
  required int initialSeconds,
}) {
  final controller = TextEditingController(
    text: CardioFormat.duration(initialSeconds),
  );
  return showDialog<int>(
    context: context,
    builder: (dialogCtx) {
      final l10n = AppLocalizations.of(dialogCtx);
      return _CardioInputDialog<int>(
        title: l10n.enterDuration,
        controller: controller,
        // Plain datetime keyboard exposes the `:` key on both platforms;
        // bare minutes also parse (e.g. `28` → 28:00).
        keyboardType: TextInputType.datetime,
        hintText: l10n.enterDurationHint,
        helperText: l10n.enterDurationHelper,
        errorText: l10n.enterDurationError,
        cancelLabel: l10n.cancel,
        okLabel: l10n.ok,
        parse: CardioFormat.parseDuration,
      );
    },
  );
}

/// Prompts for a distance in [distanceUnit] (`km` / `mi`, profile-derived)
/// and returns the parsed canonical METERS, or null if cancelled / left
/// empty. [initialMeters] pre-fills the field in the display unit.
Future<double?> showCardioDistanceDialog(
  BuildContext context, {
  required double? initialMeters,
  required String distanceUnit,
  required String locale,
}) {
  final controller = TextEditingController(
    text: initialMeters != null
        ? CardioFormat.distanceValue(
            initialMeters,
            distanceUnit: distanceUnit,
            locale: locale,
          )
        : '',
  );
  return showDialog<double>(
    context: context,
    builder: (dialogCtx) {
      final l10n = AppLocalizations.of(dialogCtx);
      return _CardioInputDialog<double>(
        title: l10n.enterDistance,
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        suffixText: distanceUnit,
        helperText: l10n.enterDistanceHelper,
        errorText: l10n.enterDistanceError,
        cancelLabel: l10n.cancel,
        okLabel: l10n.ok,
        parse: (text) => CardioFormat.parseDistanceToMeters(text, distanceUnit),
      );
    },
  );
}

/// Stateful tap-to-type dialog backing both cardio target dialogs. Holds the
/// `_error` flag so a failed parse can flip the field into its error state
/// (red border + [errorText]) WITHOUT popping — the validate-before-close fix
/// (Phase 38h). [parse] returns the canonical value or null on unparseable
/// input; an empty field is treated as a cancel-equivalent no-op (pop null).
class _CardioInputDialog<T> extends StatefulWidget {
  const _CardioInputDialog({
    required this.title,
    required this.controller,
    required this.keyboardType,
    required this.helperText,
    required this.errorText,
    required this.cancelLabel,
    required this.okLabel,
    required this.parse,
    this.hintText,
    this.suffixText,
  });

  final String title;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final String helperText;
  final String errorText;
  final String cancelLabel;
  final String okLabel;
  final T? Function(String) parse;
  final String? hintText;
  final String? suffixText;

  @override
  State<_CardioInputDialog<T>> createState() => _CardioInputDialogState<T>();
}

class _CardioInputDialogState<T> extends State<_CardioInputDialog<T>> {
  bool _showError = false;

  void _submit(String text) {
    final trimmed = text.trim();
    // Empty → no-op / cancel-equivalent (preserves pre-38h behavior: no
    // caller distinguishes empty from cancel, so there's no clear path).
    if (trimmed.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final parsed = widget.parse(text);
    if (parsed == null) {
      // Non-empty but unparseable: block the close, surface the error.
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hintText,
          suffixText: widget.suffixText,
          // Always-visible helper: the pre-filled value masks `hintText`, so
          // the format guidance has to live in the persistent helper slot.
          helperText: widget.helperText,
          // On a failed parse the helper is replaced by the error copy and
          // the field flips to its error border.
          errorText: _showError ? widget.errorText : null,
        ),
        // Clear the error as soon as the user edits — give them a clean slate
        // to retry instead of a sticky red field.
        onChanged: (_) {
          if (_showError) setState(() => _showError = false);
        },
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: dialogTextButtonStyle,
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          onPressed: () => _submit(widget.controller.text),
          style: dialogTextButtonStyle,
          child: Text(widget.okLabel),
        ),
      ],
    );
  }
}
