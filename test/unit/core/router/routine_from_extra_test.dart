/// Regression test for the `/routines/create` grey-screen crash.
///
/// GoRouter's `extra` is NOT preserved across process death. When Android
/// kills the app while the user sits on `/routines/create` and later restores
/// it, the route rebuilds with `extra` as a non-Routine value. The old
/// `CreateRoutineScreen(routine: state.extra as Routine?)` threw a `_TypeError`
/// on that value, which in a RELEASE build paints a grey `ErrorWidget` — the
/// whole Routines tab goes blank (the reported on-device bug). `routineFromExtra`
/// guards the cast so a lost extra degrades to "create a new routine".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/router/app_router.dart';
import 'package:repsaga/features/routines/models/routine.dart';

void main() {
  group('routineFromExtra (process-death extra guard)', () {
    final routine = Routine(
      id: 'r1',
      name: 'Push Day',
      isDefault: false,
      exercises: const [],
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    );

    test('returns the Routine when extra IS a Routine (edit flow)', () {
      expect(routineFromExtra(routine), same(routine));
    });

    test('returns null when extra is null (normal create flow)', () {
      expect(routineFromExtra(null), isNull);
    });

    test('returns null for a non-Routine extra — the process-death restoration '
        'case that used to throw a _TypeError and paint a grey screen', () {
      // On restore, `extra` comes back as a deserialized primitive/map, never
      // the original Routine object. A bare `as Routine?` threw on each of
      // these; the guard must yield null so the screen opens in create mode.
      expect(routineFromExtra('some-string'), isNull);
      expect(routineFromExtra(<String, dynamic>{'id': 'r1'}), isNull);
      expect(routineFromExtra(42), isNull);
      expect(routineFromExtra(const <int>[1, 2, 3]), isNull);
    });
  });
}
