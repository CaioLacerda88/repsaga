# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### Legal PR 2 — UI consent flows

Branch: `feat/legal-pr2-consent-ui-age-gate-toggles`

Follow-up to Legal PR 1 (#305) — that PR shipped Policy + ToS copy hedged as
"delivered by a forthcoming app update". This PR ships the 4 UI surfaces that
make those hedges true. Cluster reference: `data-protection-compliance`
(PROJECT.md §0 Cluster Ledger; named in PR #307).

**Surfaces (4):**

1. **Age confirmation at signup** — `lib/features/auth/ui/login_screen.dart`.
   New `CheckboxListTile` shown only in signup mode below the password field
   ("I confirm I am 18 years of age or older."). Sign-up CTA disabled until
   checked. State is local to the screen (transient per signup attempt). Inline
   ToS / Privacy Policy links route via `context.push`. ARB keys:
   `signupAgeConfirmation`, `signupAgeConfirmationLink`.
2. **Bodyweight sensitive-data opt-in** — new
   `lib/features/profile/providers/bodyweight_consent_provider.dart` mirroring
   `crash_reports_enabled_provider.dart` (Hive key `bodyweight_consent_enabled`,
   default **false** — explicit opt-in for sensitive health data per LGPD Art.
   11). UI changes:
   - `bodyweight_row.dart` — `BodyweightEditorSheet._onSave` shows a consent
     dialog when consent is false, defers save until "Save with consent" is
     tapped. Dialog title + body + 2 actions, no SnackBar (the dialog itself
     is the surface).
   - New `bodyweight_consent_toggle.dart` widget mounted in Profile Settings
     → Privacy section. Withdrawal mechanism.
3. **Gender opt-in disclosure** — new gender editor in `profile_settings_screen.dart`
   (currently there's no gender UI — Phase 29 v2 wired the column but the
   editor was deferred). Includes a one-time disclosure banner gated by
   `gender_consent_enabled` Hive key. Banner hidden once any value has been
   picked. New provider `gender_consent_provider.dart`.
4. **Analytics opt-out toggle** — exact-mirror of `CrashReportsToggle`:
   - `lib/features/analytics/data/analytics_repository.dart` — static `_enabled`
     flag + `setEnabled(bool)`; `insertEvent` short-circuits when disabled.
   - `lib/features/profile/providers/analytics_enabled_provider.dart` — Hive
     key `analytics_enabled`, default **true** (legitimate-interest opt-out).
   - `lib/features/profile/ui/widgets/analytics_toggle.dart` — `SwitchListTile`.
   - Mount in `profile_settings_screen.dart` PRIVACY section immediately below
     `CrashReportsToggle`.

**Implementation checklist:**

- [x] Surface 4 — Analytics opt-out (smallest, exact CrashReports mirror)
- [x] Surface 1 — Age confirmation checkbox at signup
- [x] Surface 2 — Bodyweight consent provider + dialog + withdrawal toggle
- [x] Surface 3 — Gender editor + opt-in banner + consent provider
- [x] ARB additions in BOTH `app_en.arb` + `app_pt.arb`
- [x] `flutter gen-l10n` regen
- [x] Unit tests for each new provider (12/12 green)
- [x] Widget tests for each new surface (38/38 green; behavior-not-wiring per CLAUDE.md A2)
- [x] `dart format .` + `dart analyze --fatal-infos` clean
- [x] `flutter test` — 3491 passed; 25 baseline integration failures unchanged from main HEAD (require local Supabase)
- [ ] Branch + commit + push + open PR

**Verification:**

- [x] `dart format .` clean
- [x] `dart analyze --fatal-infos` clean
- [x] Affected unit/widget tests green
- [x] Existing tests with new dependencies updated (login duplicate-email tests
      now tick age checkbox; profile_screen_test counts adjusted for new rows)
- [ ] PR body includes `**QA pass pending — final coverage + E2E run after code review.**`
