/// Router-level regression for the `/routines/create` grey-screen crash.
///
/// The unit test `test/unit/core/router/routine_from_extra_test.dart` pins the
/// `routineFromExtra` helper contract in isolation. THIS test reproduces the
/// actual user-perceptible symptom end-to-end: it drives the real
/// `/routines/create` route — wired with the production `routineFromExtra`
/// guard inside the route builder — using a NON-Routine `extra` (the value
/// shape GoRouter hands back on Android process-death restore, which the old
/// bare `state.extra as Routine?` cast threw a `_TypeError` on → grey
/// `ErrorWidget` painting the whole Routines tab blank in a RELEASE build).
///
/// Behavior asserted (not wiring):
///   * NO `ErrorWidget` paints (the grey screen is gone).
///   * `CreateRoutineScreen` renders, in CREATE mode — the screen distinguishes
///     mode via `_isEditing => widget.routine != null`, surfaced as the AppBar
///     title's Semantics identifier (`routine-mgmt-create-title` vs
///     `...-edit-title`) and an empty name field. A guard that wrongly passed
///     the garbage through would either crash or open in edit mode; both are
///     caught here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/router/app_router.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/routines/ui/create_routine_screen.dart';
import 'package:repsaga/l10n/app_localizations.dart';

/// Resolves immediately to a fixed profile so `CreateRoutineScreen`'s
/// `profileProvider` read for `weightUnit` never touches the real Supabase
/// client. The screen only reads `.value?.weightUnit`; a null-but-resolved
/// profile is enough, but we hand back a real one for realism.
class _StubProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile?> build() async =>
      const Profile(id: 'u1', displayName: 'Caio');
}

/// A GoRouter whose `/routines/create` route is wired EXACTLY like production:
/// the builder calls `routineFromExtra(state.extra)` and feeds the result to
/// the real [CreateRoutineScreen]. Driving this route with garbage `extra`
/// exercises the real crash path (the bare cast lived in this builder).
GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/routines',
    routes: [
      GoRoute(
        path: '/routines',
        builder: (_, _) => const Scaffold(body: Text('routines-body')),
        routes: [
          GoRoute(
            path: 'create',
            builder: (context, state) =>
                CreateRoutineScreen(routine: routineFromExtra(state.extra)),
          ),
        ],
      ),
    ],
  );
}

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [profileProvider.overrideWith(_StubProfileNotifier.new)],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

void main() {
  group('/routines/create extra guard (process-death restore)', () {
    testWidgets(
      'navigating with a NON-Routine extra opens create mode, no grey screen',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_wrap(router));
        await tester.pumpAndSettle();
        expect(find.text('routines-body'), findsOneWidget);

        // This is the exact symptom-trigger: on process-death restore GoRouter
        // hands `extra` back as a non-Routine value. `'garbage-string'` would
        // have thrown `_TypeError` under the old `state.extra as Routine?`.
        router.push('/routines/create', extra: 'garbage-string');
        await tester.pumpAndSettle();

        // 1. The crash symptom is GONE — no grey ErrorWidget painted.
        expect(
          find.byType(ErrorWidget),
          findsNothing,
          reason:
              'A non-Routine extra must NOT throw — the old bare cast painted '
              'a grey ErrorWidget over the whole Routines tab on restore.',
        );

        // 2. The real screen rendered.
        expect(find.byType(CreateRoutineScreen), findsOneWidget);

        // 3. It is in CREATE mode, not edit mode. The screen flags mode via the
        //    AppBar title Semantics identifier (`_isEditing` drives it). Create
        //    title present, edit title absent.
        expect(
          find.bySemanticsIdentifier('routine-mgmt-create-title'),
          findsOneWidget,
          reason: 'A lost/garbage extra must degrade to create mode.',
        );
        expect(
          find.bySemanticsIdentifier('routine-mgmt-edit-title'),
          findsNothing,
        );

        // 4. Create mode also means an empty name field (edit mode prefills the
        //    routine name). The lone editable TextField with empty text is the
        //    name field; assert no pre-populated routine name leaked through.
        final nameField = tester.widget<TextField>(
          find.byType(TextField).first,
        );
        expect(
          nameField.controller?.text,
          isEmpty,
          reason: 'Create mode starts with a blank name field.',
        );
      },
    );
  });
}
