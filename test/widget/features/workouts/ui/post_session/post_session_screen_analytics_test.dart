/// Phase 32 PR 32d — `post_session_cinematic_shown` + per-title
/// `title_unlocked` analytics emit on PostSessionScreen mount.
///
/// Pins three behaviors:
///   1. ONE `post_session_cinematic_shown` fires on mount (post-first-frame),
///      carrying the in-scope `total_xp`, `had_rank_up`, `had_title_unlock`,
///      `had_class_change` flags derived from the queue.
///   2. ONE `title_unlocked` event fires per [TitleUnlockEvent] in the queue,
///      carrying the slug + the `sagaNumber` as `workout_number`.
///   3. Multiple frame pumps + rebuilds DO NOT cause duplicate emits — the
///      `_analyticsFired` one-shot guard holds across rebuilds.
///
/// Behavior, not wiring: events are captured into a recording fake and the
/// EXACT [AnalyticsEvent] values are asserted against the canonical
/// constructors. A future shape change must update both the screen AND
/// these assertions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/title.dart' as rpg;
import 'package:repsaga/features/rpg/providers/earned_titles_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_controller.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_screen.dart';
import 'package:repsaga/l10n/app_localizations.dart';

const _kCatalog = <rpg.Title>[
  rpg.Title.crossBuild(
    slug: 'pillar_walker',
    triggerId: rpg.CrossBuildTriggerId.pillarWalker,
  ),
];

PostSessionParams _params({
  required CelebrationQueueResult queueResult,
  required AppLocalizations l10n,
  int totalXpEarned = 640,
  int priorFinishedWorkoutCount = 46,
  Map<BodyPart, int> bpXpDeltas = const {BodyPart.chest: 640},
}) {
  return PostSessionParams(
    queueResult: queueResult,
    prResult: null,
    exerciseNames: const {},
    totalXpEarned: totalXpEarned,
    bpXpDeltas: bpXpDeltas,
    bpProgressFractionPre: const {},
    bpRankBefore: const {},
    bpVitalityBefore: const {},
    bpFirstAwakening: const {},
    priorFinishedWorkoutCount: priorFinishedWorkoutCount,
    durationMinutes: 48,
    setsCount: 20,
    tonnageTons: 7.8,
    l10n: l10n,
  );
}

