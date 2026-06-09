import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';

/// Hive key (in [HiveService.userPrefs]) recording whether the user has ever
/// performed a confirmed long-press on a routine card. Once `true`, the
/// "press and hold to edit" discoverability hint is retired permanently.
const String routineHintSeenKey = 'hint_routine_longpress_seen';

/// Hive key (in [HiveService.userPrefs]) counting how many times a
/// routines-bearing surface has been mounted. The hint hides once this
/// reaches [_maxViewCount] even if the user never long-pressed, so it never
/// becomes a permanent fixture in the list.
const String routineHintViewCountKey = 'routine_hint_view_count';

/// After this many surface mounts the hint stops showing regardless of
/// whether the gesture was ever discovered.
const int _maxViewCount = 3;

/// Reactive gate for the routine long-press discoverability hint.
///
/// Backed by [HiveService.userPrefs] (opened during `HiveService.init()`
/// before `runApp`), mirroring [BodyweightPromptDismissalNotifier]: the box
/// is guaranteed open by the time any UI consumer reads this provider, so the
/// synchronous `Hive.box` read in [build] never races box-opening.
///
/// State is the boolean answer to "should the hint row render right now?" —
/// `true` iff the gesture has never been confirmed AND the surface has been
/// shown fewer than [_maxViewCount] times. Exposing the derived boolean (not
/// the raw flags) keeps the hint widget's `build` trivial and lets the row
/// rebuild reactively the instant either flag flips.
///
/// `userPrefs` is excluded from [HiveService.cacheSchemaBoxes], so these flags
/// survive cache-schema wipes — a user who already discovered the gesture
/// must never see the hint resurface after a model-version bump.
class RoutineHintNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Defensive: the `userPrefs` box is opened in `HiveService.init()` before
    // `runApp`, so in production it is always open. But the hint is a purely
    // cosmetic discoverability affordance — it must NEVER throw and crash the
    // routine list / home screen if prefs are unavailable (e.g. a widget test
    // that renders the screen without booting Hive). When the box isn't open
    // we degrade to "don't show the hint" rather than propagating a
    // `HiveError` into the screen's build.
    if (!Hive.isBoxOpen(HiveService.userPrefs)) return false;

    final box = Hive.box<dynamic>(HiveService.userPrefs);
    final seen = box.get(routineHintSeenKey, defaultValue: false) as bool;
    final viewCount = box.get(routineHintViewCountKey, defaultValue: 0) as int;
    return !seen && viewCount < _maxViewCount;
  }

  /// Mark the long-press gesture as discovered. Idempotent — once `seen` is
  /// stamped, re-calling is a value-equal no-op (the early return below
  /// short-circuits both the Hive write and the state emission, so wrapping
  /// every `onLongPress` site in this call costs nothing after the first).
  ///
  /// Wired into all three routine-card `onLongPress` callbacks alongside the
  /// existing `showRoutineActionSheet` call; it never alters the action-sheet
  /// behavior.
  Future<void> markSeen() async {
    if (!Hive.isBoxOpen(HiveService.userPrefs)) return;
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    final alreadySeen =
        box.get(routineHintSeenKey, defaultValue: false) as bool;
    if (alreadySeen) return;

    await box.put(routineHintSeenKey, true);
    state = false;
  }

  /// Increment the per-mount view counter once. Idempotent against the
  /// already-hidden terminal state: once the count has reached [_maxViewCount]
  /// (or the gesture was discovered, flipping `state` to `false`), further
  /// calls short-circuit so a re-mount can't keep churning Hive writes.
  ///
  /// Call exactly once per routines-surface mount (e.g. from `initState`).
  Future<void> recordView() async {
    if (!Hive.isBoxOpen(HiveService.userPrefs)) return;
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    final seen = box.get(routineHintSeenKey, defaultValue: false) as bool;
    if (seen) return;

    final current = box.get(routineHintViewCountKey, defaultValue: 0) as int;
    if (current >= _maxViewCount) return;

    final next = current + 1;
    await box.put(routineHintViewCountKey, next);
    state = next < _maxViewCount;
  }
}

/// Reactive gate for the routine long-press hint row. `true` ⇒ render the
/// hint. See [RoutineHintNotifier].
final routineHintProvider = NotifierProvider<RoutineHintNotifier, bool>(
  RoutineHintNotifier.new,
);
