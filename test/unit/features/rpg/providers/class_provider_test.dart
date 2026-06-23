/// Unit tests for [characterClassProvider] (Phase 18e, spec §18 acceptance #8).
///
/// The provider is a thin `Provider<CharacterClass?>` that watches
/// [rpgProgressProvider] and feeds the snapshot's per-body-part rank map
/// into [`ClassResolver.resolve`]. The contract this test pins:
///
///   1. **Loading** → null (badge falls back to placeholder copy).
///   2. **Empty snapshot** (day-0 user) → [CharacterClass.initiate] via the
///      resolver's rank-1 floor.
///   3. **Class label updates immediately on rank changes** — bullet 8 of
///      spec §18. A snapshot transition that crosses the resolver's
///      Initiate floor (max < 5) must flip the provider's value in the same
///      rebuild cycle. The provider has no caching of its own; it's a
///      pass-through computation over the AsyncNotifier's value.
///
/// **Why test the provider, not the resolver:** the resolver is unit-tested
/// in `class_resolver_test.dart`. This file pins the wiring — that the
/// provider correctly projects the snapshot onto the resolver's input shape
/// and propagates AsyncValue states. A regression here would mean the saga
/// screen's class badge stops reacting to rank-ups even though the resolver
/// still works in isolation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/data/rpg_repository.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/providers/class_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';

