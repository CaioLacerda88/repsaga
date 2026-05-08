import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format/number_format.dart';
import '../../core/theme/dialog_button_style.dart';
import '../../l10n/app_localizations.dart';

/// A reusable stepper widget for weight values.
///
/// Supports tap and long-press with progressive acceleration on the +/- buttons.
/// Initial hold delay of 400ms, then repeats at 150ms intervals.
/// Displays one decimal place when the value is fractional, integer otherwise.
class WeightStepper extends StatefulWidget {
  const WeightStepper({
    required this.value,
    required this.onChanged,
    this.increment = 2.5,
    this.unit = 'kg',
    this.valueColor,
    this.valueFontWeight,
    this.valueShadow,
    super.key,
  });

  final double value;
  final double increment;
  final ValueChanged<double> onChanged;

  /// The weight unit label displayed in the input dialog and semantics.
  final String unit;

  /// Optional override for the value-text color (Phase 20 commit 4).
  ///
  /// When `null` (the default), the value renders in
  /// `theme.colorScheme.primary` with a 30% primary halo — the standard
  /// daily-violet treatment. When provided, the value renders in this color
  /// instead AND the violet halo is suppressed (passing a fresh shadow via
  /// [valueShadow] is the caller's call). The active-workout SetRow uses
  /// this hook to render the gold value(s) on standing-PR / predicted-PR
  /// rows without creating a one-off stepper subclass.
  final Color? valueColor;

  /// Optional override for the value-text font weight (Phase 20 commit 4).
  ///
  /// Defaults to [FontWeight.w800]. The set-row PR treatment uses this to
  /// keep the value at w800 (Rajdhani's bundled bold) while the dim/normal
  /// states use a lighter weight in the future. Currently every state ships
  /// w800; the param exists for symmetry with [valueColor].
  final FontWeight? valueFontWeight;

  /// Optional override for the value-text shadow (Phase 20 commit 4).
  ///
  /// Defaults to a 30% primary-violet halo. PR rows pass `null` to suppress
  /// the violet halo on a gold value (a violet halo behind a gold number
  /// reads muddy on the Arcane-Ascent palette).
  final Shadow? valueShadow;

  @override
  State<WeightStepper> createState() => _WeightStepperState();
}

class _WeightStepperState extends State<WeightStepper> {
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

  String _formatWeight(double value, String locale) {
    return AppNumberFormat.weight(value, locale: locale);
  }

  /// Parses a user-entered weight accepting either `.` or `,` as the decimal
  /// separator so pt-BR users can type `80,5` naturally on the numeric keyboard.
  double? _parseWeight(String text) {
    final normalised = text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalised);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showNumberInput() {
    final locale = Localizations.localeOf(context).languageCode;
    final controller = TextEditingController(
      text: _formatWeight(widget.value, locale),
    );
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final l10n = AppLocalizations.of(dialogCtx);
        return AlertDialog(
          title: Text(l10n.enterWeight),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(suffixText: widget.unit),
            onSubmitted: (text) {
              final parsed = _parseWeight(text);
              if (parsed != null) {
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
                final parsed = _parseWeight(controller.text);
                if (parsed != null) {
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
    final locale = Localizations.localeOf(context).languageCode;
    final formatted = _formatWeight(widget.value, locale);

    // Phase 20 commit 1 (BUG-019): mirror the locked Direction B mockup CSS:
    //   .step-btn       { width: 40px; flex-shrink: 0; }
    //   .step-value-zone { flex: 1; }
    // Fixed-width +/- buttons + flex-filled center value zone makes the
    // stepper occupy its parent's full horizontal width, so the value tap
    // surface scales with the row column instead of the old 32dp pill that
    // missed sweaty-thumb hits on 360dp Brazilian-mid-market screens.
    return Row(
      children: [
        GestureDetector(
          onLongPressStart: (_) => _startRepeating(_decrement),
          onLongPressEnd: (_) => _stopRepeating(),
          onLongPressCancel: _stopRepeating,
          child: IconButton(
            onPressed: widget.value >= widget.increment ? _decrement : null,
            icon: const Icon(Icons.remove, size: 18),
            // BUG-019: pinned to 40x48 — Material's 48dp vertical tap min plus
            // a 40dp horizontal cap so the value zone owns the slack. The
            // BUG-019 widget test asserts both floors on a 360dp viewport.
            constraints: const BoxConstraints.tightFor(width: 40, height: 48),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Expanded(
          child: Semantics(
            label:
                'Weight value: $formatted ${widget.unit}. Tap to enter weight.',
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
                      formatted,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 26,
                        fontWeight: widget.valueFontWeight ?? FontWeight.w800,
                        color: widget.valueColor ?? theme.colorScheme.primary,
                        // Halo only on the default (violet) state. PR rows
                        // pass an explicit `valueColor` and want a clean
                        // value — the gold reads cleanly without a halo on
                        // top of the gold tint background.
                        shadows: widget.valueColor != null
                            ? (widget.valueShadow != null
                                  ? [widget.valueShadow!]
                                  : null)
                            : [
                                Shadow(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 8,
                                ),
                              ],
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
            // BUG-019: pinned to 40x48 — Material's 48dp vertical tap min plus
            // a 40dp horizontal cap so the value zone owns the slack. The
            // BUG-019 widget test asserts both floors on a 360dp viewport.
            constraints: const BoxConstraints.tightFor(width: 40, height: 48),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
