import '../../rpg/models/body_part.dart';

/// Variants for the rotating-priority encouragement nudge above the home
/// ActionHero. Priority order resolved by [selectNudge].
sealed class HomeNudge {
  const HomeNudge();
}

class NudgeCrossBuildClose extends HomeNudge {
  const NudgeCrossBuildClose(this.titleName);

  final String titleName;
}

class NudgeBodyPartTitleClose extends HomeNudge {
  const NudgeBodyPartTitleClose({
    required this.bodyPart,
    required this.titleName,
  });

  final BodyPart bodyPart;
  final String titleName;
}

class NudgeRemainingWorkouts extends HomeNudge {
  const NudgeRemainingWorkouts(this.count);

  final int count;
}

class NudgeStreak extends HomeNudge {
  const NudgeStreak(this.days);

  final int days;
}

class NudgeFirstStep extends HomeNudge {
  const NudgeFirstStep();
}

/// Selects which nudge to surface, in fixed priority order:
///   1. Cross-build title within 1 rank
///   2. Body-part title within 1 rank
///   3. Remaining bucket workouts (count > 0)
///   4. Current streak (days > 0)
///   5. First-step fallback
///
/// All inputs are derived externally; this function does no I/O.
HomeNudge selectNudge({
  required String? crossBuildClose,
  required ({BodyPart bodyPart, String titleName})? bodyPartTitleClose,
  required int remainingBucketWorkouts,
  required int streakDays,
}) {
  if (crossBuildClose != null) {
    return NudgeCrossBuildClose(crossBuildClose);
  }
  if (bodyPartTitleClose != null) {
    return NudgeBodyPartTitleClose(
      bodyPart: bodyPartTitleClose.bodyPart,
      titleName: bodyPartTitleClose.titleName,
    );
  }
  if (remainingBucketWorkouts > 0) {
    return NudgeRemainingWorkouts(remainingBucketWorkouts);
  }
  if (streakDays > 0) {
    return NudgeStreak(streakDays);
  }
  return const NudgeFirstStep();
}
