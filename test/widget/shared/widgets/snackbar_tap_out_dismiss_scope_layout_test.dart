/// Parameterized layout invariants for [SnackBarCountdown] across
/// representative viewport sizes (320 dp → 800 dp).
///
/// **Why this test exists.** The on-device 2026-05-13 report showed the
/// progress bar sitting only beneath the message text (not spanning the
/// full snack width) and floating ~14 dp above the snack's bottom edge.
/// The fix (commit `b674628`) restructured the widget so it owns the
/// entire snack interior — message row + action button + bottom-edge
/// progress bar — with `SnackBar.padding: EdgeInsets.zero` and
/// `SnackBar.action: null` so nothing competes for inner real estate.
///
/// This test pins the fix structurally by measuring rendered `Rect`s at
/// six viewport sizes that span compact phones through landscape
/// tablets. Each invariant is asserted at every viewport via a single
/// parametric `testWidgets` block — a regression at any width fails the
/// test with the exact viewport label that broke.
///
/// Why a parametric test in lieu of a per-device on-device check:
/// the user can't always have hardware in reach, but `tester.view.
/// physicalSize` + `tester.getRect` are deterministic across CI/dev
/// machines and capture the same rendering math the device uses.
///
/// **The six invariants** (one `testWidgets` block each):
///   1. Bar width equals the snack interior width (no horizontal gap).
///   2. Bar bottom-Y equals the snack interior bottom-Y (no vertical
///      gap to the snack's bottom edge).
///   3. Message Text is wrapped in `Expanded` — its rendered width plus
///      the action button's width plus the right-side padding equals
///      the snack interior width (within a 4 dp tolerance for
///      `TextButton` internal-padding rounding).
///   4. No `RenderFlex overflowed` exception at the narrowest 320 dp
///      viewport (the spec's stress case).
///   5. Action button stays right-aligned — its left edge is always
///      to the right of the message text's right edge.
///   6. A diagnostic invariant that dumps the per-viewport numbers in a
///      stable format the test runner emits via `printOnFailure`.
///      Not assertive on its own; piggybacks on (1)+(2) — kept separate
///      so the diagnostic output is always emitted even when the
///      asserting invariants pass.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/shared/widgets/snackbar_tap_out_dismiss_scope.dart';

/// Representative viewport sizes spanning compact Android phones through
/// landscape tablets. All values are LOGICAL dp; the test multiplies by
/// a fixed devicePixelRatio to derive physical pixels.
const _viewportsDp = <(String, Size)>[
  ('compact Android 320', Size(320, 640)),
  ('standard Android 360', Size(360, 720)),
  ('iPhone 14 390', Size(390, 844)),
  // Samsung S25 Ultra reports ~412 dp effective width in portrait — the
  // exact device the user reported the original bug from.
  ('large Android 412 (S25 Ultra)', Size(412, 915)),
  ('tablet portrait 600', Size(600, 960)),
  ('tablet landscape 800', Size(800, 600)),
];

const _devicePixelRatio = 3.0;

/// 4 dp tolerance accounts for Material `TextButton` internal padding
/// rounding plus subpixel layout math. Bar-vs-snack alignments are
/// pinned to 0 dp tolerance — those are exact-pixel contracts.
const _undoColumnTolerance = 4.0;

/// The on-screen message we drive — long enough to actually fill the
/// `Expanded` slot at narrow widths, short enough to never wrap to two
/// lines at the wider viewports.
const _message = 'Set 1 deleted';
const _undoLabel = 'UNDO';

