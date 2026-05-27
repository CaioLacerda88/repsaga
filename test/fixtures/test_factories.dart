// Factory classes for generating test data as Map<String, dynamic>.
// These will be replaced with Freezed model factories once models are generated.

class TestExerciseFactory {
  static Map<String, dynamic> create({
    String? id,
    String? name,
    String? muscleGroup,
    String? equipmentType,
    bool? isDefault,
    String? imageStartUrl,
    String? imageEndUrl,
    String? userId,
    String? deletedAt,
    String? createdAt,
    String? description,
    String? formTips,
    String? slug,
    bool? usesBodyweightLoad,
  }) {
    return {
      'id': id ?? 'exercise-001',
      'name': name ?? 'Bench Press',
      'muscle_group': muscleGroup ?? 'chest',
      'equipment_type': equipmentType ?? 'barbell',
      'is_default': isDefault ?? true,
      'image_start_url': imageStartUrl,
      'image_end_url': imageEndUrl,
      'user_id': userId,
      'deleted_at': deletedAt,
      'created_at': createdAt ?? '2026-01-01T00:00:00Z',
      'description': description,
      'form_tips': formTips,
      // Phase 15f: slug is the join key for exercise_translations and is
      // NOT NULL on the table. Default to a stable value for tests; override
      // when a test needs a specific slug.
      'slug': slug ?? 'bench_press',
      // Phase 24c: defaults to FALSE so existing tests built around loaded
      // exercises (bench, squat, deadlift) keep their existing semantics.
      // Override with `true` only for the 20 curated bodyweight exercises
      // (pull-ups, dips, push-ups, pistol squats, etc.).
      'uses_bodyweight_load': usesBodyweightLoad ?? false,
    };
  }
}

class TestWorkoutFactory {
  static Map<String, dynamic> create({
    String? id,
    String? userId,
    String? name,
    String? startedAt,
    String? finishedAt,
    int? durationSeconds,
    bool? isActive,
    String? notes,
    String? createdAt,
  }) {
    return {
      'id': id ?? 'workout-001',
      'user_id': userId ?? 'user-001',
      'name': name ?? 'Push Day',
      'started_at': startedAt ?? '2026-01-01T10:00:00Z',
      'finished_at': finishedAt ?? '2026-01-01T11:00:00Z',
      'duration_seconds': durationSeconds ?? 3600,
      'is_active': isActive ?? false,
      'notes': notes,
      'created_at': createdAt ?? '2026-01-01T10:00:00Z',
    };
  }
}

class TestProfileFactory {
  static Map<String, dynamic> create({
    String? id,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? fitnessLevel,
    String? createdAt,
    double? bodyweightKg,
  }) {
    return {
      'id': id ?? 'user-001',
      'username': username ?? 'testuser',
      'display_name': displayName ?? 'Test User',
      'avatar_url': avatarUrl,
      'fitness_level': fitnessLevel ?? 'beginner',
      'created_at': createdAt ?? '2026-01-01T00:00:00Z',
      // Phase 24c: bodyweight is opt-in. Tests that exercise the
      // bodyweight-load math should pass an explicit value; tests that don't
      // care leave it null so the schema reflects the "user has not entered
      // a bodyweight yet" baseline.
      'bodyweight_kg': bodyweightKg,
    };
  }
}

class TestWorkoutExerciseFactory {
  static Map<String, dynamic> create({
    String? id,
    String? workoutId,
    String? exerciseId,
    int? order,
    int? restSeconds,
  }) {
    return {
      'id': id ?? 'we-001',
      'workout_id': workoutId ?? 'workout-001',
      'exercise_id': exerciseId ?? 'exercise-001',
      'order': order ?? 1,
      'rest_seconds': restSeconds,
    };
  }
}

