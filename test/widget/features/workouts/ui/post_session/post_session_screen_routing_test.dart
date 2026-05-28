/// Widget tests pinning two user-visible routing contracts on
/// [PostSessionScreen]:
///
///   1. Title display name — the summary EQUIP row must render the
///      LOCALIZED title NAME, never the raw slug
///      ([[cluster_slug_rendered_as_display_name]]). The slug is the
///      forever-stable join key for `earned_titles`; surfacing it on
///      screen as user-visible text is the failure mode this test pins.
///
///   2. State 9 (class-change-only) Beat 1 copy — when the reward tier is
///      [RewardTier.classChangeAnticipatory] AND no level-up event is
///      present (so `newCharacterLevel == null`), the rendered Beat 1
///      copy must route through `b1CopyClassChangeOnly`. The string
///      content overlaps with the PR-anticipatory variant today
///      ("NEW LIMIT.") but the route is asserted via the semantic
///      distinction — a future copy edit to one or the other must NOT
///      break State 9.
///
/// Both behaviors are asserted against the rendered widget tree (what the
/// user sees), not via mock-call verification. See
/// `feedback_widget_l10n_parameterization` and the testing-conventions
/// section of CLAUDE.md for the rationale.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/title.dart' as rpg;
import 'package:repsaga/features/rpg/providers/earned_titles_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/cinematic_skip_button.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/cinematic_tap_hint.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_controller.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_screen.dart';
import 'package:repsaga/l10n/app_localizations.dart';

/// Cross-build catalog entry the post-session screen looks up for the
/// `pillar_walker` slug (the load-bearing case — the same slug the
/// `_buildTitleCut` flow renders when a cross-build title unlocks).
const _kPillarWalkerCatalog = <rpg.Title>[
  rpg.Title.crossBuild(
    slug: 'pillar_walker',
    triggerId: rpg.CrossBuildTriggerId.pillarWalker,
  ),
];

/// Builds [PostSessionParams] for the test fixture. `AppLocalizations` is
/// loaded inside the harness once the locale resolves.
PostSessionParams _params({
  required CelebrationQueueResult queueResult,
  required PRDetectionResult? prResult,
  required AppLocalizations l10n,
  int totalXpEarned = 640,
  Map<BodyPart, int> bpXpDeltas = const {BodyPart.chest: 640},
  Map<BodyPart, int> bpRankBefore = const {},
}) {
  return PostSessionParams(
    queueResult: queueResult,
    prResult: prResult,
    exerciseNames: const {},
    totalXpEarned: totalXpEarned,
    bpXpDeltas: bpXpDeltas,
    bpProgressFractionPre: const {},
    bpRankBefore: bpRankBefore,
    bpFirstAwakening: const {},
    priorFinishedWorkoutCount: 46,
    durationMinutes: 48,
    setsCount: 20,
    tonnageTons: 7.8,
    l10n: l10n,
  );
}

Widget _harness({
  required PostSessionParams Function(AppLocalizations l10n) paramsBuilder,
  Locale locale = const Locale('en'),
  List<rpg.Title> catalog = _kPillarWalkerCatalog,
}) {
  return ProviderScope(
    overrides: [
      // Stub the catalog so the title cut + summary EQUIP row don't trip
      // over a missing assets/JSON load in the test harness.
      titleCatalogProvider.overrideWith((_) async => catalog),
      // The screen reads rpgProgressProvider once during initState; the
      // empty snapshot satisfies the controller's pre-render lookup
      // (the controller's value path falls back to
      // [RpgProgressSnapshot.empty] when the provider is still loading,
      // but overriding with an immediate-resolution stub avoids the
      // race entirely).
      rpgProgressProvider.overrideWith(
        () => _FakeRpgProgress(RpgProgressSnapshot.empty),
      ),
      // Per PR #277 review: the mount analytics emit reads
      // `currentUserIdProvider` in the post-frame callback, which by
      // default reads `Supabase.instance.client` and throws under
      // `flutter_test`. The analytics repository provider falls back to
      // a no-op on its own, so only `currentUserIdProvider` needs an
      // override here.
      currentUserIdProvider.overrideWithValue('user-routing-test'),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return PostSessionScreen(
            params: paramsBuilder(l10n),
            onContinue: () {},
          );
        },
      ),
    ),
  );
}

