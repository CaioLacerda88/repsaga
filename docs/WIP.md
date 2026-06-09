# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Routines long-press discoverability hint (item 5) — `fix/routines-tip` (in progress)

UX-locked one-time hint row teaching the routine-card long-press → edit/delete
gesture. Per backlog item 5.

- [x] `lib/features/routines/providers/routine_hint_provider.dart` — `RoutineHintNotifier`
      (sync `Notifier<bool>` over `HiveService.userPrefs`, mirrors
      `BodyweightPromptDismissalNotifier`). Keys `hint_routine_longpress_seen`
      (bool) + `routine_hint_view_count` (int, cap 3). State = `!seen && count<3`.
      `markSeen()` (idempotent) + `recordView()` (idempotent, once per mount).
- [x] `lib/features/routines/ui/widgets/routine_long_press_hint.dart` — self-gating
      `ConsumerStatefulWidget`; `Icons.touch_app` 16dp + 12sp Barlow `bodySmall`,
      `textDim`; `recordView()` in post-frame callback; `horizontalPadding` param
      (16 on `/routines`, 0 on home).
- [x] l10n `hintRoutineLongPress` (en + pt).
- [x] Render site 1: `routine_list_screen.dart` — hint between MY ROUTINES header
      and first user card.
- [x] Render site 2: `home_screen.dart` `_HomeRoutinesList` — hint between
      MY ROUTINES eyebrow and first card (`horizontalPadding: 0`).
- [x] All 3 `onLongPress` sites wrapped with `markSeen()` (routines list user +
      default lists, home). `bucket_chip_row.dart` is an `onTap` chip, not a
      card long-press — out of scope.
- [x] Defensive `Hive.isBoxOpen` guard in the notifier — the hint is cosmetic
      and must never throw a `HiveError` into a screen build when prefs aren't
      booted (broke the Hive-free `routine_list_screen_test.dart` otherwise).
- [x] Tests: `test/unit/features/routines/routine_hint_provider_test.dart` (7,
      gating + idempotence) + `test/widget/features/routines/ui/routine_long_press_hint_test.dart`
      (5, visibility/markSeen-gone/recordView/alignment).
- [x] format + analyze clean; guards clean (hardcoded-colors, typography).
- [x] Visual: web build, signed in as smokeRoutineManagement, hint renders
      between MY ROUTINES header and first card on both `/routines` and Home at
      360dp — ambient list-metadata, flush to the 16dp card edge.
