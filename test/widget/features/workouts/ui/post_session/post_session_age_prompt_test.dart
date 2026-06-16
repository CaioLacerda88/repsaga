/// Phase 38d — post-session "set your age" one-time nudge.
///
/// Pins user-perceptible gating on the post-session SUMMARY:
///   * Shows IFF the session had a completed cardio entry AND the profile
///     has no birth date AND the prompt isn't dismissed.
///   * Hidden when DOB is set, when not-cardio, and when already dismissed.
///   * Dismissing removes the banner AND records the never-show-again flag
///     (so it never re-appears) — the banner is gone after dismiss.
///   * "Set age" opens the AgeEditorSheet.
///
/// Behavior, not wiring: every assertion checks what's on screen (banner
/// present/absent, sheet open) — not that a method was called.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/data/profile_repository.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/age_prompt_dismissal_provider.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/widgets/age_row.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/cardio_session.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_controller.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_screen.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/age_prompt_banner.dart';
import 'package:repsaga/l10n/app_localizations.dart';

class _MockProfileRepository extends Mock implements ProfileRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _StubProfileNotifier extends AsyncNotifier<Profile?>
    with Mock
    implements ProfileNotifier {
  _StubProfileNotifier(this._profile);
  final Profile? _profile;
  @override
  Future<Profile?> build() async => _profile;
}

class _StubDismissal extends AgePromptDismissalNotifier {
  _StubDismissal(this._initial);
  final bool _initial;
  @override
  bool build() => _initial;
  @override
  Future<void> markDismissed() async {
    state = true;
  }
}

class _FakeRpgProgress extends RpgProgressNotifier {
  @override
  Future<RpgProgressSnapshot> build() async => RpgProgressSnapshot.empty;
}

ActiveWorkoutExercise _completedCardioEntry() {
  return ActiveWorkoutExercise(
    workoutExercise: const WorkoutExercise(
      id: 'we-cardio',
      workoutId: 'workout-1',
      exerciseId: 'ex-treadmill',
      order: 0,
    ),
    sets: const [],
    cardioSession: CardioSession(
      id: 'cardio-1',
      workoutId: 'workout-1',
      exerciseId: 'ex-treadmill',
      durationSeconds: 1725,
      isCompleted: true,
      createdAt: DateTime.utc(2026, 6, 12, 10),
    ),
  );
}

PostSessionParams _params({
  required AppLocalizations l10n,
  required List<ActiveWorkoutExercise> exercises,
}) {
  return PostSessionParams(
    queueResult: const CelebrationQueueResult(queue: []),
    prResult: null,
    exerciseNames: const {},
    totalXpEarned: 240,
    bpXpDeltas: const {BodyPart.chest: 240},
    bpProgressFractionPre: const {},
    bpRankBefore: const {},
    bpFirstAwakening: const {},
    priorFinishedWorkoutCount: 5,
    durationMinutes: 28,
    setsCount: 0,
    tonnageTons: 0.0,
    exercises: exercises,
    l10n: l10n,
  );
}

Widget _harness({
  required Profile? profile,
  required List<ActiveWorkoutExercise> exercises,
  bool dismissed = false,
  _MockProfileRepository? repo,
}) {
  final mockRepo = repo ?? _MockProfileRepository();
  final mockAuth = _MockAuthRepository();
  return ProviderScope(
    overrides: [
      rpgProgressProvider.overrideWith(_FakeRpgProgress.new),
      profileProvider.overrideWith(() => _StubProfileNotifier(profile)),
      profileRepositoryProvider.overrideWithValue(mockRepo),
      authRepositoryProvider.overrideWithValue(mockAuth),
      agePromptDismissalProvider.overrideWith(() => _StubDismissal(dismissed)),
      // Short-circuit `_fireMountAnalytics` before it touches the analytics
      // repository (no Supabase in this test) — userId == null returns
      // early. The age-prompt gating under test is independent of analytics.
      currentUserIdProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return PostSessionScreen(
            params: _params(l10n: l10n, exercises: exercises),
            onContinue: () {},
          );
        },
      ),
    ),
  );
}

/// Long-press fast-forwards the cinematic straight to the summary panel.
Future<void> _skipToSummary(WidgetTester tester) async {
  await tester.pump();
  await tester.longPress(find.byType(PostSessionScreen));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Profile(id: 'fallback'));
    registerFallbackValue(DateTime(2000));
  });

  testWidgets(
    'shows the age prompt on a cardio session when DOB is null and not dismissed',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          profile: const Profile(id: 'user-1'),
          exercises: [_completedCardioEntry()],
        ),
      );
      await _skipToSummary(tester);

      expect(find.byType(AgePromptBanner), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('hides the age prompt when the session had NO cardio', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        profile: const Profile(id: 'user-1'),
        exercises: const [],
      ),
    );
    await _skipToSummary(tester);

    expect(find.byType(AgePromptBanner), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hides the age prompt when the profile already has a DOB', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        profile: Profile(id: 'user-1', dateOfBirth: DateTime(1990, 1, 1)),
        exercises: [_completedCardioEntry()],
      ),
    );
    await _skipToSummary(tester);

    expect(find.byType(AgePromptBanner), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hides the age prompt when already dismissed forever', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        profile: const Profile(id: 'user-1'),
        exercises: [_completedCardioEntry()],
        dismissed: true,
      ),
    );
    await _skipToSummary(tester);

    expect(find.byType(AgePromptBanner), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dismissing the prompt removes it (never shown again)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        profile: const Profile(id: 'user-1'),
        exercises: [_completedCardioEntry()],
      ),
    );
    await _skipToSummary(tester);
    expect(find.byType(AgePromptBanner), findsOneWidget);

    // Tap the dismiss (✕) affordance.
    await tester.tap(
      find.descendant(
        of: find.byType(AgePromptBanner),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    // Banner is gone — the Hive-backed dismissal flipped true and the
    // reactive gate removed it.
    expect(find.byType(AgePromptBanner), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('"Set age" opens the AgeEditorSheet', (tester) async {
    final mockRepo = _MockProfileRepository();
    final mockAuth = _MockAuthRepository();
    when(() => mockAuth.currentUser).thenReturn(null);

    await tester.pumpWidget(
      _harness(
        profile: const Profile(id: 'user-1'),
        exercises: [_completedCardioEntry()],
        repo: mockRepo,
      ),
    );
    await _skipToSummary(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(AgePromptBanner),
        matching: find.text('SET AGE'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AgeEditorSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