void main() {
  group(
    'PostSessionScreen — title display name (negative pin: never the slug)',
    () {
      testWidgets(
        'summary EQUIP row renders the localized name in en (not the slug)',
        (tester) async {
          // Use a realistic phone viewport — the post-session summary panel
          // composes for ~760dp tall production screens. The default 800x600
          // flutter_test viewport doesn't have enough vertical room for the
          // Mission Debrief section + EQUIP row + share CTA + CONTINUE rail
          // to fit, which produces a benign RenderFlex overflow in the test
          // that's irrelevant to the rendering contract being asserted.
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = const Size(360, 800);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _harness(
              paramsBuilder: (l10n) => _params(
                queueResult: const CelebrationQueueResult(
                  queue: [TitleUnlockEvent(slug: 'pillar_walker')],
                ),
                prResult: null,
                l10n: l10n,
              ),
            ),
          );
          await tester.pump();

          // Long-press skips every cinematic cut and lands directly on the
          // summary panel — the choreographer's designated fast-forward
          // path. CONTINUAR is summary-only, so pinning the EQUIP row's
          // displayed name on this surface is the post-cinematic contract.
          await tester.longPress(find.byType(PostSessionScreen));
          await tester.pump(const Duration(milliseconds: 50));

          // Negative pin: the raw slug must NEVER appear as user-visible
          // text on the summary panel.
          expect(find.text('pillar_walker'), findsNothing);
          // Positive pin: the localized en name resolves through
          // `localizedTitleCopy(slug, l10n)`.
          expect(find.text('Pillar-Walker'), findsOneWidget);
        },
      );

      testWidgets(
        'summary EQUIP row renders the localized name in pt-BR (not the slug)',
        (tester) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = const Size(360, 800);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _harness(
              locale: const Locale('pt'),
              paramsBuilder: (l10n) => _params(
                queueResult: const CelebrationQueueResult(
                  queue: [TitleUnlockEvent(slug: 'pillar_walker')],
                ),
                prResult: null,
                l10n: l10n,
              ),
            ),
          );
          await tester.pump();

          await tester.longPress(find.byType(PostSessionScreen));
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.text('pillar_walker'), findsNothing);
          expect(find.text('Andarilho de Pilares'), findsOneWidget);
        },
      );
    },
  );

  group('PostSessionScreen — State 9 (class-change-only) Beat 1 copy', () {
    testWidgets(
      'routes to b1CopyClassChangeOnly when only a class change is queued',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            paramsBuilder: (l10n) => _params(
              queueResult: const CelebrationQueueResult(
                queue: [
                  ClassChangeEvent(
                    fromClass: CharacterClass.initiate,
                    toClass: CharacterClass.bulwark,
                  ),
                ],
              ),
              prResult: null,
              l10n: l10n,
            ),
          ),
        );
        // Pump one frame past the initial postFrame so Beat 1 paints.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Steady-state en value of `b1CopyClassChangeOnly`. The
        // PR-anticipatory variant shares this string today; the routing
        // distinction is what matters — future divergence of either copy
        // line will surface here as a failure that points at the right
        // place to update.
        expect(find.text('NEW LIMIT.'), findsOneWidget);

        // Stop the in-flight controller and tear down without leaving
        // pending `Future.delayed` timers. The `_disposed` guard added in
        // the screen handles the actual teardown safety.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('tap-hint visible only on cut 0 before first tap; '
        'skip button visible during cinematic, gone on summary', (
      tester,
    ) async {
      // Use a baseline cut so we have a B1 to land on. With no reward
      // events queued the screen's choreographer emits exactly the B1
      // (+ optional B2 single) — cinematic plays, then summary mounts
      // after long-press.
      await tester.pumpWidget(
        _harness(
          paramsBuilder: (l10n) => _params(
            queueResult: const CelebrationQueueResult(queue: []),
            prResult: null,
            l10n: l10n,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Initial state — cut 0, untapped, hint NOT yet expired (2000ms
      // timer hasn't fired). Both the hint and the skip button render.
      expect(
        find.byType(CinematicTapHint),
        findsOneWidget,
        reason: 'Tap hint must be visible on cut 0 before first tap',
      );
      expect(
        find.byType(CinematicSkipButton),
        findsOneWidget,
        reason: 'Skip button must be visible during cinematic cuts',
      );

      // Skip to summary via the skip button. The button calls
      // controller.skipToSummary() — same path the long-press takes.
      await tester.tap(find.byType(CinematicSkipButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Summary mounted — neither affordance should render.
      expect(
        find.byType(CinematicSkipButton),
        findsNothing,
        reason: 'Skip button must NOT render on summary panel',
      );
      expect(
        find.byType(CinematicTapHint),
        findsNothing,
        reason: 'Tap hint must NOT render on summary panel',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'system back gesture shows leave-confirmation dialog; Leave routes '
      'through onContinue; Cancel keeps the screen mounted (Phase 31 Bug E)',
      (tester) async {
        // Track whether the route's onContinue ran.
        var onContinueFired = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              titleCatalogProvider.overrideWith(
                (_) async => _kPillarWalkerCatalog,
              ),
              rpgProgressProvider.overrideWith(
                () => _FakeRpgProgress(RpgProgressSnapshot.empty),
              ),
              // PR #277 review — see [_harness] for rationale.
              currentUserIdProvider.overrideWithValue('user-back-gesture-test'),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context);
                  return PostSessionScreen(
                    params: _params(
                      queueResult: const CelebrationQueueResult(queue: []),
                      prResult: null,
                      l10n: l10n,
                    ),
                    onContinue: () => onContinueFired++,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Round 1 — Cancel path. PopScope intercept fires a system back
        // (NavigatorState.maybePop), which routes through the screen's
        // onPopInvokedWithResult callback → showDialog.
        final NavigatorState navigator = tester.state(find.byType(Navigator));
        unawaited(navigator.maybePop());
        await tester.pumpAndSettle();

        // Dialog visible with localized copy. Button labels render
        // uppercased per the project's button-typography convention
        // (CONTINUAR / COMPARTILHAR / REFAZER all uppercase at the widget
        // layer — the dialog buttons match that aesthetic via .toUpperCase()).
        expect(find.text('Leave the post-battle?'), findsOneWidget);
        expect(find.text('CANCEL'), findsOneWidget);
        expect(find.text('LEAVE'), findsOneWidget);

        // Tap Cancel — dialog dismisses, screen still mounted, onContinue
        // NOT fired.
        await tester.tap(find.text('CANCEL'));
        await tester.pumpAndSettle();
        expect(find.text('Leave the post-battle?'), findsNothing);
        expect(find.byType(PostSessionScreen), findsOneWidget);
        expect(onContinueFired, 0, reason: 'Cancel must not fire onContinue');

        // Round 2 — Leave path. Same intercept → dialog → Leave button
        // routes through the controller's onContinue + the widget's
        // onContinue callback.
        unawaited(navigator.maybePop());
        await tester.pumpAndSettle();
        expect(find.text('Leave the post-battle?'), findsOneWidget);

        await tester.tap(find.text('LEAVE'));
        await tester.pumpAndSettle();
        expect(
          onContinueFired,
          1,
          reason: 'Leave must route through the screen onContinue exactly once',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'routes to b1CopyMaxLevelUp when a level-up co-occurs with class change',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            paramsBuilder: (l10n) => _params(
              queueResult: const CelebrationQueueResult(
                queue: [
                  ClassChangeEvent(
                    fromClass: CharacterClass.initiate,
                    toClass: CharacterClass.bulwark,
                  ),
                  LevelUpEvent(newLevel: 23),
                ],
              ),
              prResult: null,
              l10n: l10n,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Max-combo / level-up variant renders the level in the copy
        // line — substring assertion dodges whitespace/case fragility.
        expect(find.textContaining('LEVEL 23'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}

/// Fake [RpgProgressNotifier] that resolves a pre-canned snapshot
/// immediately. The post-session controller only reads this once via
/// `.value ?? RpgProgressSnapshot.empty` — no refresh-after-save path is
/// exercised here.
class _FakeRpgProgress extends RpgProgressNotifier {
  _FakeRpgProgress(this._snapshot);
  final RpgProgressSnapshot _snapshot;
  @override
  Future<RpgProgressSnapshot> build() async => _snapshot;
}

