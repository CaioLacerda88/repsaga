import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../models/routine.dart';
import '../routine_providers.dart';

/// Loads and manages the list of routines for the current user.
class RoutineListNotifier extends AsyncNotifier<List<Routine>> {
  @override
  FutureOr<List<Routine>> build() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return [];
    final repo = ref.watch(routineRepositoryProvider);
    final locale = ref.watch(localeProvider).languageCode;
    return repo.getRoutines(userId: userId, locale: locale);
  }

  /// Create a new routine and refresh the list.
  Future<void> createRoutine({
    required String name,
    required List<RoutineExercise> exercises,
    String? notes,
  }) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return;
    final repo = ref.read(routineRepositoryProvider);
    final locale = ref.read(localeProvider).languageCode;
    await repo.createRoutine(
      userId: userId,
      locale: locale,
      name: name,
      exercises: exercises,
      notes: notes,
    );
    ref.invalidateSelf();
  }

  /// Update an existing routine and refresh the list.
  Future<void> updateRoutine({
    required String id,
    required String name,
    required List<RoutineExercise> exercises,
    String? notes,
  }) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return;
    final repo = ref.read(routineRepositoryProvider);
    final locale = ref.read(localeProvider).languageCode;
    await repo.updateRoutine(
      id: id,
      userId: userId,
      locale: locale,
      name: name,
      exercises: exercises,
      notes: notes,
    );
    ref.invalidateSelf();
  }

  /// Duplicate a routine as a user-owned copy and refresh the list.
  /// Returns the newly created [Routine] so callers can navigate to edit it,
  /// or `null` if the user is not logged in or the operation fails.
  Future<Routine?> duplicateRoutine(Routine source) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return null;
    try {
      final repo = ref.read(routineRepositoryProvider);
      final locale = ref.read(localeProvider).languageCode;
      final copy = await repo.createRoutine(
        userId: userId,
        locale: locale,
        name: '${source.name} (Copy)',
        exercises: source.exercises,
        notes: source.notes,
      );
      ref.invalidateSelf();
      return copy;
    } catch (_) {
      return null;
    }
  }

  /// Delete a routine and refresh the list.
  Future<void> deleteRoutine(String id) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return;
    final repo = ref.read(routineRepositoryProvider);
    await repo.deleteRoutine(id, userId: userId);
    ref.invalidateSelf();
  }

  /// Force-refresh from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

/// Provides the paginated list of routines.
final routineListProvider =
    AsyncNotifierProvider<RoutineListNotifier, List<Routine>>(
      RoutineListNotifier.new,
    );
