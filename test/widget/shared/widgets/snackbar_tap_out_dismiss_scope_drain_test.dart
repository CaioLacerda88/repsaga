/// Regression guard for the 2026-05-14 "drain bar is invisible" bug.
///
/// **The bug** (commit `4c8ddcf` reported on Samsung S25 Ultra release
/// APK): the countdown progress bar appeared, sat at full width for the
/// snack's full 3.5 s duration, then disappeared with the snack — never
/// visibly drained. The track was visible (3 dp dim-violet stripe full
/// snack width) but the *filler* (the brighter draining stripe) was
/// invisible.
///
/// **Root cause:** the previous implementation wrapped the filler
/// `ColoredBox` in `Align(widthFactor: X)`. `Align` passes LOOSE
/// constraints to its child; a `ColoredBox` with no child collapses to
/// 0×0 under loose constraints. The filler was always 0×0 — the
/// `widthFactor` shrink had nothing to shrink. The user saw only the
/// unchanging track.
///
/// **The earlier layout tests didn't catch it** because they measured
/// the *track* (`SnackBarCountdown.trackKey`), not the filler. The fix
/// adds [SnackBarCountdown.fillerKey] on the inner draining widget and
/// this test measures THAT at two time slices: at t=0 the filler width
/// equals the track width (bar starts full), at t=duration/2 the filler
/// width is ~half the track width (bar half-drained).
///
/// `TweenAnimationBuilder<double>` with `curve: Curves.linear` is the
/// new driver — `tester.pump(Duration)` advances the synthetic clock
/// the same way it advanced the previous `AnimationController`, so we
/// can pump 1750 ms of a 3500 ms drain and assert the filler is at
/// ~50% width. 5% tolerance covers subpixel layout rounding.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/shared/widgets/snackbar_tap_out_dismiss_scope.dart';

const _duration = Duration(milliseconds: 3500);

/// Wall-clock elapsed since `_SnackBarCountdown.build` first ran. The
/// `TweenAnimationBuilder` starts animating the moment the widget
/// mounts, so this is the canonical "elapsed drain time" we use to
/// predict expected filler width: width ≈ track × (1 - elapsed/duration).
///
/// The pre-show pumps cover the ScaffoldMessenger's entrance animation
/// (~250 ms) AND the build/layout of the snack widget itself. That
/// elapsed time counts AGAINST the drain duration, so the test
/// computes expected widths relative to total pumped-since-show, not
/// the conceptual "t=0 of the drain".
Duration _elapsedSinceShow = Duration.zero;

