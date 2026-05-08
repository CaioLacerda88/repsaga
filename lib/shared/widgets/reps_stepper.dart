import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dialog_button_style.dart';
import '../../l10n/app_localizations.dart';

/// A reusable stepper widget for rep counts.
///
/// Supports tap and long-press with progressive acceleration on the +/- buttons.
/// Initial hold delay of 400ms, then repeats at 150ms intervals.
/// Displays integer values only.
class RepsStepper extends StatefulWidget {
  const RepsStepper({
    required this.value,
    required this.onChanged,
    this.increment = 1,
    this.valueColor,
    this.valueFontWeight,
    super.key,
  });

  final int value;
  final int increment;
  final ValueChanged<int> onChanged;

  /// Optional override for the value-text color (Phase 20 commit 4).
  ///
  /// When `null` (the default), the value renders in
  /// `theme.colorScheme.onSurface` — the standard cream text. SetRow uses
  /// this hook to render the gold reps value on standing-PR / predicted-PR
  /// rows whose accent set includes [RecordType.maxReps] or
  /// [RecordType.maxVolume].
  final Color? valueColor;

  /// Optional override for the value-text font weight (Phase 20 commit 4).
  ///
  /// Defaults to [FontWeight.w700]. Mirrors [WeightStepper]'s param for
  /// symmetry — present for callers that want to bump the weight to w800
  /// on PR rows in line with the design's Rajdhani-800 spec.
  final FontWeight? valueFontWeight;

  @override
  State<RepsStepper> createState() => _RepsStepperState();
}

class _RepsStepperState extends State<RepsStepper> {
  Timer? _timer;

  void _decrement() {
    final next = widget.value - widget.increment;
    if (next >= 0) widget.onChanged(next);
  }

  void _increment() {
    widget.onChanged(widget.value + widget.increment);
  }

  void _startRepeating(VoidCallback action) {
    action();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () {
      _timer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => action(),
      );
    });
  }

  void _stopRepeating() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showNumberInput() {
    final controller = TextEditingController(text: widget.value.toString());
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final l10n = AppLocalizations.of(dialogCtx);
        return AlertDialog(
          title: Text(l10n.enterReps),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            onSubmitted: (text) {
              final parsed = int.tryParse(text);
              if (parsed != null && parsed >= 0) {
                widget.onChanged(parsed);
              }
              Navigator.of(dialogCtx).pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              style: dialogTextButtonStyle,
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text);
                if (parsed != null && parsed >= 0) {
                  widget.onChanged(parsed);
                }
                Navigator.of(dialogCtx).pop();
              },
              style: dialogTextButtonStyle,
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Phase 20 commit 2 (BUG-019 mirror): structural twin of [WeightStepper]
    // post-commit-1.  Fixed-width 40x48 +/- buttons via
    // `BoxConstraints.tightFor`, flex-filled center value zone via
    // `Expanded`, no `MainAxisSize.min` on the outer Row so this stepper
    // composes safely inside a flex-2 column on a 360dp viewport. The old
    // (`MainAxisSize.min` + `Flexible`) shape grew the inner Row to its
    // children's natural width and overflowed the parent column when paired
    // with the new Direction B SetRow chrome.
    return Row(
      children: [
        GestureDetector(
          onLongPressStart: (_) => _startRepeating(_decrement),
          onLongPressEnd: (_) => _stopRepeating(),
          onLongPressCancel: _stopRepeating,
          child: IconButton(
            onPressed: widget.value >= widget.increment ? _decrement : null,
            icon: const Icon(Icons.remove, size: 18),
            // BUG-019: pinned to 40x48 — Material's 48dp vertical tap min
            // plus a 40dp horizontal cap so the value zone owns the slack.
            constraints: const BoxConstraints.tightFor(width: 40, height: 48),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Expanded(
          child: Semantics(
            label: 'Reps value: ${widget.value}. Tap to enter reps.',
            button: true,
            child: GestureDetector(
              onTap: _showNumberInput,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 48,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.value.toString(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: widget.valueFontWeight ?? FontWeight.w700,
                        color: widget.valueColor ?? theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          onLongPressStart: (_) => _startRepeating(_increment),
          onLongPressEnd: (_) => _stopRepeating(),
          onLongPressCancel: _stopRepeating,
          child: IconButton(
            onPressed: _increment,
            icon: const Icon(Icons.add, size: 18),
            // BUG-019: pinned to 40x48 — Material's 48dp vertical tap min
            // plus a 40dp horizontal cap so the value zone owns the slack.
            constraints: const BoxConstraints.tightFor(width: 40, height: 48),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
