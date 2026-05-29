import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/profile_settings_screen.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../../../../helpers/test_material_app.dart';

class MockAuthRepository extends Mock implements AuthRepository {
  @override
  supabase.User? get currentUser => supabase.User(
    id: 'user-001',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    email: 'test@example.com',
    createdAt: DateTime(2026).toIso8601String(),
  );
}

Widget _buildProfileSettingsScreen({
  required ProfileNotifier Function() profileNotifier,
  int workoutCount = 0,
  int prCount = 0,
}) {
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(profileNotifier),
      authRepositoryProvider.overrideWithValue(MockAuthRepository()),
      workoutCountProvider.overrideWith((ref) => Future.value(workoutCount)),
      prCountProvider.overrideWith((ref) => Future.value(prCount)),
      // PR #283 review (Blocker 3): ProfileAvatar now ref.watches
      // currentUserEmailProvider directly (no defensive try/catch). The
      // real provider hits Supabase.instance which is unset in widget
      // tests — stub the value to match the auth mock's email.
      currentUserEmailProvider.overrideWithValue('test@example.com'),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: ProfileSettingsScreen()),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_stats_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ProfileSettingsScreen stats section (UX-U06)', () {
    testWidgets('shows zero workout count, zero PR count, and member since', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildProfileSettingsScreen(
          profileNotifier: _FakeProfileNotifier.new,
          workoutCount: 0,
          prCount: 0,
        ),
      );

      await tester.pumpAndSettle();

      // Stats labels should be visible.
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('PRs'), findsOneWidget);
      expect(find.text('Member since'), findsOneWidget);

      // Values should show "0" for empty data.
      expect(find.text('0'), findsNWidgets(2));

      // Member since should show the date.
      expect(find.text('Jan 2026'), findsOneWidget);
    });

    testWidgets('shows correct workout count when > 0', (tester) async {
      await tester.pumpWidget(
        _buildProfileSettingsScreen(
          profileNotifier: _FakeProfileNotifier.new,
          workoutCount: 42,
          prCount: 0,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('shows correct PR count when > 0', (tester) async {
      await tester.pumpWidget(
        _buildProfileSettingsScreen(
          profileNotifier: _FakeProfileNotifier.new,
          workoutCount: 0,
          prCount: 7,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('shows "--" for member since while profile is loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildProfileSettingsScreen(
          profileNotifier: _LoadingProfileNotifier.new,
        ),
      );

      // Do NOT call pumpAndSettle — profile stays in loading state.
      await tester.pump();

      expect(find.text('--'), findsOneWidget);
    });
  });
}

class _FakeProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  @override
  Future<Profile?> build() async {
    return Profile(
      id: 'user-001',
      displayName: 'Test User',
      weightUnit: 'kg',
      createdAt: DateTime(2026, 1, 15),
    );
  }

  @override
  Future<void> saveOnboardingProfile({
    required String displayName,
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}

  @override
  Future<void> toggleWeightUnit() async {}
}

/// A profile notifier that stays in the loading state forever.
///
/// Uses a [Completer] that never completes (no pending timer) so that
/// the test framework does not complain about orphan timers.
class _LoadingProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  @override
  Future<Profile?> build() {
    return Completer<Profile?>().future;
  }

  @override
  Future<void> saveOnboardingProfile({
    required String displayName,
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}

  @override
  Future<void> toggleWeightUnit() async {}
}
