import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Modal editor for a workout's free-text notes (Q1 notes-edit-after).
///
/// Opened from the History detail screen's notes section — the calm,
/// full-context surface where reflective text belongs (rather than the
/// finish gate, which is the RPG celebration beat). Prefills with any
/// existing note, enforces a 2000-character cap, and returns the edited
/// text on Save or `null` on Cancel / dismiss.
///
/// **Decoupling Rule 2 — localized strings injected as props.** The sheet
/// renders strings supplied by the caller, keeping it unit-testable without
/// an l10n harness (see auto-memory `widget_l10n_parameterization`).
///
/// The returned value distinguishes Save from Cancel via a wrapper: `null`
/// means dismissed/cancelled (no change); a [NotesEditResult] means the user
/// committed an edit (its `notes` may be empty → caller clears the note).
class NotesEditSheet extends StatefulWidget {
  const NotesEditSheet({
    super.key,
    required this.initialNotes,
    required this.title,
    required this.hintText,
    required this.saveLabel,
    required this.cancelLabel,
    required this.counterFormatter,
    this.maxLength = 2000,
    this.counterThreshold = 1800,
  });

  /// Existing note text to prefill (empty/null → empty field).
  final String? initialNotes;

  /// Eyebrow title shown at the top of the sheet (e.g. localized "Notes").
  final String title;

  /// Placeholder shown when the field is empty.
  final String hintText;

  final String saveLabel;
  final String cancelLabel;

  /// Formats the near-cap counter label, e.g. `"1853 / 2000"`. Takes the
  /// current length + the max so the localized string is supplied by the
  /// caller (keeps the widget l10n-harness-free per Decoupling Rule 2).
  final String Function(int current, int max) counterFormatter;

  /// Hard character cap. Defaults to the 2000-char column budget.
  final int maxLength;

  /// The counter stays hidden until the current length reaches this value
  /// (default 1800 → shown only when ≤ 200 chars remain of a 2000 cap). The
  /// always-on `N/M` counter reads as a nag; surfacing it only near the cap
  /// keeps the field calm.
  final int counterThreshold;

  /// Open the sheet and return the user's edit, or `null` if cancelled.
  static Future<NotesEditResult?> show(
    BuildContext context, {
    required String? initialNotes,
    required String title,
    required String hintText,
    required String saveLabel,
    required String cancelLabel,
    required String Function(int current, int max) counterFormatter,
    int maxLength = 2000,
    int counterThreshold = 1800,
  }) {
    return showModalBottomSheet<NotesEditResult>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => NotesEditSheet(
        initialNotes: initialNotes,
        title: title,
        hintText: hintText,
        saveLabel: saveLabel,
        cancelLabel: cancelLabel,
        counterFormatter: counterFormatter,
        maxLength: maxLength,
        counterThreshold: counterThreshold,
      ),
    );
  }

  @override
  State<NotesEditSheet> createState() => _NotesEditSheetState();
}

class _NotesEditSheetState extends State<NotesEditSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lift the sheet above the keyboard so the multiline field + actions
    // stay visible while typing.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'workout-notes-edit-sheet',
      child: SafeArea(
        top: false,
        // The bottomInset Padding lifts the whole sheet above the keyboard.
        // The Column(min) makes the sheet SHRINK-WRAP its content (eyebrow +
        // field + buttons) so it sits DIRECTLY above the keyboard — no
        // full-height sheet, no dead gap. A bare SingleChildScrollView here is
        // GREEDY in its scroll axis: inside the isScrollControlled sheet it
        // gets maxHeight == full screen and fills it (RenderBox.constrain
        // clamps to maxHeight), pinning content to the top with the keyboard
        // inset painted as empty space below. The field's own maxLines cap
        // (capped at 5) gives it an internal scrollbar for long notes, so we
        // never need an outer scroll view that fights the shrink-wrap.
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title.toUpperCase(),
                style: AppTextStyles.label.copyWith(color: AppColors.textDim),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: widget.maxLength,
                // Capped so eyebrow + field + buttons fit above the keyboard on
                // the smallest real Android phone (~534dp tall, keyboard
                // ~260dp → ~250dp budget). Long notes scroll INSIDE the field.
                maxLines: 5,
                minLines: 3,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: AppTextStyles.body.copyWith(color: AppColors.textCream),
                // Custom counter: nothing until the user nears the cap, then
                // a colored remaining-budget readout. Material calls this on
                // every change, so it tracks `currentLength` without a manual
                // setState. Returning `null` (not an empty Text) collapses the
                // counter row entirely so the field doesn't reserve the gap.
                buildCounter:
                    (
                      context, {
                      required int currentLength,
                      required int? maxLength,
                      required bool isFocused,
                    }) {
                      if (currentLength < widget.counterThreshold) {
                        return null;
                      }
                      final cap = maxLength ?? widget.maxLength;
                      final remaining = cap - currentLength;
                      final color = remaining <= 0
                          ? AppColors.error
                          : remaining <= 50
                          ? AppColors.warning
                          : AppColors.textDim;
                      return Text(
                        widget.counterFormatter(currentLength, cap),
                        style: AppTextStyles.label.copyWith(color: color),
                      );
                    },
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: AppTextStyles.body.copyWith(
                    color: AppColors.textDim,
                  ),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Semantics(
                    container: true,
                    identifier: 'workout-notes-cancel',
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textDim,
                        minimumSize: const Size(80, 48),
                      ),
                      child: Text(widget.cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    container: true,
                    identifier: 'workout-notes-save',
                    label: widget.saveLabel,
                    child: FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(NotesEditResult(_controller.text)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryViolet,
                        foregroundColor: AppColors.textCream,
                        minimumSize: const Size(80, 48),
                      ),
                      child: Text(widget.saveLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Result of a [NotesEditSheet] Save. A `null` return from `show` means the
/// sheet was cancelled / dismissed (no change); a non-null result means the
/// user committed [notes] (which may be empty → the caller clears the note).
class NotesEditResult {
  const NotesEditResult(this.notes);

  final String notes;
}
