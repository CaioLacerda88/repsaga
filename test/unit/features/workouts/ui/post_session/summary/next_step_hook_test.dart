import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/next_step_hook.dart';

void main() {
  group('NextStepHookResolver.resolve', () {
    test('level-up wins over a PR detail hook', () {
      final hook = NextStepHookResolver.resolve(
        hasLevelUp: true,
        prDetail: const PrDetailHook(
          exerciseName: 'Supino',
          weightKg: 95,
          reps: 5,
          improvementKg: 5,
        ),
        dominantBodyPart: BodyPart.chest,
        dominantXpToNextRank: 240,
        dominantNextRank: 18,
        ranksToNextLevel: 4,
        nextLevel: 24,
      );
      expect(hook, isA<NextLevelHook>());
      expect((hook! as NextLevelHook).ranksToNextLevel, 4);
      expect((hook as NextLevelHook).nextLevel, 24);
    });

    test('PR detail wins over next-rank hook (no level-up)', () {
      final hook = NextStepHookResolver.resolve(
        hasLevelUp: false,
        prDetail: const PrDetailHook(
          exerciseName: 'Supino',
          weightKg: 95,
          reps: 5,
          improvementKg: 5,
        ),
        dominantBodyPart: BodyPart.chest,
        dominantXpToNextRank: 240,
        dominantNextRank: 18,
        ranksToNextLevel: null,
        nextLevel: null,
      );
      expect(hook, isA<PrDetailHook>());
    });

    test('next-rank hook when no level-up and no PR', () {
      final hook = NextStepHookResolver.resolve(
        hasLevelUp: false,
        prDetail: null,
        dominantBodyPart: BodyPart.chest,
        dominantXpToNextRank: 240,
        dominantNextRank: 18,
        ranksToNextLevel: null,
        nextLevel: null,
      );
      expect(hook, isA<NextRankHook>());
      final nr = hook! as NextRankHook;
      expect(nr.bodyPart, BodyPart.chest);
      expect(nr.xpToNextRank, 240);
      expect(nr.nextRank, 18);
    });

    test(
      'null when dominantXpToNextRank is zero (max-rank user has no next step)',
      () {
        final hook = NextStepHookResolver.resolve(
          hasLevelUp: false,
          prDetail: null,
          dominantBodyPart: BodyPart.chest,
          dominantXpToNextRank: 0,
          dominantNextRank: 99,
          ranksToNextLevel: null,
          nextLevel: null,
        );
        expect(hook, isNull);
      },
    );

    test('null when level-up flag set but ranksToNextLevel is null', () {
      // Defensive: caller must supply both ranksToNextLevel + nextLevel for
      // the NextLevelHook to fire. Without them, fall through to PR/next-rank.
      final hook = NextStepHookResolver.resolve(
        hasLevelUp: true,
        prDetail: null,
        dominantBodyPart: BodyPart.chest,
        dominantXpToNextRank: 240,
        dominantNextRank: 18,
        ranksToNextLevel: null,
        nextLevel: null,
      );
      // Fall-through path → NextRankHook.
      expect(hook, isA<NextRankHook>());
    });

    test('null when no inputs match', () {
      final hook = NextStepHookResolver.resolve(
        hasLevelUp: false,
        prDetail: null,
        dominantBodyPart: null,
        dominantXpToNextRank: null,
        dominantNextRank: null,
        ranksToNextLevel: null,
        nextLevel: null,
      );
      expect(hook, isNull);
    });
  });
}
