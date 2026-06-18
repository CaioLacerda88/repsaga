import 'package:flutter/material.dart';

import '../../../../core/theme/dialog_button_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../utils/cardio_format.dart';

/// Tap-to-type dialogs shared by the active cardio card (`DurationStepper` /
/// `CardioEntryCard._editDistance`) and the routine builder's cardio target
/// slots. Both return the PARSED value (seconds / canonical meters) or null
/// on cancel / unparseable input — the caller decides whether to mutate a
/// notifier (active card) or local entry state (builder), so the dialog stays
/// dependency-free and reusable.

/// Prompts for a duration (`mm:ss` or bare minutes) and returns the parsed
/// total seconds, or null if cancelled / unparseable. [initialSeconds]
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
      void submit(String text) {
        Navigator.of(dialogCtx).pop(CardioFormat.parseDuration(text));
      }

      return AlertDialog(
        title: Text(l10n.enterDuration),
        content: TextField(
          controller: controller,
          // Plain datetime keyboard exposes the `:` key on both platforms;
          // bare minutes also parse (e.g. `28` → 28:00).
          keyboardType: TextInputType.datetime,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.enterDurationHint),
          onSubmitted: submit,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            style: dialogTextButtonStyle,
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => submit(controller.text),
            style: dialogTextButtonStyle,
            child: Text(l10n.ok),
          ),
        ],
      );
    },
  );
}

/// Prompts for a distance in [distanceUnit] (`km` / `mi`, profile-derived)
/// and returns the parsed canonical METERS, or null if cancelled /
/// unparseable. [initialMeters] pre-fills the field in the display unit.
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
      void submit(String text) {
        Navigator.of(
          dialogCtx,
        ).pop(CardioFormat.parseDistanceToMeters(text, distanceUnit));
      }

      return AlertDialog(
        title: Text(l10n.enterDistance),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(suffixText: distanceUnit),
          onSubmitted: submit,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            style: dialogTextButtonStyle,
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => submit(controller.text),
            style: dialogTextButtonStyle,
            child: Text(l10n.ok),
          ),
        ],
      );
    },
  );
}
