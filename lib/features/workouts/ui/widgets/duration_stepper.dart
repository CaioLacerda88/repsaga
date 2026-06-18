import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../utils/cardio_format.dart';
import 'cardio_target_dialogs.dart';

/// The duration hero of the cardio logging card (Phase 38b).
///
/// Mirrors [WeightStepper]'s interaction contract — fixed 40×48 ± buttons
/// with long-press acceleration (400ms initial hold, 150ms repeat), a
/// flex-filled center value zone, and a tap-to-type dialog — but formats
/// the value as `mm:ss` and steps in 30-second increments. The value renders
/// in [AppColors.bodyPartCardio] at the hero register (~40sp Rajdhani 700
/// tabular) per the locked `docs/phase-38-mockups.html`.
class DurationStepper extends StatefulWidget {
  const DurationStepper({
    required this.value,
    required this.onChanged,
    this.increment = 30,
    super.key,
  });

  /// Current duration in seconds.
  final int value;

  /// Step applied by the ± buttons, in seconds.
  final int increment;

  final ValueChanged<int> onChanged;

  @override
  State<DurationStepper> createState() => _DurationStepperState();
}

class _DurationStepperState extends State<DurationStepper> {
  Timer? _timer;

  void _decrement() {
    // Floor at one increment (30s), never 0. This makes
    // `CardioSession.durationSeconds` "always > 0 by UI construction" a
    // literal invariant — there is no reachable 0:00 + disabled-CTA state.
    // The DB CHECK (`duration_seconds > 0`) stays as the hard backstop.
    final next = widget.value - widget.increment;
    if (next >= widget.increment) widget.onChanged(next);
  }

  void _increment() {
    widget.onChanged(widget.value + widget.increment);
  }

  // Same hold-to-repeat ramp as WeightStepper: fire once on press, wait
  // 400ms, then repeat every 150ms until release/cancel.
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

  Future<void> _showNumberInput() async {
    final parsed = await showCardioDurationDialog(
      context,
      initialSeconds: widget.value,
    );
    if (parsed != null) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatted = CardioFormat.duration(widget.value);

    // Geometry mirrors WeightStepper (BUG-019 lineage): fixed-width 40×48
    // ± buttons + flex-filled center value zone so the tap surface scales
    // with the card width on 360dp mid-market screens. The ± buttons are
    // wrapped in explicit `Semantics(button:)` + GestureDetector for the
    // long-press repeat — same a11y/gesture-arena rationale as
    // `weight_stepper.dart` (a Tooltip would inject a competing
    // GestureDetector).
    return Row(
      children: [
        Semantics(
          button: true,
          label: l10n.decrementDuration,
          child: GestureDetector(
            onLongPressStart: (_) => _startRepeating(_decrement),
            onLongPressEnd: (_) => _stopRepeating(),
            onLongPressCancel: _stopRepeating,
            // NO `visualDensity: compact` (deliberate delta from
            // WeightStepper): IconButton subtracts the density offset from
            // its effective constraints, so compact shrinks the RENDERED
            // hit-box to 40×40 — below the 48dp floor the spec pins. The
            // tightFor(40, 48) constraint alone renders the true 40×48
            // target (cluster/feedback: tap-target-measurement — measure
            // rendered size, not declared minimums).
            child: IconButton(
              // Disabled at the 30s floor — decrement can't go lower, so the
              // button reflects that it's a no-op (mirrors the value floor in
              // `_decrement`).
              onPressed: widget.value > widget.increment ? _decrement : null,
              icon: const Icon(Icons.remove, size: 18),
              color: AppColors.bodyPartCardio,
              constraints: const BoxConstraints.tightFor(width: 40, height: 48),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            label: l10n.durationValueSemantics(formatted),
            button: true,
            child: GestureDetector(
              onTap: _showNumberInput,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatted,
                      textAlign: TextAlign.center,
                      // Duration hero — the only mandatory cardio input, so
                      // it carries the numeral register at hero size in the
                      // cardio identity hue (locked mockup: ~40sp teal,
                      // tabular figures via AppTextStyles.numeric).
                      style: AppTextStyles.numeric.copyWith(
                        fontSize: 40,
                        color: AppColors.bodyPartCardio,
                      ),
                    ),
                  ),
                  Text(
                    l10n.cardioDurationMinLabel,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: l10n.incrementDuration,
          child: GestureDetector(
            onLongPressStart: (_) => _startRepeating(_increment),
            onLongPressEnd: (_) => _stopRepeating(),
            onLongPressCancel: _stopRepeating,
            // See the minus button above for why there is no
            // `visualDensity: compact` here.
            child: IconButton(
              onPressed: _increment,
              icon: const Icon(Icons.add, size: 18),
              color: AppColors.bodyPartCardio,
              constraints: const BoxConstraints.tightFor(width: 40, height: 48),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }
}
