import 'package:flutter/material.dart';

import '../../../exercises/models/exercise.dart';
import '../../models/active_workout_state.dart';
import 'cardio_entry_card.dart';
import 'exercise_card.dart';
import 'routine_notes_strip.dart';

/// Vertical list of [ExerciseCard]s for the active workout body.
///
/// Pure layout wrapper — defers all per-exercise behavior to [ExerciseCard].
/// Bottom padding accounts for the FAB so the last card can scroll above it.
///
/// When [routineNotes] is non-empty (the workout was started from a routine
/// that has training notes), a quiet [RoutineNotesStrip] is rendered as the
/// FIRST list item (index 0) so it scrolls away with content. For ad-hoc
/// workouts and routines without notes the list is IDENTICAL to before — no
/// strip, no empty slot, no added chrome.
class ExerciseList extends StatelessWidget {
  const ExerciseList({
    required this.exercises,
    required this.reorderMode,
    this.routineNotes,
    super.key,
  });

  final List<ActiveWorkoutExercise> exercises;
  final bool reorderMode;

  /// The source routine's training notes (Q2). Null/blank → no notes strip.
  final String? routineNotes;

  bool get _hasNotes => routineNotes != null && routineNotes!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final notesOffset = _hasNotes ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88, top: 8),
      itemCount: exercises.length + notesOffset,
      itemBuilder: (context, index) {
        if (_hasNotes && index == 0) {
          return RoutineNotesStrip(notes: routineNotes!.trim());
        }
        final exerciseIndex = index - notesOffset;
        final activeExercise = exercises[exerciseIndex];
        // Phase 38b — mixed sessions: cardio entries render the dedicated
        // CardioEntryCard (duration-hero grammar, teal stripe) while
        // strength entries keep the weight×reps ExerciseCard, in the SAME
        // list. The muscle group is the modality discriminator (the
        // notifier seeds `cardioSession` for cardio entries and sets for
        // strength ones).
        final isCardio =
            activeExercise.workoutExercise.exercise?.muscleGroup ==
            MuscleGroup.cardio;
        if (isCardio) {
          return CardioEntryCard(
            activeExercise: activeExercise,
            reorderMode: reorderMode,
            isFirst: exerciseIndex == 0,
            isLast: exerciseIndex == exercises.length - 1,
          );
        }
        return ExerciseCard(
          activeExercise: activeExercise,
          reorderMode: reorderMode,
          isFirst: exerciseIndex == 0,
          isLast: exerciseIndex == exercises.length - 1,
        );
      },
    );
  }
}
