import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/profile_settings_screen.dart';
import 'package:repsaga/features/profile/ui/widgets/profile_avatar.dart';
import 'package:repsaga/features/workouts/data/share_service.dart';
import 'package:repsaga/features/workouts/providers/share_controller.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../helpers/test_material_app.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUser extends Mock implements User {}

class MockProfileNotifier extends AsyncNotifier<Profile?>
    with Mock
    implements ProfileNotifier {
  MockProfileNotifier(this._profile);
  final Profile? _profile;

  @override
  Future<Profile?> build() async => _profile;

  @override
  Future<void> toggleWeightUnit() async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}
}

Widget buildTestWidget({
  Profile? profile,
  String? email,
  MockAuthRepository? authRepository,
}) {
  final mockAuth = authRepository ?? MockAuthRepository();
  if (authRepository == null) {
    final mockUser = email != null ? (MockUser()..setEmail(email)) : null;
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockAuth.signOut()).thenAnswer((_) async {});
  }

  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => MockProfileNotifier(profile)),
      authRepositoryProvider.overrideWithValue(mockAuth),
      // BUG-040: ProfileSettingsScreen → workoutCountProvider now listens to
      // authStateProvider for cross-user invalidation. Without this stub
      // the real provider body subscribes to Supabase + arms a 5s fallback
      // timer that prevents the test from settling. An empty stream is
      // safe — the listener only acts on emissions, and these tests don't
      // exercise sign-out/sign-in flows.
      authStateProvider.overrideWith((ref) => const Stream<AuthState>.empty()),
      // PR #283 review (Blocker 3): the avatar widget now reads
      // currentUserEmailProvider directly via ref.watch (no defensive
      // try/catch). The provider's lambda hits Supabase.instance which
      // is unset in widget tests — stub it explicitly with the
      // mocked-out email value.
      currentUserEmailProvider.overrideWithValue(email),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const ProfileSettingsScreen(),
    ),
  );
}

extension _MockUserEmail on MockUser {
  void setEmail(String email) {
    when(() => this.email).thenReturn(email);
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    // ProfileSettingsScreen watches crashReportsEnabledProvider which reads the
    // user_prefs Hive box. Open it on a temp path so tests don't crash.
    tempDir = await Directory.systemTemp.createTemp('profile_widget_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ProfileSettingsScreen', () {
    testWidgets('shows display name when profile has displayName', (
      tester,
    ) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'John Doe',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('shows fallback "Gym User" when displayName is null', (
      tester,
    ) async {
      const profile = Profile(id: 'user-1', weightUnit: 'kg');

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      expect(find.text('Gym User'), findsOneWidget);
    });

    testWidgets('shows "Gym User" when profile is null', (tester) async {
      await tester.pumpWidget(buildTestWidget(profile: null));
      await tester.pump();

      expect(find.text('Gym User'), findsOneWidget);
    });

    testWidgets('shows email from auth repository', (tester) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(
        buildTestWidget(profile: profile, email: 'jane@example.com'),
      );
      await tester.pump();

      expect(find.text('jane@example.com'), findsOneWidget);
    });

    testWidgets('shows weight unit segmented button', (tester) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
      expect(find.text('lbs'), findsOneWidget);
    });

    testWidgets('kg is selected when weightUnit is kg', (tester) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(button.selected, {'kg'});
    });

    testWidgets('lbs is selected when weightUnit is lbs', (tester) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'lbs',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(button.selected, {'lbs'});
    });

