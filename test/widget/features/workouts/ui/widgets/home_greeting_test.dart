/// Widget tests for [HomeGreeting] (Phase 27 L2).
///
/// The greeting sits at the top of Home and renders two lines:
///
///   1. Eyebrow: weekday name · short month-day, uppercased and
///      locale-formatted via [DateFormat.EEEE] + [DateFormat.MMMd].
///   2. Name: the user's display name, with email-prefix fallback when
///      [Profile.displayName] is null/empty, then empty string when neither
///      source resolves.
///
/// Tests pin the rendered contract — what the user sees — not the wiring.
/// The display-name vs email-prefix decision is the load-bearing piece of
/// behavior; the date eyebrow's locale formatting is covered with a
/// fixed-time pt_BR test using `package:clock`.
library;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/home_greeting.dart';

import '../../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _ProfileStub extends AsyncNotifier<Profile?> implements ProfileNotifier {
  _ProfileStub(this.profile);
  final Profile? profile;

  @override
  Future<Profile?> build() async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _harness({
  required Profile? profile,
  required String? email,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => _ProfileStub(profile)),
      currentUserEmailProvider.overrideWithValue(email),
    ],
    child: TestMaterialApp(
      locale: locale,
      home: const Scaffold(body: HomeGreeting()),
    ),
  );
}

Profile _profile({String? displayName}) =>
    Profile(id: 'user-001', displayName: displayName, weightUnit: 'kg');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HomeGreeting', () {
    testWidgets('shows display name when profile.displayName is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          profile: _profile(displayName: 'Caio'),
          email: 'caio@test.local',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Caio'), findsOneWidget);
      // Prefix must NOT render when display name is present.
      expect(find.text('caio'), findsNothing);
    });

    testWidgets('falls back to email prefix when displayName is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          profile: _profile(displayName: null),
          email: 'caiolacerda88@gmail.com',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('caiolacerda88'), findsOneWidget);
    });

    testWidgets(
      'falls back to email prefix when displayName is whitespace-only',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            profile: _profile(displayName: '   '),
            email: 'alex@example.com',
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('alex'), findsOneWidget);
      },
    );

    testWidgets(
      'renders no name text when both displayName and email are absent',
      (tester) async {
        await tester.pumpWidget(
          _harness(profile: _profile(displayName: null), email: null),
        );
        await tester.pump();
        await tester.pump();

        // Widget must mount cleanly without throwing — Semantics container is
        // on the tree at the home-greeting identifier even when the name
        // resolves to an empty string. We assert the absence of any name
        // candidate strings rather than the presence of the empty string
        // (Flutter renders empty Text as a zero-glyph node which `find.text`
        // matches inconsistently).
        expect(find.byType(HomeGreeting), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'widget must build without throwing when both sources null',
        );
        expect(find.text('Alex'), findsNothing);
        expect(find.text('caiolacerda88'), findsNothing);
      },
    );

    testWidgets('renders uppercased weekday and short month-day in pt locale', (
      tester,
    ) async {
      // Pin clock at Tuesday, May 19 2026 so the rendered eyebrow is
      // deterministic regardless of the day the test runs.
      await withClock(Clock.fixed(DateTime(2026, 5, 19, 12)), () async {
        await tester.pumpWidget(
          _harness(
            profile: _profile(displayName: 'Caio'),
            email: 'caio@test.local',
            locale: const Locale('pt'),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Find the eyebrow Text widget — the one whose data is uppercase
        // and contains both the weekday name and the day-month formatted
        // for the pt locale.
        //
        // DateFormat.EEEE('pt').format(DateTime(2026, 5, 19)) → "terça-feira"
        // DateFormat.MMMd('pt').format(DateTime(2026, 5, 19)) → "19 de mai."
        //
        // Both substrings must appear in the rendered uppercase string.
        final eyebrowFinder = find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              w.data == w.data!.toUpperCase() &&
              w.data!.contains('TERÇA') &&
              w.data!.contains('19') &&
              w.data!.contains('MAI'),
        );
        expect(eyebrowFinder, findsOneWidget);
      });
    });
  });
}