Widget _harness({
  required PostSessionParams Function(AppLocalizations l10n) paramsBuilder,
  required _RecordingAnalyticsRepository analyticsRepo,
  String? userId = 'user-mount-001',
}) {
  return ProviderScope(
    overrides: [
      titleCatalogProvider.overrideWith((_) async => _kCatalog),
      rpgProgressProvider.overrideWith(
        () => _FakeRpgProgress(RpgProgressSnapshot.empty),
      ),
      analyticsRepositoryProvider.overrideWithValue(analyticsRepo),
      currentUserIdProvider.overrideWithValue(userId),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
  group('PostSessionScreen — Phase 32 PR 32d mount analytics', () {
    testWidgets(
      'emits ONE post_session_cinematic_shown on mount with derived flags',
      (tester) async {
        final analyticsRepo = _RecordingAnalyticsRepository();
        await tester.pumpWidget(
          _harness(
            paramsBuilder: (l10n) => _params(
              queueResult: const CelebrationQueueResult(
                queue: [
                  RankUpEvent(bodyPart: BodyPart.chest, newRank: 2),
                  TitleUnlockEvent(slug: 'pillar_walker'),
                  ClassChangeEvent(
                    fromClass: CharacterClass.initiate,
                    toClass: CharacterClass.bulwark,
                  ),
                ],
              ),
              l10n: l10n,
            ),
            analyticsRepo: analyticsRepo,
          ),
        );
        // Pump past the post-frame callback so `_fireMountAnalytics` runs.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final cinematicEvents = analyticsRepo.events
            .where((e) => e.name == 'post_session_cinematic_shown')
            .toList();
        expect(cinematicEvents, hasLength(1));
        expect(
          cinematicEvents.single,
          const AnalyticsEvent.postSessionCinematicShown(
            totalXp: 640,
            hadRankUp: true,
            hadTitleUnlock: true,
            hadClassChange: true,
          ),
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('derives all-false flags + zero xp from an empty queue', (
      tester,
    ) async {
      final analyticsRepo = _RecordingAnalyticsRepository();
      await tester.pumpWidget(
        _harness(
          paramsBuilder: (l10n) => _params(
            queueResult: const CelebrationQueueResult(queue: []),
            totalXpEarned: 0,
            bpXpDeltas: const {},
            l10n: l10n,
          ),
          analyticsRepo: analyticsRepo,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final cinematicEvents = analyticsRepo.events
          .where((e) => e.name == 'post_session_cinematic_shown')
          .toList();
      expect(cinematicEvents, hasLength(1));
      expect(
        cinematicEvents.single,
        const AnalyticsEvent.postSessionCinematicShown(
          totalXp: 0,
          hadRankUp: false,
          hadTitleUnlock: false,
          hadClassChange: false,
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'emits one title_unlocked per TitleUnlockEvent with workout_number = '
      'sagaNumber',
      (tester) async {
        final analyticsRepo = _RecordingAnalyticsRepository();
        // priorFinishedWorkoutCount = 6 → sagaNumber = 7 (incremented in the
        // controller on mount).
        await tester.pumpWidget(
          _harness(
            paramsBuilder: (l10n) => _params(
              priorFinishedWorkoutCount: 6,
              queueResult: const CelebrationQueueResult(
                queue: [TitleUnlockEvent(slug: 'pillar_walker')],
              ),
              l10n: l10n,
            ),
            analyticsRepo: analyticsRepo,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final titleEvents = analyticsRepo.events
            .where((e) => e.name == 'title_unlocked')
            .toList();
        expect(titleEvents, hasLength(1));
        expect(
          titleEvents.single,
          const AnalyticsEvent.titleUnlocked(
            titleSlug: 'pillar_walker',
            workoutNumber: 7,
          ),
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'does NOT double-fire across multiple frame pumps (rebuild guard)',
      (tester) async {
        final analyticsRepo = _RecordingAnalyticsRepository();
        await tester.pumpWidget(
          _harness(
            paramsBuilder: (l10n) => _params(
              queueResult: const CelebrationQueueResult(
                queue: [TitleUnlockEvent(slug: 'pillar_walker')],
              ),
              l10n: l10n,
            ),
            analyticsRepo: analyticsRepo,
          ),
        );
        // Pump many frames — the choreographer's animations + Riverpod
        // rebuilds must not retrigger the post-frame analytics emit.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        final cinematicCount = analyticsRepo.events
            .where((e) => e.name == 'post_session_cinematic_shown')
            .length;
        final titleCount = analyticsRepo.events
            .where((e) => e.name == 'title_unlocked')
            .length;

        expect(cinematicCount, 1, reason: 'guard must prevent double-fire');
        expect(titleCount, 1, reason: 'guard must prevent double-fire');

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('no emit when current user id is null (logged-out edge)', (
      tester,
    ) async {
      final analyticsRepo = _RecordingAnalyticsRepository();
      await tester.pumpWidget(
        _harness(
          paramsBuilder: (l10n) => _params(
            queueResult: const CelebrationQueueResult(
              queue: [TitleUnlockEvent(slug: 'pillar_walker')],
            ),
            l10n: l10n,
          ),
          analyticsRepo: analyticsRepo,
          userId: null,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // No user id → no records (defensive — logged-out users should never
      // reach this screen, but the guard is cheap insurance).
      expect(analyticsRepo.events, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// Recording fake — captures every event the screen pushes through
/// [AnalyticsRepository.insertEvent] so tests can assert on the EXACT
/// payload (not just the call count). Same pattern as the share controller
/// test file.
class _RecordingAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  final List<AnalyticsEvent> events = [];

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    events.add(event);
  }
}

class _FakeRpgProgress extends RpgProgressNotifier {
  _FakeRpgProgress(this._snapshot);
  final RpgProgressSnapshot _snapshot;
  @override
  Future<RpgProgressSnapshot> build() async => _snapshot;
}
