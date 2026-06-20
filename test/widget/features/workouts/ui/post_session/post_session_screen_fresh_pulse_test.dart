/// Phase Vitality PR 2 — fresh-today pulse recorded on [PostSessionScreen]
/// mount.
///
/// **Why this test exists.** The fresh-today pulse write was moved OFF the
/// finish critical path and onto the post-session screen's mount to fix a
/// web-IndexedDB finish-path hang (cousin of cluster `hive-testwidgets`):
/// firing the Hive/IndexedDB write — plus the provider's first-read
/// `sweepExpired()` — in the same synchronous tick that scheduled the
/// finish→post-session post-frame navigation starved the post-frame callback
/// on web, so finish hung on the spinner and never navigated. The write now
/// lives in [PostSessionScreen]'s `initState` post-frame callback, where it
/// can never block navigation.
///
/// This pins the OTHER half of that fix: the feature must still work. The
/// pulse must end up recorded for the body parts trained this session so the
/// saga rows read "fresh today" for 24h. We assert the user-perceptible
/// contract — `isPulsing` is true for trained body parts after the screen
/// mounts, and false for body parts that earned no XP — using a real
/// in-memory storage (not a no-op spy), so the actual `recordChargedBatch`
/// behavior is exercised end to end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/rpg/data/vitality_fresh_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/rpg/providers/vitality_fresh_pulse_provider.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_controller.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_screen.dart';
import 'package:repsaga/l10n/app_localizations.dart';

PostSessionParams _params({
  required AppLocalizations l10n,
  required Map<BodyPart, int> bpXpDeltas,
}) {
  return PostSessionParams(
    queueResult: const CelebrationQueueResult(queue: []),
    prResult: null,
    exerciseNames: const {},
    totalXpEarned: 120,
    bpXpDeltas: bpXpDeltas,
    bpProgressFractionPre: const {},
    bpRankBefore: const {},
    bpVitalityBefore: const {},
    bpFirstAwakening: const {},
    priorFinishedWorkoutCount: 4,
    durationMinutes: 30,
    setsCount: 12,
    tonnageTons: 4.2,
    l10n: l10n,
  );
}

Widget _harness({
  required Map<BodyPart, int> bpXpDeltas,
  required VitalityFreshPulseLocalStorage storage,
}) {
  return ProviderScope(
    overrides: [
      rpgProgressProvider.overrideWith(
        () => _FakeRpgProgress(RpgProgressSnapshot.empty),
      ),
      currentUserIdProvider.overrideWithValue('user-pulse-001'),
      // Real in-memory storage — exercises the actual recordChargedBatch /
      // isPulsing behavior the saga row depends on.
      vitalityFreshPulseLocalStorageProvider.overrideWithValue(storage),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return PostSessionScreen(
            params: _params(l10n: l10n, bpXpDeltas: bpXpDeltas),
            onContinue: () {},
          );
        },
      ),
    ),
  );
}

void main() {
  group('PostSessionScreen — fresh-today pulse on mount', () {
    testWidgets(
      'records a fresh pulse for every trained body part so the saga row '
      'reads "fresh today"',
      (tester) async {
        final storage = _InMemoryFreshPulseStorage();

        // Pre-condition: nothing is pulsing before the screen mounts.
        expect(storage.isPulsing(BodyPart.chest), isFalse);
        expect(storage.isPulsing(BodyPart.back), isFalse);

        await tester.pumpWidget(
          _harness(
            bpXpDeltas: const {BodyPart.chest: 80, BodyPart.back: 40},
            storage: storage,
          ),
        );
        // Drive the initState post-frame callback + the fire-and-forget write.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Behavior: the two body parts that earned XP now read "fresh today".
        expect(
          storage.isPulsing(BodyPart.chest),
          isTrue,
          reason: 'chest earned XP this session → its saga row pulses fresh',
        );
        expect(
          storage.isPulsing(BodyPart.back),
          isTrue,
          reason: 'back earned XP this session → its saga row pulses fresh',
        );
        // A body part the user did not train must NOT pulse.
        expect(
          storage.isPulsing(BodyPart.legs),
          isFalse,
          reason: 'legs earned no XP → its saga row stays steady-state',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('records nothing when no body part earned XP (empty deltas)', (
      tester,
    ) async {
      final storage = _InMemoryFreshPulseStorage();

      await tester.pumpWidget(_harness(bpXpDeltas: const {}, storage: storage));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // No deltas → no writes → no body part pulses (cardio-only / no-XP
      // sessions don't synthesize a phantom pulse).
      expect(storage.recordedBatches, isEmpty);
      for (final bp in BodyPart.values) {
        expect(storage.isPulsing(bp), isFalse);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// Real-behavior in-memory fresh-pulse storage. Mirrors
/// [VitalityFreshPulseLocalStorage]'s 24h window semantics without opening a
/// Hive box, so the test exercises the genuine record→isPulsing round-trip
/// the saga row reads against. `recordedBatches` lets the empty-deltas test
/// assert the screen does not even attempt a write.
class _InMemoryFreshPulseStorage implements VitalityFreshPulseLocalStorage {
  final Map<BodyPart, DateTime> _entries = {};
  final List<List<BodyPart>> recordedBatches = [];

  @override
  bool isPulsing(BodyPart bodyPart, {DateTime? now}) {
    final at = _entries[bodyPart];
    if (at == null) return false;
    final expiresAt = at.add(VitalityFreshPulseLocalStorage.pulseDuration);
    return (now ?? DateTime.now()).isBefore(expiresAt);
  }

  @override
  Future<void> recordCharged(BodyPart bodyPart, {DateTime? at}) async {
    _entries[bodyPart] = at ?? DateTime.now();
  }

  @override
  Future<void> recordChargedBatch(
    Iterable<BodyPart> bodyParts, {
    DateTime? at,
  }) async {
    final list = bodyParts.toList();
    recordedBatches.add(list);
    final t = at ?? DateTime.now();
    for (final bp in list) {
      await recordCharged(bp, at: t);
    }
  }

  @override
  Future<void> sweepExpired({DateTime? now}) async {
    final ref = now ?? DateTime.now();
    _entries.removeWhere(
      (_, at) =>
          ref.isAfter(at.add(VitalityFreshPulseLocalStorage.pulseDuration)),
    );
  }
}

class _FakeRpgProgress extends RpgProgressNotifier {
  _FakeRpgProgress(this._snapshot);
  final RpgProgressSnapshot _snapshot;
  @override
  Future<RpgProgressSnapshot> build() async => _snapshot;
}
