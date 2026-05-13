import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/providers/notifiers/rest_timer_notifier.dart';
import 'package:repsaga/features/workouts/ui/widgets/rest_timer_overlay.dart';
import '../../../../../helpers/test_material_app.dart';

/// Builds a testable widget tree with an overridden [restTimerProvider].
Widget buildOverlay(RestTimerState? timerState) {
  return ProviderScope(
    overrides: [
      restTimerProvider.overrideWith(() => _FakeRestTimerNotifier(timerState)),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: RestTimerOverlay()),
    ),
  );
}

/// A minimal notifier that starts with a fixed state for widget tests.
///
/// Overrides [adjustTime] to compute elapsed from the state snapshot (not
/// from the wall clock) since these tests don't run under [fakeAsync].
/// The wall-clock behaviour of [adjustTime] is covered by the unit tests.
class _FakeRestTimerNotifier extends RestTimerNotifier {
  _FakeRestTimerNotifier(this._initial);
  final RestTimerState? _initial;

  @override
  RestTimerState? build() => _initial;

  @override
  void adjustTime(int deltaSeconds) {
    final current = state;
    if (current == null) return;
    final elapsed = current.totalSeconds - current.remainingSeconds;
    final newTotal = (current.totalSeconds + deltaSeconds).clamp(30, 600);
    final newRemaining = (newTotal - elapsed).clamp(0, newTotal);
    state = current.copyWith(
      totalSeconds: newTotal,
      remainingSeconds: newRemaining,
    );
  }
}