Future<void> _pumpScope(WidgetTester tester, Size viewport) async {
  tester.view.physicalSize = viewport * _devicePixelRatio;
  tester.view.devicePixelRatio = _devicePixelRatio;

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
                        message: _message,
                        duration: const Duration(seconds: 4),
                        action: SnackBarAction(
                          label: _undoLabel,
                          onPressed: () {},
                        ),
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
  // Pump the entrance animation to completion. SnackBar's default entrance
  // is ~250 ms; pump 300 ms to land comfortably past it.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() {
    // Reset the test view after each scenario so a viewport set by one
    // test never leaks into the next.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  group('SnackBarCountdown layout invariants — adaptive across viewport sizes', () {
    testWidgets(
      'should render the progress bar at the snack interior full width '
      'across all viewports',
      (tester) async {
        for (final (label, viewport) in _viewportsDp) {
          await _pumpScope(tester, viewport);

          final snackSize = tester.getSize(find.byType(SnackBarCountdown));
          final trackSize = tester.getSize(
            find.byKey(SnackBarCountdown.trackKey),
          );

          expect(
            trackSize.width,
            snackSize.width,
            reason:
                'Viewport "$label" (${viewport.width}×${viewport.height} '
                'dp): the progress bar`s rendered width '
                '(${trackSize.width}) MUST equal the snack interior '
                'width (${snackSize.width}) — i.e. the bar spans edge '
                'to edge. If this fails the SnackBar.padding override '
                'is missing or the bar is nested under another '
                'horizontally-constrained widget.',
          );
        }
      },
    );

    testWidgets('should hug the snack`s bottom edge across all viewports (bar '
        'bottom-Y equals snack bottom-Y, 0 dp gap)', (tester) async {
      for (final (label, viewport) in _viewportsDp) {
        await _pumpScope(tester, viewport);

        final snackRect = tester.getRect(find.byType(SnackBarCountdown));
        final trackRect = tester.getRect(
          find.byKey(SnackBarCountdown.trackKey),
        );

        expect(
          trackRect.bottom,
          snackRect.bottom,
          reason:
              'Viewport "$label" (${viewport.width}×${viewport.height} '
              'dp): the progress bar`s bottom-Y (${trackRect.bottom}) '
              'MUST equal the snack`s bottom-Y (${snackRect.bottom}) '
              '— no dead space between the bar and the snack`s bottom '
              'edge. If this fails the SnackBar.padding override is '
              'missing or another widget is occupying the Column`s '
              'last slot below the bar.',
        );
      }
    });

    testWidgets('should expand the message Text to fill the row width '
        '(message + action + right padding ≈ snack interior)', (tester) async {
      for (final (label, viewport) in _viewportsDp) {
        await _pumpScope(tester, viewport);

        final snackRect = tester.getRect(find.byType(SnackBarCountdown));
        final messageRect = tester.getRect(find.text(_message));
        final actionRect = tester.getRect(
          find.widgetWithText(TextButton, _undoLabel),
        );

        // The Expanded(message) + TextButton(action) Row sits inside
        // a Padding(EdgeInsets.fromLTRB(16, 14, 8, 12)). With the
        // action present, the row spans from snackRect.left + 16
        // (left pad) to snackRect.right - 8 (right pad). The
        // message's right edge sits flush against the action's left
        // edge. Net assertion: the *combined* horizontal footprint
        // (message.left → action.right) plus the outer paddings
        // equals the snack width.
        //
        // 4 dp tolerance accounts for TextButton's internal padding
        // (12 horizontal) + Material's tap-target layout rounding.
        final combinedFootprint = actionRect.right - messageRect.left;
        final expectedFootprint =
            snackRect.width - 16 /* left pad */ - 8 /* right pad */;

        expect(
          combinedFootprint,
          closeTo(expectedFootprint, _undoColumnTolerance),
          reason:
              'Viewport "$label" (${viewport.width}×${viewport.height} '
              'dp): message+action combined horizontal footprint '
              '($combinedFootprint dp) must equal the snack interior '
              'minus L/R padding ($expectedFootprint dp ± '
              '$_undoColumnTolerance dp tolerance). If this fails the '
              'message Text is no longer wrapped in `Expanded` or the '
              'padding constants drifted.',
        );
      }
    });

    testWidgets('should NOT overflow at the narrowest viewport (320 dp)', (
      tester,
    ) async {
      await _pumpScope(tester, const Size(320, 640));
      expect(
        tester.takeException(),
        isNull,
        reason:
            'At 320 dp viewport (the narrowest in our matrix), the '
            'snack must lay out without throwing a RenderFlex '
            'overflow. If this fails the message Text needs an '
            '`Expanded` wrap or `TextOverflow.ellipsis` to handle '
            'edge-case width constraints.',
      );
    });

    testWidgets(
      'should keep the action button right of the message text across '
      'all viewports',
      (tester) async {
        for (final (label, viewport) in _viewportsDp) {
          await _pumpScope(tester, viewport);

          final messageRect = tester.getRect(find.text(_message));
          final actionRect = tester.getRect(
            find.widgetWithText(TextButton, _undoLabel),
          );

          expect(
            actionRect.left,
            greaterThanOrEqualTo(messageRect.right),
            reason:
                'Viewport "$label" (${viewport.width}×${viewport.height} '
                'dp): the UNDO button`s left edge (${actionRect.left} '
                'dp) must be at or right of the message text`s right '
                'edge (${messageRect.right} dp). If this fails the Row '
                'ordering broke — message and action are overlapping.',
          );
        }
      },
    );

    testWidgets('diagnostic — emit per-viewport rendered widths for cold-read '
        'verification (always passes; output via printOnFailure)', (
      tester,
    ) async {
      final lines = <String>[
        '| viewport dp | snack interior dp | bar width dp | bar Y == snack Y |',
        '|---|---|---|---|',
      ];

      for (final (label, viewport) in _viewportsDp) {
        await _pumpScope(tester, viewport);

        final snackRect = tester.getRect(find.byType(SnackBarCountdown));
        final trackRect = tester.getRect(
          find.byKey(SnackBarCountdown.trackKey),
        );

        // toStringAsFixed(2) — keeps the table readable while
        // preserving sub-pixel detail if rounding ever drifts.
        final viewportLabel = '${viewport.width.toInt()} ($label)';
        final snackWidth = snackRect.width.toStringAsFixed(2);
        final trackWidth = trackRect.width.toStringAsFixed(2);
        final bottomMatch = trackRect.bottom == snackRect.bottom
            ? 'YES'
            : 'NO (Δ=${(snackRect.bottom - trackRect.bottom).toStringAsFixed(2)})';

        lines.add(
          '| $viewportLabel | $snackWidth | $trackWidth | $bottomMatch |',
        );
      }

      // printOnFailure registers the diagnostic with the test runner;
      // it shows in stdout when the test passes (via --reporter
      // expanded) AND in the failure log on failure. The expect()
      // below is a no-op tautology so the diagnostic is unmissable
      // when scanning a green run.
      printOnFailure(lines.join('\n'));
      // ignore: avoid_print -- diagnostic table is the value of this test
      for (final line in lines) {
        // ignore: avoid_print
        print(line);
      }

      expect(lines.length, _viewportsDp.length + 2);
    });
  });
}
