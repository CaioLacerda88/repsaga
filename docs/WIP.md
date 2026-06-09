# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Manual QA scan punch-list — 2026-06-09 (user scanning; NOT implementing yet)

User is doing a manual pass of the installed APK (main `6adb6252`) and feeding
findings. Collecting + root-causing only; implementation batched once the user
signals the scan is done. UX critic dispatched for items 3 + 5.

### 1. Signup — password strength hint is misleading  ·  DONE (branch fix/signup-polish)
`login_screen.dart` `passwordStrengthScore` + `_PasswordStrengthBar`. Medium
tier hardcodes "add numbers or symbols" regardless of what's actually missing
("Test12." has both a number and a symbol; it's only short on length).
**Fix (user-approved "Tier + next step"):** name the single highest-priority
missing requirement, prioritized length → number → symbol, prefixed with the
tier word. Strong stays celebratory.
- "Test12."  ▮▮▯  Medium — use 8+ characters
- "testtest" ▮▮▯  Medium — add a number
- "Test12ab" ▮▮▯  Medium — add a symbol
- "Test12.ab"▮▮▮  Strong password!
New l10n tip keys (en+pt). Pass the password value (or unmet-set) to the bar.

### 2. Signup — age-gate checkbox text misplaced on device  ·  DONE (branch fix/signup-polish)
`login_screen.dart` checkbox `Row` (~513) + `_AgeGateLabel` (~728). Root: the
inline Terms/Privacy links are `WidgetSpan(TextButton)` forced to
`minimumSize: Size(0, 48)` → that text line inflates to 48dp, breaking line
flow + baselines; compounded by a magic `Padding(top: 12)` faking checkbox
alignment. **Fix:** correct checkbox↔label vertical alignment + de-inflate the
link line (keep a reasonable tap target without a 48dp inline height). Preserve
the `auth-age-link-*` Semantics identifiers (E2E). Re-screenshot at 360/412dp.

### 3. Signup — password reveal UX (drop confirm)  ·  DONE (branch fix/signup-polish)
UX critic pick: **drop the confirm-password field entirely** (GOV.UK/HIG/NN/g —
a reliable reveal toggle replaces confirm's typo-safety; frees a field for
412dp). Single password field + single reveal toggle. Spec:
- Remove `_confirmPasswordController` + `_validateConfirmPassword` (+ field).
- Eye stays as the password `AppTextField` suffix; add state-aware tooltip
  (drives Material 3 semantics label): "Mostrar senha" (obscured) / "Ocultar
  senha" — keys `showPassword`/`hidePassword`.
- One-time ghost hint below the strength bar at score 0: "Toque no olho para
  verificar" / "Tap the eye to check your password"; 12sp Barlow `textDim`,
  self-dismiss after first toggle.
- Strength bar unchanged.
**APPROVED by user (2026-06-09): drop confirm (option a).**

**Blast-radius inventory (confirmed — all contained to the auth surface):**
_lib/features/auth/ui/login_screen.dart:_
- L31 `_confirmPasswordController` decl · L55 dispose · L68 clear-on-toggle → remove all
- L247-251 `_validateConfirmPassword` → remove
- L452-454 confirm `AppTextField` block (+ its `if(_isSignUp)` wrapper SizedBox) → remove
- L425 password `onFieldSubmitted` — currently `_isSignUp ? null : submit` (signup chained to confirm). Confirm is now gone, so the password field becomes the keyboard-submit point AND inherits the age-gate guard: `onFieldSubmitted: isLoading || (_isSignUp && !_ageConfirmed) ? null : (_) => _submit()` (mirrors the CTA gate; works in both modes).
- L466 confirm's `onFieldSubmitted` age-gate guard → removed with the field (logic now on password, above).
- Eye toggle: pass `obscureTooltipShow`/`obscureTooltipHide` to the password `AppTextField`.
- One-time reveal hint: new bool `_revealHintDismissed`; show the ghost hint line under the strength bar while `_isSignUp && !_revealHintDismissed && password not yet revealed`; flip on first eye tap. (Local state, not Hive — fine for per-session.)

_lib/shared/widgets/app_text_field.dart:_ add optional `obscureTooltipShow`/`obscureTooltipHide` (String?); set `IconButton.tooltip = _obscured ? show : hide` (Material 3 → semantics label). Default null = no tooltip (other callers unaffected — blast-radius safe).

_l10n (en+pt, then gen):_ REMOVE `confirmPassword`, `passwordMismatch` (+ @desc). ADD `showPassword`, `hidePassword`, `passwordRevealHint`.

_tests (widget):_
- `signup_form_test.dart`: drop confirm-present assertion; **remove** the mismatch test; the email-obscured regression test drops its confirm-field obscured assertion (keep email+password).
- `signup_age_confirmation_test.dart`: the "keyboard-Done bypass" test targets the CONFIRM field → **retarget to the password field** (now the gated submit) + rename.
- `duplicate_email_snackbar_test.dart` L101: drop the confirm-field fill.
- `login_screen_test.dart` L241-284: update the "`.last` TextFormField is confirm" positional logic — password is now the last text field in signup.

_E2E:_
- `selectors.ts` L64-68: remove `confirmPasswordInput` (+ comment).
- `auth.spec.ts`: happy-path drop confirm fill; "full-form surfaces" drop confirm assertion; **remove** the mismatch test; **retarget** the keyboard-Done bypass test to the password field.
- `onboarding.spec.ts` fresh-signup regression: drop the confirm fill.

No refs outside auth (grepped `_confirmPasswordController`/`confirmPassword`/`passwordMismatch`/`auth-confirm-password` across lib+test).

### 4. Share / post-session picture overlay — class name not translated
`post_session_screen.dart:821` — `className = classSlug.toUpperCase()` prints
the raw slug instead of localizing. **Fix:** map slug → `CharacterClass` enum
(`CharacterClass.values` by `.slug`) → `localizedClassName(cls, l10n)` (helper
in `class_localization.dart:84`), then uppercase. Affects achievementFrame
className + discreet eyebrow/hero. Cluster `slug-rendered-as-display-name`.
Add a regression test (pt locale → localized class, not slug).

### 5. Routines (Treinos) screen — long-press is undiscoverable  ·  UX SPEC LOCKED
`routine_list_screen.dart` (~93/128) + `widgets/routine_card.dart` +
`home_screen.dart:439`: long-press a routine card → `showRoutineActionSheet`.
UX critic rec: a **one-time hint row** (NOT on the card — peer of the list,
avoids the two-icon right-edge collision with the play button):
- Between the "MY ROUTINES" `SectionHeader` and the first `RoutineCard`, in
  BOTH `RoutineListScreen` and the home routine section.
- `Icons.touch_app` (16dp, `AppColors.textDim`) + "Mantenha pressionado para
  editar" / "Press and hold to edit" (12sp Barlow, `textDim`), left-aligned to
  16dp card edge, no card/border/background.
- Dismiss permanently after first confirmed long-press via Hive bool
  `hint_routine_longpress_seen` (default false), with a 3-session fallback
  dismissal so it never becomes a permanent fixture.
New l10n key `hintRoutineLongPress`. Wrap the existing `onLongPress` to also
flip the Hive flag + rebuild.

**Hive infra (confirmed):** use the existing `HiveService.userPrefs` box (same
box locale_provider uses). Keys: `hint_routine_longpress_seen` (bool, default
false) → set true on first confirmed long-press. No session counter exists, so
the 3-session fallback needs `routine_hint_view_count` (int, default 0) →
increment once per routines-surface mount; hide the hint when count >= 3 even
without a long-press. Read both via a small provider so the hint row rebuilds
reactively. Blast radius: 2 render sites (`routine_list_screen.dart`,
`home_screen.dart` routine section) + 1 new hint widget + 1 prefs read/write
helper; no other consumers.

### Planned PR split (once scan done)
- **Signup polish PR:** items 1 + 2 + 3 (one surface, `login_screen.dart`).
- **Share fix PR:** item 4 (post-session/share).
- **Routines tip PR:** item 5.

---
