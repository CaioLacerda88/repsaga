/// Pins the [analyticsRepositoryProvider] fault-tolerance contract.
///
/// **Why this test exists (PR #277 review fix):** the original PR wrapped
/// every call site in try/catch because the provider would throw when
/// `Supabase.instance.client` was unavailable (test harnesses without an
/// override, pre-bootstrap reads). The reviewer flagged that as the wrong
/// layer — the "analytics never breaks user flow" contract belongs here,
/// not duplicated at each emit site.
///
/// This test pins:
///   1. Reading the provider WITHOUT a Supabase instance returns a
///      repository whose [AnalyticsRepository.insertEvent] is a silent
///      no-op (does not throw).
///   2. If a future emit site forgets the call-site try/catch, the
///      worst-case behavior is "event silently dropped" — never a
///      thrown exception that propagates into the caller's path.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';

void main() {
  group('analyticsRepositoryProvider', () {
    test('returns a fault-tolerant repo when Supabase.instance.client is '
        'unavailable (no exception, no-op insert)', () async {
      // The default test environment has NOT called Supabase.initialize,
      // so `Supabase.instance.client` will throw. The provider must
      // catch that throw and hand back a no-op repository.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final AnalyticsRepository repo = container.read(
        analyticsRepositoryProvider,
      );

      // Inserting must complete without throwing — that's the contract
      // every call site now relies on. The original PR had to wrap each
      // emit in try/catch because this throw escaped; after the fix
      // (single-point fallback in the provider), call sites are clean.
      await expectLater(
        repo.insertEvent(
          userId: 'user-x',
          event: const AnalyticsEvent.firstRankUp(
            bodyPart: 'chest',
            newRank: 2,
          ),
          platform: 'test',
          appVersion: '0.0.0',
        ),
        completes,
      );
    });

    test('multiple reads return a consistently usable repository', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final repoA = container.read(analyticsRepositoryProvider);
      final repoB = container.read(analyticsRepositoryProvider);

      // Provider caching means both reads hand back the same instance.
      expect(identical(repoA, repoB), isTrue);

      // And it remains a no-op across calls.
      await expectLater(
        repoA.insertEvent(
          userId: 'u',
          event: const AnalyticsEvent.firstRankUp(bodyPart: 'back', newRank: 1),
          platform: null,
          appVersion: null,
        ),
        completes,
      );
    });
  });
}