/// Build an [RpgProgressSnapshot] for the six active body parts with named
/// rank overrides. Defaults to rank 1 — matches the resolver's missing-row
/// projection contract.
RpgProgressSnapshot _snapshot({
  int chest = 1,
  int back = 1,
  int legs = 1,
  int shoulders = 1,
  int arms = 1,
  int core = 1,
}) {
  BodyPartProgress row(BodyPart bp, int rank) => BodyPartProgress(
    userId: 'u1',
    bodyPart: bp,
    totalXp: rank * 100.0,
    rank: rank,
    vitalityEwma: 0,
    vitalityPeak: 0,
    vitalityRefPeak: 0,
    lastEventAt: null,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  final rows = <BodyPart, BodyPartProgress>{
    BodyPart.chest: row(BodyPart.chest, chest),
    BodyPart.back: row(BodyPart.back, back),
    BodyPart.legs: row(BodyPart.legs, legs),
    BodyPart.shoulders: row(BodyPart.shoulders, shoulders),
    BodyPart.arms: row(BodyPart.arms, arms),
    BodyPart.core: row(BodyPart.core, core),
  };
  final maxRank = rows.values
      .map((r) => r.rank)
      .reduce((a, b) => a > b ? a : b);
  final minRank = rows.values
      .map((r) => r.rank)
      .reduce((a, b) => a < b ? a : b);
  return RpgProgressSnapshot(
    byBodyPart: rows,
    characterState: CharacterState(
      userId: 'u1',
      characterLevel: 1,
      maxRank: maxRank,
      minRank: minRank,
      lifetimeXp: rows.values.fold<double>(0, (s, r) => s + r.totalXp),
    ),
  );
}

/// Mutable fake AsyncNotifier so we can simulate a snapshot transition
/// (pre-finish → post-finish) without touching Supabase. The notifier's
/// `build()` returns a Future for the initial snapshot; subsequent
/// transitions invoke `state = AsyncData(...)` directly.
class _MutableRpgProgressNotifier extends RpgProgressNotifier {
  _MutableRpgProgressNotifier(this._initial);
  final RpgProgressSnapshot _initial;

  @override
  Future<RpgProgressSnapshot> build() async => _initial;

  /// Simulate a `record_set_xp` server response by swapping the AsyncValue
  /// for fresh state. Same surface the live notifier exposes via
  /// `refreshAfterSave`.
  void emit(RpgProgressSnapshot next) {
    state = AsyncData(next);
  }
}

void main() {
  group('characterClassProvider', () {
    test('AsyncLoading → null (placeholder fallback)', () async {
      // The default RpgProgressNotifier build() resolves asynchronously;
      // before the future completes, watchers see AsyncLoading. The
      // provider must surface null so the badge renders the day-1
      // placeholder copy ("The iron will name you.") rather than crashing
      // on a missing class.
      final container = ProviderContainer(
        overrides: [
          rpgProgressProvider.overrideWith(() => _SlowNotifier(_snapshot())),
        ],
      );
      addTearDown(container.dispose);

      // Read before the future resolves — the synchronous provider
      // returns null while upstream is loading.
      expect(container.read(characterClassProvider), isNull);

      // After the future resolves, the value flips to Initiate.
      await container.read(rpgProgressProvider.future);
      expect(container.read(characterClassProvider), CharacterClass.initiate);
    });

    test('day-0 snapshot (every rank 1) → Initiate', () async {
      // Empty (day-0) state hits the resolver's rank-1 floor.
      final container = ProviderContainer(
        overrides: [
          rpgProgressProvider.overrideWith(
            () => _MutableRpgProgressNotifier(_snapshot()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(rpgProgressProvider.future);
      expect(container.read(characterClassProvider), CharacterClass.initiate);
    });

    test('rank delta crosses Initiate floor → class flips on the same rebuild '
        '(bullet 8)', () async {
      // Pre-state: every rank at 4 → still Initiate (resolver floor max < 5).
      // Post-state: chest crosses to rank 5; with chest=5 and others at 4,
      // dominant is chest → Bulwark. (Spread (5-4)/5=0.20 — Ascendant
      // would fire if min >= 5, but min == 4 so the dominant lookup wins.)
      // The provider must surface the new class after a single emit().
      final initial = _snapshot(
        chest: 4,
        back: 4,
        legs: 4,
        shoulders: 4,
        arms: 4,
        core: 4,
      );
      final notifier = _MutableRpgProgressNotifier(initial);
      final container = ProviderContainer(
        overrides: [rpgProgressProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);

      await container.read(rpgProgressProvider.future);
      expect(container.read(characterClassProvider), CharacterClass.initiate);

      // Simulate the post-workout snapshot push.
      notifier.emit(
        _snapshot(chest: 5, back: 4, legs: 4, shoulders: 4, arms: 4, core: 4),
      );

      expect(container.read(characterClassProvider), CharacterClass.bulwark);
    });

    test('rank delta into balanced distribution at min >= 5 → Ascendant '
        '(precedence over dominant lookup)', () async {
      // Boundary: min rank at exactly 5, spread 0% → Ascendant overrides
      // any dominant lookup. The provider must respect resolver precedence.
      final initial = _snapshot(
        chest: 4,
        back: 4,
        legs: 4,
        shoulders: 4,
        arms: 4,
        core: 4,
      );
      final notifier = _MutableRpgProgressNotifier(initial);
      final container = ProviderContainer(
        overrides: [rpgProgressProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);

      await container.read(rpgProgressProvider.future);
      expect(container.read(characterClassProvider), CharacterClass.initiate);

      notifier.emit(
        _snapshot(chest: 5, back: 5, legs: 5, shoulders: 5, arms: 5, core: 5),
      );

      expect(container.read(characterClassProvider), CharacterClass.ascendant);
    });

    test(
      'multiple rank changes in sequence stay in sync with the resolver',
      () async {
        // Walk a synthetic user through three transitions, asserting the
        // class at each step. This is the vital "label updates immediately"
        // guarantee from spec §18 bullet 8.
        final notifier = _MutableRpgProgressNotifier(_snapshot());
        final container = ProviderContainer(
          overrides: [rpgProgressProvider.overrideWith(() => notifier)],
        );
        addTearDown(container.dispose);

        await container.read(rpgProgressProvider.future);
        expect(container.read(characterClassProvider), CharacterClass.initiate);

        // Transition 1: arms-dominant → Berserker.
        notifier.emit(_snapshot(arms: 30, chest: 10));
        expect(
          container.read(characterClassProvider),
          CharacterClass.berserker,
        );

        // Transition 2: legs-dominant → Pathfinder.
        notifier.emit(_snapshot(legs: 30, arms: 10));
        expect(
          container.read(characterClassProvider),
          CharacterClass.pathfinder,
        );

        // Transition 3: balance back into Ascendant territory.
        notifier.emit(
          _snapshot(
            chest: 30,
            back: 30,
            legs: 30,
            shoulders: 30,
            arms: 30,
            core: 30,
          ),
        );
        expect(
          container.read(characterClassProvider),
          CharacterClass.ascendant,
        );
      },
    );

    test('AsyncError → null (graceful fallback, not a crash)', () async {
      // Network blip: rpgProgressProvider lands in AsyncError. The
      // class badge must render the placeholder rather than blocking the
      // saga screen on an unrecoverable state.
      final container = ProviderContainer(
        overrides: [
          rpgProgressProvider.overrideWith(() => _ErroringNotifier()),
        ],
      );
      addTearDown(container.dispose);

      // Wait for the future to surface the error.
      await expectLater(
        container.read(rpgProgressProvider.future),
        throwsA(isA<StateError>()),
      );

      expect(container.read(characterClassProvider), isNull);
    });
  });
}

/// Notifier that resolves on a microtask delay so we can exercise the
/// AsyncLoading → AsyncData transition in a single test.
class _SlowNotifier extends RpgProgressNotifier {
  _SlowNotifier(this._snapshot);
  final RpgProgressSnapshot _snapshot;

  @override
  Future<RpgProgressSnapshot> build() async {
    await Future<void>.microtask(() {});
    return _snapshot;
  }
}

/// Notifier that fails the initial fetch so we can pin the AsyncError →
/// null contract.
class _ErroringNotifier extends RpgProgressNotifier {
  @override
  Future<RpgProgressSnapshot> build() async {
    throw StateError('simulated network error');
  }
}