Future<void> _pumpScopeAndShow(WidgetTester tester) async {
  _elapsedSinceShow = Duration.zero;
  await tester.pumpWidget(
    MaterialApp(
      home: ScaffoldMessenger(
        child: SnackBarTapOutDismissScope(
          child: Scaffold(
            body: Center(
              child: Builder(
                builder: (innerContext) {
                  return ElevatedButton(
                    onPressed: () {
                      SnackBarTapOutDismissScope.of(
                        innerContext,
                      ).showCountdownSnackBar(
                        context: innerContext,
                        message: 'Set 1 deleted',
                        duration: _duration,
                        action: SnackBarAction(label: 'UNDO', onPressed: () {}),
                      );
                    },
                    child: const Text('Show snack'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Show snack'));
  // Drive the entrance animation to completion (~250 ms). These pumps
  // also tick the drain — the test tracks elapsed time explicitly so
  // expected filler widths are computed against actual elapsed, not
  // against the conceptual t=0.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  _elapsedSinceShow = const Duration(milliseconds: 300);
}

/// Advance the synthetic clock by [step] and update [_elapsedSinceShow].
/// Pumps in 100 ms slices so the `TweenAnimationBuilder` ticks at each
/// step (otherwise a single large pump collapses intermediate frames).
Future<void> _pumpDrain(WidgetTester tester, Duration step) async {
  const slice = Duration(milliseconds: 100);
  final iterations = step.inMilliseconds ~/ slice.inMilliseconds;
  for (int i = 0; i < iterations; i++) {
    await tester.pump(slice);
  }
  _elapsedSinceShow += step;
}

/// Predicted filler width at the current elapsed time, given a linear
/// curve from `widthFactor 1.0` → `0.0` over `_duration`.
double _expectedFillerWidth(double trackWidth) {
  final fraction =
      1.0 - (_elapsedSinceShow.inMilliseconds / _duration.inMilliseconds);
  return trackWidth * fraction.clamp(0.0, 1.0);
}

void main() {
  group('SnackBarCountdown drain regression — filler width over time', () {
    testWidgets('should render the filler with NON-ZERO width near the start '
        '(bar is actually visible — pins the 2026-05-14 zero-width bug)', (
      tester,
    ) async {
      // The load-bearing assertion of this whole file: the filler is
      // not collapsed to 0×0. We use a generous tolerance because the
      // exact width depends on how much elapsed time has passed
      // between the show tap and the measurement (entrance animation
      // takes ~250 ms, all of which counts against the drain).
      await _pumpScopeAndShow(tester);

      final trackSize = tester.getSize(find.byKey(SnackBarCountdown.trackKey));
      final fillerSize = tester.getSize(
        find.byKey(SnackBarCountdown.fillerKey),
      );

      final expectedWidth = _expectedFillerWidth(trackSize.width);
      // 3% of track width — wide enough to accept TweenAnimationBuilder's
      // internal status-fence rounding plus the FractionallySizedBox
      // → ColoredBox layout math. Tight enough to catch a stuck-full
      // or zero-width regression.
      final tolerance = trackSize.width * 0.03;

      expect(
        fillerSize.width,
        closeTo(expectedWidth, tolerance),
        reason:
            'At elapsedSinceShow=${_elapsedSinceShow.inMilliseconds} ms '
            'of ${_duration.inMilliseconds} ms, the linear-curve '
            'TweenAnimationBuilder should size the filler to '
            '${expectedWidth.toStringAsFixed(2)} dp (±$tolerance). '
            'Actual: ${fillerSize.width}. If actual is 0 the filler '
            'has collapsed under loose constraints — that is the '
            '2026-05-14 bug we are guarding against. Track width: '
            '${trackSize.width}.',
      );
      // Filler is the 3 dp track row tall.
      expect(fillerSize.height, closeTo(3.0, 0.5));
    });

    testWidgets('should drain monotonically — filler width strictly shrinks as '
        'time advances', (tester) async {
      await _pumpScopeAndShow(tester);

      final widthAtStart = tester
          .getSize(find.byKey(SnackBarCountdown.fillerKey))
          .width;

      // Advance another second.
      await _pumpDrain(tester, const Duration(seconds: 1));
      final widthAfter1s = tester
          .getSize(find.byKey(SnackBarCountdown.fillerKey))
          .width;

      // Advance another second.
      await _pumpDrain(tester, const Duration(seconds: 1));
      final widthAfter2s = tester
          .getSize(find.byKey(SnackBarCountdown.fillerKey))
          .width;

      expect(
        widthAfter1s,
        lessThan(widthAtStart),
        reason:
            'Filler width MUST shrink between t=300 ms and t=1.3 s. '
            'Captured: start=$widthAtStart, after 1s=$widthAfter1s.',
      );
      expect(
        widthAfter2s,
        lessThan(widthAfter1s),
        reason:
            'Filler width MUST shrink between t=1.3 s and t=2.3 s. '
            'Captured: after 1s=$widthAfter1s, after 2s=$widthAfter2s.',
      );
    });

    testWidgets(
      'should drain linearly — width at duration/2 is ~half of width at '
      'duration/4 elapsed (curve is Curves.linear)',
      (tester) async {
        // Use a longer test duration so the entrance overhead is small
        // relative to the drain window — keeps the ratio assertion
        // tight.
        await tester.pumpWidget(
          MaterialApp(
            home: ScaffoldMessenger(
              child: SnackBarTapOutDismissScope(
                child: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (ctx) => ElevatedButton(
                        onPressed: () {
                          SnackBarTapOutDismissScope.of(
                            ctx,
                          ).showCountdownSnackBar(
                            context: ctx,
                            message: 'Set 1 deleted',
                            // 10 s gives plenty of headroom past
                            // entrance overhead — entrance is ~3% of
                            // total.
                            duration: const Duration(seconds: 10),
                            action: SnackBarAction(
                              label: 'UNDO',
                              onPressed: () {},
                            ),
                          );
                        },
                        child: const Text('Show snack'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Show snack'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final trackWidth = tester
            .getSize(find.byKey(SnackBarCountdown.trackKey))
            .width;

        // Pump to elapsed ≈ 2.5 s of 10 s (25% drained → expected
        // ~75% width).
        for (int i = 0; i < 22; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final widthAtQuarter = tester
            .getSize(find.byKey(SnackBarCountdown.fillerKey))
            .width;
        // 25% drained: expected fraction = 0.75.
        final expectedAtQuarter = trackWidth * 0.75;

        // Pump another 2.5 s → elapsed ≈ 5 s of 10 s (50% drained).
        for (int i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final widthAtHalf = tester
            .getSize(find.byKey(SnackBarCountdown.fillerKey))
            .width;
        final expectedAtHalf = trackWidth * 0.5;

        final tolerance = trackWidth * 0.03;
        expect(
          widthAtQuarter,
          closeTo(expectedAtQuarter, tolerance),
          reason:
              'After ~2.5 s of a 10 s drain (linear curve), filler '
              'should be ~75% of track width. Got $widthAtQuarter, '
              'expected $expectedAtQuarter ± $tolerance.',
        );
        expect(
          widthAtHalf,
          closeTo(expectedAtHalf, tolerance),
          reason:
              'After ~5 s of a 10 s drain (linear curve), filler should '
              'be ~50% of track width. Got $widthAtHalf, expected '
              '$expectedAtHalf ± $tolerance.',
        );
      },
    );
  });
}