void main() {
  group('RestTimerOverlay', () {
    group('rendering', () {
      testWidgets(
        'renders nothing (SizedBox.shrink) when timer state is null',
        (tester) async {
          await tester.pumpWidget(buildOverlay(null));

          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('Skip'), findsNothing);
        },
      );

      testWidgets('displays formatted countdown text "1:30" for 90 seconds', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 90,
          remainingSeconds: 90,
          isActive: true,
        );
        await tester.pumpWidget(buildOverlay(state));

        expect(find.text('1:30'), findsOneWidget);
      });

      testWidgets('displays "0:00" when remaining seconds is zero', (
        tester,
      ) async {
        // Use isActive: true to avoid triggering the auto-dismiss Future.delayed
        // inside the widget, which would leave a pending timer after the test.
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 0,
          isActive: true,
        );
        await tester.pumpWidget(buildOverlay(state));

        expect(find.text('0:00'), findsOneWidget);
      });

      testWidgets('displays the circular progress indicator when active', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 30,
          isActive: true,
        );
        await tester.pumpWidget(buildOverlay(state));

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('displays the "Rest" label when timer is active', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 30,
          isActive: true,
        );
        await tester.pumpWidget(buildOverlay(state));

        expect(find.text('Rest'), findsOneWidget);
      });

      testWidgets('displays the Skip button when timer is active', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 30,
          isActive: true,
        );
        await tester.pumpWidget(buildOverlay(state));

        expect(find.text('Skip'), findsOneWidget);
      });

      testWidgets('displays -30s and +30s buttons when timer is active', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 30,
          isActive: true,
        );
        await tester.pumpWidget(buildOverlay(state));

        expect(find.text('-30s'), findsOneWidget);
        expect(find.text('+30s'), findsOneWidget);
      });

      testWidgets('does not display -30s or +30s buttons when timer is null', (
        tester,
      ) async {
        await tester.pumpWidget(buildOverlay(null));

        expect(find.text('-30s'), findsNothing);
        expect(find.text('+30s'), findsNothing);
      });
    });

    group('interactions', () {
      testWidgets('tapping overlay background stops timer', (tester) async {
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 45,
          isActive: true,
        );

        final container = ProviderContainer(
          overrides: [
            restTimerProvider.overrideWith(() => _FakeRestTimerNotifier(state)),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(body: RestTimerOverlay()),
            ),
          ),
        );

        // Verify the timer is active before tapping.
        expect(container.read(restTimerProvider), isNotNull);

        // Tap on the background area (top-left corner, away from buttons).
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();

        // Timer should be stopped (null state).
        expect(container.read(restTimerProvider), isNull);
      });

      testWidgets('tapping Skip button sets timer state to null', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 45,
          isActive: true,
        );

        final container = ProviderContainer(
          overrides: [
            restTimerProvider.overrideWith(() => _FakeRestTimerNotifier(state)),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(body: RestTimerOverlay()),
            ),
          ),
        );

        await tester.tap(find.text('Skip'));
        await tester.pump();

        expect(container.read(restTimerProvider), isNull);
      });
    });

    group('adjustment button interactions', () {
      testWidgets('tapping +30s calls adjustTime(30) on notifier', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 60,
          isActive: true,
        );

        final container = ProviderContainer(
          overrides: [
            restTimerProvider.overrideWith(() => _FakeRestTimerNotifier(state)),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(body: RestTimerOverlay()),
            ),
          ),
        );

        await tester.tap(find.text('+30s'));
        await tester.pump();

        final updatedState = container.read(restTimerProvider);
        expect(updatedState!.totalSeconds, 90);
        expect(updatedState.remainingSeconds, 90);
      });

      testWidgets('tapping -30s calls adjustTime(-30) on notifier', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 90,
          remainingSeconds: 90,
          isActive: true,
        );

        final container = ProviderContainer(
          overrides: [
            restTimerProvider.overrideWith(() => _FakeRestTimerNotifier(state)),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(body: RestTimerOverlay()),
            ),
          ),
        );

        await tester.tap(find.text('-30s'));
        await tester.pump();

        final updatedState = container.read(restTimerProvider);
        expect(updatedState!.totalSeconds, 60);
        expect(updatedState.remainingSeconds, 60);
      });
    });

    group('tap-through prevention', () {
      // Structural pin for the outer scrim's `HitTestBehavior.opaque`. A
      // behavioral test would be misleading here — `Material` absorbs
      // hit-tests at the render level in the widget-test environment, so a
      // tap-propagation assertion would pass with or without the production
      // fix. Pinning the property structurally is the load-bearing test;
      // the dismissal contract is covered by the existing 'interactions'
      // group above.

      testWidgets(
        'outer scrim GestureDetector declares HitTestBehavior.opaque',
        (tester) async {
          const state = RestTimerState(
            totalSeconds: 60,
            remainingSeconds: 45,
            isActive: true,
          );
          await tester.pumpWidget(buildOverlay(state));

          // The widget tree contains exactly two GestureDetectors:
          //   - the outer scrim-dismiss detector (L49)
          //   - the inner control-row detector (L108) which is already opaque
          // The outer is the topmost GestureDetector; the inner is its
          // descendant. Assert ALL GestureDetectors in the overlay declare
          // opaque hit-testing — the outer for tap-through prevention, the
          // inner so button taps don't bubble to the dismiss handler.
          final detectors = tester
              .widgetList<GestureDetector>(find.byType(GestureDetector))
              .toList();

          expect(
            detectors,
            isNotEmpty,
            reason:
                'RestTimerOverlay must contain at least one GestureDetector',
          );
          for (final d in detectors) {
            expect(
              d.behavior,
              HitTestBehavior.opaque,
              reason:
                  'RestTimerOverlay GestureDetectors must use '
                  'HitTestBehavior.opaque to block tap propagation to widgets '
                  'painted beneath the scrim',
            );
          }
        },
      );
    });

    group('accessibility', () {
      testWidgets(
        'overlay has semantics label containing remaining time for screen readers',
        (tester) async {
          const state = RestTimerState(
            totalSeconds: 120,
            remainingSeconds: 75,
            isActive: true,
          );
          await tester.pumpWidget(buildOverlay(state));

          // The Semantics widget wraps the progress ring + countdown text.
          expect(
            find.bySemanticsLabel(RegExp(r'Rest timer.*1:15.*remaining')),
            findsOneWidget,
          );
        },
      );

      testWidgets('Skip button has "Skip rest timer" semantics label', (
        tester,
      ) async {
        const state = RestTimerState(
          totalSeconds: 60,
          remainingSeconds: 30,
          isActive: true,
        );
        await tester.pumpWidget(buildOverlay(state));

        expect(find.bySemanticsLabel('Skip rest timer'), findsOneWidget);
      });

      testWidgets(
        'countdown Semantics declares liveRegion: true so screen readers announce ticks (Family 3 — AW-EX-F-BR1-06)',
        (tester) async {
          // The rest-timer countdown drives the user's between-set rhythm.
          // Without `liveRegion: true` on the Semantics wrapping the
          // countdown, screen readers do NOT re-announce on tick changes —
          // the user only hears the time when the overlay first appears.
          // Pin the property structurally so a refactor that drops
          // liveRegion fails fast, before the regression reaches a
          // screen-reader user.
          const state = RestTimerState(
            totalSeconds: 60,
            remainingSeconds: 45,
            isActive: true,
          );
          await tester.pumpWidget(buildOverlay(state));

          // Find the Semantics widget that holds the countdown label and
          // assert it declares `liveRegion: true`. The countdown label
          // matches `RegExp(r'Rest timer.*remaining')`.
          final semanticsWidgets = tester
              .widgetList<Semantics>(find.byType(Semantics))
              .where(
                (s) =>
                    s.properties.label != null &&
                    RegExp(
                      r'Rest timer.*remaining',
                    ).hasMatch(s.properties.label!),
              )
              .toList();

          expect(
            semanticsWidgets,
            isNotEmpty,
            reason:
                'Expected to find a Semantics widget wrapping the countdown '
                'with a label matching "Rest timer ... remaining".',
          );
          expect(
            semanticsWidgets.first.properties.liveRegion,
            isTrue,
            reason:
                'Countdown Semantics MUST declare liveRegion: true so '
                'screen readers announce each tick. Without it, the user '
                'hears the time once and is stranded.',
          );
        },
      );

      testWidgets(
        'outer dismiss scrim exposes "Dismiss rest timer" Semantics (Family 3 — AW-EX-F-BR1-06)',
        (tester) async {
          // The outer GestureDetector at L49 is the tap-anywhere-to-dismiss
          // affordance. Pre-fix it had no Semantics — sighted users could
          // dismiss by tapping the scrim, but screen-reader users had no
          // way to discover or invoke that action. Pin the localized label
          // is reachable on the AOM.
          const state = RestTimerState(
            totalSeconds: 60,
            remainingSeconds: 45,
            isActive: true,
          );
          await tester.pumpWidget(buildOverlay(state));

          expect(find.bySemanticsLabel('Dismiss rest timer'), findsOneWidget);
        },
      );

      testWidgets(
        'exercise-name Text is wrapped in a Semantics(label:) so it surfaces in the AOM',
        (tester) async {
          const state = RestTimerState(
            totalSeconds: 60,
            remainingSeconds: 45,
            exerciseName: 'Bench Press',
            isActive: true,
          );
          await tester.pumpWidget(buildOverlay(state));

          expect(find.bySemanticsLabel('Bench Press'), findsOneWidget);
        },
      );

      testWidgets(
        'tap-to-dismiss hint copy is removed (Phase 23 UI/UX REV-3)',
        (tester) async {
          // The visible "Tap anywhere to dismiss" hint Text was removed
          // 2026-05-12 as mechanic-instructive filler — the outer
          // `restTimerDismiss` Semantics label still carries the
          // screen-reader affordance, and the visible -30s / Skip / +30s
          // controls + scrim-as-tap-target cover the sighted case.
          //
          // Pin the deletion at both layers: no visible Text AND no
          // residual AOM label. If either reappears, the REV-3 fix was
          // reverted (and the PR-5 contrast pin / PR #187 ExcludeSemantics
          // pin would re-engage in lockstep, so they don't need their own
          // separate guard anymore).
          const state = RestTimerState(
            totalSeconds: 60,
            remainingSeconds: 45,
            isActive: true,
          );
          await tester.pumpWidget(buildOverlay(state));

          expect(
            find.text('Tap anywhere to dismiss'),
            findsNothing,
            reason:
                'Phase 23 REV-3: the dismiss-hint Text was removed — the '
                'outer Semantics label + visible controls own the dismiss '
                'affordance. If this finds a widget, the hint was '
                're-added.',
          );
          expect(
            find.bySemanticsLabel('Tap anywhere to dismiss'),
            findsNothing,
            reason:
                'Phase 23 REV-3: no residual AOM label for the removed '
                'hint. The canonical affordance lives on the outer scrim '
                '`restTimerDismiss` label (verified by the sibling pin '
                'below).',
          );
          // Paired positive: canonical AOM affordance is still reachable.
          expect(find.bySemanticsLabel('Dismiss rest timer'), findsOneWidget);
        },
      );
    });

    // PR-5 — device-feedback fix (Samsung S25 Ultra).
    //
    // Pre-fix: each control button was wrapped in
    // `SizedBox(width: 64, height: 56)`. On a real Android device with
    // OEM font rendering, `+30s` wrapped to two lines because TextButton's
    // default 16dp horizontal padding ate ~32dp of the 64dp box, and `+30s`
    // at `titleMedium @ w700` (the `+` glyph is wider than `-`) didn't fit
    // in the remaining ~32dp. Playwright at 360dp Chromium did NOT catch
    // it — desktop font metrics differed enough.
    //
    // Fix shape: dropped the SizedBox; use TextButton's intrinsic content +
    // padding sizing, with `minimumSize: Size(48, 48)` enforcing the WCAG
    // tap-target floor. Buttons end up slightly asymmetric in width but
    // never wrap, scale with font accessibility settings, and meet the
    // 48dp tap-target floor on every screen size.
    //
    // This pin guards both contracts: tap-target floor + single-line.
    group('PR-5 — control button sizing (device-feedback fix)', () {
      testWidgets(
        '-30s, Skip, +30s render single-line + meet 48dp tap-target floor',
        (tester) async {
          const state = RestTimerState(
            totalSeconds: 90,
            remainingSeconds: 90,
            isActive: true,
          );
          await tester.pumpWidget(buildOverlay(state));

          final plusButton = find.widgetWithText(TextButton, '+30s');
          final minusButton = find.widgetWithText(TextButton, '-30s');
          final skipButton = find.widgetWithText(TextButton, 'Skip');

          expect(plusButton, findsOneWidget);
          expect(minusButton, findsOneWidget);
          expect(skipButton, findsOneWidget);

          final plusSize = tester.getSize(plusButton);
          final minusSize = tester.getSize(minusButton);
          final skipSize = tester.getSize(skipButton);

          // Single-line height contract — if the SizedBox constraint ever
          // returns and `+30s` wraps, the rendered height grows past
          // ~60dp. A single-line `titleMedium @ w700` button should be
          // ~48-56dp tall.
          expect(
            plusSize.height,
            lessThan(72),
            reason:
                '+30s wrapped to multiple lines (got ${plusSize.height}dp). '
                'Pre-fix bug from Samsung S25 Ultra device feedback.',
          );
          expect(
            minusSize.height,
            lessThan(72),
            reason:
                '-30s wrapped to multiple lines (got ${minusSize.height}dp).',
          );

          // WCAG 48dp tap-target floor on both axes.
          for (final s in [plusSize, minusSize, skipSize]) {
            expect(
              s.width,
              greaterThanOrEqualTo(48),
              reason: 'tap-target width below 48dp floor: $s',
            );
            expect(
              s.height,
              greaterThanOrEqualTo(48),
              reason: 'tap-target height below 48dp floor: $s',
            );
          }
        },
      );
    });
  });
}