class TestSetFactory {
  static Map<String, dynamic> create({
    String? id,
    String? workoutExerciseId,
    int? setNumber,
    int? reps,
    double? weight,
    int? rpe,
    String? setType,
    String? notes,
    bool? isCompleted,
    String? createdAt,
  }) {
    return {
      'id': id ?? 'set-001',
      'workout_exercise_id': workoutExerciseId ?? 'we-001',
      'set_number': setNumber ?? 1,
      'reps': reps ?? 10,
      'weight': weight ?? 60.0,
      'rpe': rpe,
      'set_type': setType ?? 'working',
      'notes': notes,
      'is_completed': isCompleted ?? true,
      'created_at': createdAt ?? '2026-01-01T10:05:00Z',
    };
  }
}

class TestRoutineSetConfigFactory {
  static Map<String, dynamic> create({
    int? targetReps,
    double? targetWeight,
    int? restSeconds,
  }) {
    return {
      'target_reps': targetReps ?? 10,
      'target_weight': targetWeight,
      'rest_seconds': restSeconds ?? 90,
    };
  }
}

class TestRoutineExerciseFactory {
  static Map<String, dynamic> create({
    String? exerciseId,
    List<Map<String, dynamic>>? setConfigs,
    Map<String, dynamic>? exercise,
  }) {
    return {
      'exercise_id': exerciseId ?? 'exercise-001',
      'set_configs':
          setConfigs ??
          [
            TestRoutineSetConfigFactory.create(),
            TestRoutineSetConfigFactory.create(),
            TestRoutineSetConfigFactory.create(),
          ],
      // ignore: use_null_aware_elements
      if (exercise != null) 'exercise': exercise,
    };
  }
}

class TestRoutineFactory {
  static Map<String, dynamic> create({
    String? id,
    String? userId,
    String? name,
    bool? isDefault,
    List<Map<String, dynamic>>? exercises,
    String? createdAt,
    String? templateSlug,
  }) {
    return {
      'id': id ?? 'routine-001',
      'user_id': userId,
      'name': name ?? 'Push Day',
      'is_default': isDefault ?? false,
      'exercises':
          exercises ??
          [
            TestRoutineExerciseFactory.create(),
            TestRoutineExerciseFactory.create(exerciseId: 'exercise-002'),
          ],
      'created_at': createdAt ?? '2026-01-01T00:00:00Z',
      'template_slug': templateSlug,
    };
  }
}

class TestPersonalRecordFactory {
  static Map<String, dynamic> create({
    String? id,
    String? userId,
    String? exerciseId,
    String? recordType,
    double? value,
    String? achievedAt,
    String? setId,
  }) {
    return {
      'id': id ?? 'pr-001',
      'user_id': userId ?? 'user-001',
      'exercise_id': exerciseId ?? 'exercise-001',
      'record_type': recordType ?? 'max_weight',
      'value': value ?? 100.0,
      'achieved_at': achievedAt ?? '2026-01-01T10:30:00Z',
      'set_id': setId,
    };
  }
}

class TestActiveWorkoutStateFactory {
  static Map<String, dynamic> create({
    Map<String, dynamic>? workout,
    List<Map<String, dynamic>>? exercises,
  }) {
    return {
      'workout': workout ?? TestWorkoutFactory.create(isActive: true),
      'exercises': exercises ?? [],
    };
  }

  static Map<String, dynamic> createWithExercises({
    Map<String, dynamic>? workout,
    int exerciseCount = 2,
    int setsPerExercise = 3,
  }) {
    final workoutData = workout ?? TestWorkoutFactory.create(isActive: true);

    final exercises = List.generate(exerciseCount, (i) {
      final weId = 'we-${i + 1}';
      final sets = List.generate(setsPerExercise, (j) {
        return TestSetFactory.create(
          id: 'set-$weId-${j + 1}',
          workoutExerciseId: weId,
          setNumber: j + 1,
        );
      });

      return {
        'workout_exercise': TestWorkoutExerciseFactory.create(
          id: weId,
          exerciseId: 'exercise-${i + 1}',
          order: i + 1,
        ),
        'sets': sets,
      };
    });

    return {'workout': workoutData, 'exercises': exercises};
  }
}