    testWidgets('shows logout button', (tester) async {
      await tester.pumpWidget(buildTestWidget(profile: null));
      await tester.pump();

      expect(find.text('Log Out'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('logout button shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget(profile: null));
      await tester.pump();

      await tester.ensureVisible(find.text('Log Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to log out?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancelling logout dialog does not call signOut', (
      tester,
    ) async {
      final mockAuth = MockAuthRepository();
      when(() => mockAuth.currentUser).thenReturn(null);
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await tester.pumpWidget(
        buildTestWidget(profile: null, authRepository: mockAuth),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Log Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => mockAuth.signOut());
    });

    testWidgets('IdentityCard renders the ProfileAvatar surface', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(profile: null));
      await tester.pump();

      // Contract pin: the IdentityCard wires exactly one ProfileAvatar.
      // Gradient color + monogram derivation are covered by
      // `profile_avatar_test.dart`.
      expect(find.byType(ProfileAvatar), findsOneWidget);
    });

    testWidgets(
      'tapping the lbs segment calls toggleWeightUnit on the notifier',
      (tester) async {
        var toggleCalled = false;

        // Use a notifier that records the call.
        final notifier = _TrackingProfileNotifier(
          profile: const Profile(
            id: 'user-1',
            displayName: 'Jane',
            weightUnit: 'kg',
          ),
          onToggle: () => toggleCalled = true,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(() => notifier),
              authRepositoryProvider.overrideWithValue(
                MockAuthRepository()
                  ..setCurrentUser(null)
                  ..setSignOut(),
              ),
              // BUG-040: stub authStateProvider so workoutCountProvider's
              // listener doesn't subscribe to the real Supabase auth
              // stream (which would arm a 5s pending timer).
              authStateProvider.overrideWith(
                (ref) => const Stream<AuthState>.empty(),
              ),
              // PR #283 review (Blocker 3): ProfileAvatar now ref.watches
              // currentUserEmailProvider directly.
              currentUserEmailProvider.overrideWithValue(null),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ProfileSettingsScreen(),
            ),
          ),
        );
        await tester.pump();

        // Tap the 'lbs' segment to trigger toggleWeightUnit.
        await tester.tap(find.text('lbs'));
        await tester.pump();

        expect(toggleCalled, isTrue);
      },
    );

    testWidgets(
      'tapping the kg segment calls toggleWeightUnit when lbs is active',
      (tester) async {
        var toggleCalled = false;

        final notifier = _TrackingProfileNotifier(
          profile: const Profile(id: 'user-1', weightUnit: 'lbs'),
          onToggle: () => toggleCalled = true,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(() => notifier),
              authRepositoryProvider.overrideWithValue(
                MockAuthRepository()
                  ..setCurrentUser(null)
                  ..setSignOut(),
              ),
              // BUG-040: stub authStateProvider so workoutCountProvider's
              // listener doesn't subscribe to the real Supabase auth
              // stream (which would arm a 5s pending timer).
              authStateProvider.overrideWith(
                (ref) => const Stream<AuthState>.empty(),
              ),
              // PR #283 review (Blocker 3): ProfileAvatar now ref.watches
              // currentUserEmailProvider directly.
              currentUserEmailProvider.overrideWithValue(null),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ProfileSettingsScreen(),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('kg'));
        await tester.pump();

        expect(toggleCalled, isTrue);
      },
    );

    testWidgets('shows LinearProgressIndicator while profile is loading', (
      tester,
    ) async {
      // Use a notifier that stays in loading state indefinitely.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => _LoadingProfileNotifier()),
            authRepositoryProvider.overrideWithValue(
              MockAuthRepository()
                ..setCurrentUser(null)
                ..setSignOut(),
            ),
            // BUG-040: stub authStateProvider so workoutCountProvider's
            // listener doesn't subscribe to the real Supabase auth stream
            // (which would arm a 5s pending timer).
            authStateProvider.overrideWith(
              (ref) => const Stream<AuthState>.empty(),
            ),
            // PR #283 review (Blocker 3): ProfileAvatar now ref.watches
            // currentUserEmailProvider directly.
            currentUserEmailProvider.overrideWithValue(null),
          ],
          child: TestMaterialApp(
            theme: AppTheme.dark,
            home: const ProfileSettingsScreen(),
          ),
        ),
      );
      // Only pump once so we catch the loading frame.
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Manage Data row', (tester) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      expect(find.text('DATA MANAGEMENT'), findsOneWidget);
      expect(find.text('Manage Data'), findsOneWidget);
    });

    testWidgets('Manage Data row has chevron icon', (tester) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      // Body Weight (Phase 24c), Gender (Legal PR 2), Weekly Goal, Language,
      // Manage Data, Privacy Policy, and Terms of Service rows each render a
      // chevron icon.
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(7));
    });

    // PO-039: The display name must show an edit icon and be tappable, opening
    // an edit dialog when tapped.
    testWidgets(
      'PO-039: identity card shows an edit icon next to the display name',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          displayName: 'John Doe',
          weightUnit: 'kg',
        );

        await tester.pumpWidget(buildTestWidget(profile: profile));
        await tester.pump();

        // An edit icon must be visible alongside the name.
        expect(find.byIcon(Icons.edit), findsOneWidget);
      },
    );

    testWidgets(
      'PO-039: tapping the display name opens the Edit Display Name dialog',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          displayName: 'John Doe',
          weightUnit: 'kg',
        );

        final mockAuth = MockAuthRepository();
        when(() => mockAuth.currentUser).thenReturn(null);
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(() => MockProfileNotifier(profile)),
              authRepositoryProvider.overrideWithValue(mockAuth),
              // BUG-040: stub authStateProvider so workoutCountProvider's
              // listener doesn't subscribe to the real Supabase auth
              // stream (which would arm a 5s pending timer).
              authStateProvider.overrideWith(
                (ref) => const Stream<AuthState>.empty(),
              ),
              // PR #283 review (Blocker 3): ProfileAvatar now ref.watches
              // currentUserEmailProvider directly.
              currentUserEmailProvider.overrideWithValue(null),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ProfileSettingsScreen(),
            ),
          ),
        );
        await tester.pump();

        // Tap the display name (wrapped in a GestureDetector).
        await tester.tap(find.text('John Doe'));
        await tester.pumpAndSettle();

        // The edit dialog must appear.
        expect(find.text('Edit Display Name'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
      },
    );

    testWidgets(
      'PO-039: edit dialog is pre-populated with the current display name',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          displayName: 'Jane Smith',
          weightUnit: 'kg',
        );

        final mockAuth = MockAuthRepository();
        when(() => mockAuth.currentUser).thenReturn(null);
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(() => MockProfileNotifier(profile)),
              authRepositoryProvider.overrideWithValue(mockAuth),
              // BUG-040: stub authStateProvider so workoutCountProvider's
              // listener doesn't subscribe to the real Supabase auth
              // stream (which would arm a 5s pending timer).
              authStateProvider.overrideWith(
                (ref) => const Stream<AuthState>.empty(),
              ),
              // PR #283 review (Blocker 3): ProfileAvatar now ref.watches
              // currentUserEmailProvider directly.
              currentUserEmailProvider.overrideWithValue(null),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ProfileSettingsScreen(),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Jane Smith'));
        await tester.pumpAndSettle();

        // The TextField inside the dialog must be pre-filled with the name.
        final textField = tester.widget<TextField>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
        );
        expect(textField.controller?.text, 'Jane Smith');
      },
    );

    testWidgets(
      'shows LEGAL section with Privacy Policy and Terms of Service',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          displayName: 'Jane',
          weightUnit: 'kg',
        );

        await tester.pumpWidget(buildTestWidget(profile: profile));
        await tester.pump();

        expect(find.text('LEGAL'), findsOneWidget);
        expect(find.text('Privacy Policy'), findsOneWidget);
        expect(find.text('Terms of Service'), findsOneWidget);
        expect(find.byIcon(Icons.privacy_tip_outlined), findsOneWidget);
        expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      },
    );

    testWidgets('Privacy Policy legal tile is tappable', (tester) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      // Ensure the tile exists and is wired up to an InkWell (tappable).
      expect(
        find.ancestor(
          of: find.text('Privacy Policy'),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Terms of Service legal tile is tappable', (tester) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      expect(
        find.ancestor(
          of: find.text('Terms of Service'),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // Crash-reports toggle (PR 5 — observability)
    // -----------------------------------------------------------------------

    testWidgets(
      'shows PRIVACY section header and "Send crash reports" switch',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          displayName: 'Jane',
          weightUnit: 'kg',
        );

        await tester.pumpWidget(buildTestWidget(profile: profile));
        await tester.pump();

        expect(find.text('PRIVACY'), findsOneWidget);
        expect(find.text('Send crash reports'), findsOneWidget);
        // Legal PR 2 — the PRIVACY section now hosts three toggles:
        // CrashReports + Analytics + BodyweightConsent.
        expect(find.byType(SwitchListTile), findsNWidgets(3));
        expect(find.text('Send usage analytics'), findsOneWidget);
        expect(find.text('Body weight tracking'), findsOneWidget);
      },
    );

    testWidgets(
      '"Send crash reports" switch is ON by default (no persisted value)',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          displayName: 'Jane',
          weightUnit: 'kg',
        );

        await tester.pumpWidget(buildTestWidget(profile: profile));
        await tester.pump();

        // Locate the crash-reports tile specifically (Legal PR 2 added two
        // sibling tiles to the PRIVACY section).
        final switchTile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Send crash reports'),
        );
        expect(switchTile.value, isTrue);
      },
    );

    // -----------------------------------------------------------------------
    // Language / PREFERENCES section
    // -----------------------------------------------------------------------

    testWidgets('shows PREFERENCES section header and Language row', (
      tester,
    ) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      expect(find.text('PREFERENCES'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
    });

    testWidgets('Language row shows current language display name (English)', (
      tester,
    ) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      // The default locale is English, so it should show "English".
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('tapping Language row opens the language picker bottom sheet', (
      tester,
    ) async {
      const profile = Profile(
        id: 'user-1',
        displayName: 'Jane',
        weightUnit: 'kg',
      );

      await tester.pumpWidget(buildTestWidget(profile: profile));
      await tester.pump();

      // Scroll to the Language row (it may be off-screen).
      await tester.ensureVisible(find.text('Language'));
      await tester.pumpAndSettle();

      // Tap the Language row.
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();

      // The bottom sheet should show both language options.
      expect(find.text('Portugu\u00eas (Brasil)'), findsOneWidget);
    });

    testWidgets(
      'PO-039: cancelling the edit dialog does not close the profile screen',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          displayName: 'John Doe',
          weightUnit: 'kg',
        );

        final mockAuth = MockAuthRepository();
        when(() => mockAuth.currentUser).thenReturn(null);
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(() => MockProfileNotifier(profile)),
              authRepositoryProvider.overrideWithValue(mockAuth),
              // BUG-040: stub authStateProvider so workoutCountProvider's
              // listener doesn't subscribe to the real Supabase auth
              // stream (which would arm a 5s pending timer).
              authStateProvider.overrideWith(
                (ref) => const Stream<AuthState>.empty(),
              ),
              // PR #283 review (Blocker 3): ProfileAvatar now ref.watches
              // currentUserEmailProvider directly.
              currentUserEmailProvider.overrideWithValue(null),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ProfileSettingsScreen(),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('John Doe'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // After cancelling, the profile screen should still be visible.
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('John Doe'), findsOneWidget);
      },
    );
  });

  // -----------------------------------------------------------------------
  // Avatar upload flow — camera permission denied snackbar
  // -----------------------------------------------------------------------

  group('avatar upload flow — camera permission denied snackbar', () {
    testWidgets(
      'shows cameraPermissionDeniedForAvatar snackbar with no action when '
      'camera permission is denied (not permanently)',
      (tester) async {
        // cameraPermissionStatus → denied (camera row visible in picker)
        // requestCameraPermission → denied (not permanently)
        final service = ShareService(
          permissionStatusReader: (_) async => PermissionStatus.denied,
          permissionRequester: (_) async => PermissionStatus.denied,
          imagePicker: (_) async => null,
          fileShareSink: (_, {text}) async =>
              const ShareResult('', ShareResultStatus.dismissed),
        );

        const profile = Profile(id: 'user-1', displayName: 'Alice');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(() => MockProfileNotifier(profile)),
              authRepositoryProvider.overrideWithValue(
                MockAuthRepository()
                  ..setCurrentUser(null)
                  ..setSignOut(),
              ),
              authStateProvider.overrideWith(
                (ref) => const Stream<AuthState>.empty(),
              ),
              currentUserEmailProvider.overrideWithValue(null),
              shareServiceProvider.overrideWithValue(service),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ProfileSettingsScreen(),
            ),
          ),
        );
        await tester.pump();

        // Tap avatar → picker sheet → tap "Take a photo"
        await tester.tap(find.byType(ProfileAvatar).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Take a photo'));
        await tester.pumpAndSettle();

        // Contract: correct copy — NOT the generic upload-failed copy.
        expect(
          find.text(
            'Camera access denied. Try the gallery, or open settings to grant access.',
          ),
          findsOneWidget,
        );
        // Denied (not permanent) → no "Open settings" action button.
        expect(find.text('Open settings'), findsNothing);
      },
    );

    testWidgets(
      'shows cameraPermissionDeniedForAvatar snackbar WITH "Open settings" '
      'action when camera permission is permanently denied',
      (tester) async {
        // cameraPermissionStatus → denied (camera row still visible so user
        // can tap it; the runtime-request then returns permanentlyDenied).
        final service = ShareService(
          permissionStatusReader: (_) async => PermissionStatus.denied,
          permissionRequester: (_) async => PermissionStatus.permanentlyDenied,
          imagePicker: (_) async => null,
          fileShareSink: (_, {text}) async =>
              const ShareResult('', ShareResultStatus.dismissed),
          appSettingsOpener: () async => true,
        );

        const profile = Profile(id: 'user-1', displayName: 'Alice');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(() => MockProfileNotifier(profile)),
              authRepositoryProvider.overrideWithValue(
                MockAuthRepository()
                  ..setCurrentUser(null)
                  ..setSignOut(),
              ),
              authStateProvider.overrideWith(
                (ref) => const Stream<AuthState>.empty(),
              ),
              currentUserEmailProvider.overrideWithValue(null),
              shareServiceProvider.overrideWithValue(service),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ProfileSettingsScreen(),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byType(ProfileAvatar).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Take a photo'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Camera access denied. Try the gallery, or open settings to grant access.',
          ),
          findsOneWidget,
        );
        // PermanentlyDenied → "Open settings" SnackBarAction is present.
        expect(find.text('Open settings'), findsOneWidget);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Extra notifier stubs used in the additional tests above
// ---------------------------------------------------------------------------

class _TrackingProfileNotifier extends AsyncNotifier<Profile?>
    with Mock
    implements ProfileNotifier {
  _TrackingProfileNotifier({required this.profile, required this.onToggle});

  final Profile? profile;
  final VoidCallback onToggle;

  @override
  Future<Profile?> build() async => profile;

  @override
  Future<void> toggleWeightUnit() async => onToggle();

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}
}

class _LoadingProfileNotifier extends AsyncNotifier<Profile?>
    with Mock
    implements ProfileNotifier {
  @override
  Future<Profile?> build() => Completer<Profile?>().future; // never resolves

  @override
  Future<void> toggleWeightUnit() async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}
}

extension _MockAuthRepositoryExt on MockAuthRepository {
  void setCurrentUser(User? user) {
    when(() => currentUser).thenReturn(user);
  }

  void setSignOut() {
    when(() => signOut()).thenAnswer((_) async {});
  }
}
