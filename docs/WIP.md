# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## In-flight — Signup screen redesign (Option A, Full-Form Signup)

**Branch:** `feature/signup-redesign-option-a`
**Source of truth:** `docs/signup-screen-mockup-v1.html` §3 (Option A) + PROJECT.md §2 backlog.

### Boundary inventory (gates implementation — traced, do NOT re-derive)

**Signature changes (update ALL callers + tests):**
- `AuthRepository.signUpWithEmail` — add `String? displayName`; thread into
  the `data:`/user_metadata map alongside `locale` (only when non-null).
- `AuthNotifier.signUpWithEmail` — add `displayName` param, forward to repo.
- `LoginScreen._submit` — pass `_displayNameController.text`.
- `ProfileNotifier.saveOnboardingProfile` — REMOVE `displayName` param;
  upsert only fitnessLevel + frequency + onboarded_at. (`upsertProfile`
  already treats `displayName` as omit-on-null, so no repo change needed.)

**Signup form (login_screen.dart, signup is `_isSignUp` mode):**
- Add `_displayNameController` + `_confirmPasswordController`; dispose + clear
  on mode toggle.
- displayName field above email (`AutofillHints.name`, non-empty validation).
- confirm-password field (`obscureText`, `AutofillHints.newPassword`,
  signup-only; validator `value == _passwordController.text`).
- 3-segment non-blocking strength bar (score 1=len≥6, 2=len≥8|digit|special,
  3=all three). Colors error/warning/success.
- "CRIAR CONTA" heading (Rajdhani 700 ~16sp full-cream) signup-only, replaces
  the dim subtitle in signup mode.
- PRESERVE the structural age-gate: CTA `onPressed = null` until checkbox
  ticked (PR #309).

**Age-gate + legal:**
- Inline Privacy + Terms links INTO the checkbox label via `Text.rich` +
  `WidgetSpan(TextButton)`. Use `MaterialTapTargetSize.padded`.
- DELETE the separate legal-chips Padding+Row (PR #309).
- Hide `_LegalFooter` when `_isSignUp`.
- Disabled-CTA helper text (`signupAgeRequiredHint`) when signup & !ageConfirmed.

**Onboarding (onboarding_screen.dart):**
- Remove `_nameController`, the name AppTextField, the empty-name guard, and
  the `displayName:` arg to saveOnboardingProfile. Page 2 = level + frequency.
- Drop dead `pleaseEnterName` ARB key (only referenced in onboarding).

**L10n (both arb + gen):** add `confirmPassword`, `passwordMismatch`,
`passwordStrengthWeak/Medium/Strong`, `signupHeading`, `signupAgeRequiredHint`.
Reuse `displayName`, `termsOfService`, `privacyPolicy`. Remove `pleaseEnterName`.

**Breakage to handle:** auth_notifier_test (displayName forwarding),
profile_notifier_save_test (drop displayName), onboarding widget/provider
tests (name field absent), E2E selectors + onboarding.spec + auth.spec +
fresh-signup regression. Keep PR #312 fresh-signup save path intact.

### Checklist

- [x] Branch + WIP (this section)
- [x] L10n keys (en + pt) + gen — `signupHeading`, `confirmPassword`,
  `passwordMismatch`, `passwordStrengthWeak/Medium/Strong`,
  `signupAgeRequiredHint`, `signupAgeConfirmationLead`, `displayNameRequired`;
  removed `pleaseEnterName`.
- [x] AuthRepository.signUpWithEmail + displayName (omit-on-null in `data:`)
- [x] AuthNotifier.signUpWithEmail + displayName
- [x] login_screen.dart: controllers, fields, strength bar, heading, inline
  legal (`_AgeGateLabel`), footer suppression, helper text
- [x] ProfileNotifier.saveOnboardingProfile: drop displayName
- [x] onboarding_screen.dart: remove name field + guard + arg
- [x] Widget tests: signup_form_test (new), signup_age_confirmation,
  login_screen, duplicate_email_snackbar, onboarding (no name), save_error
- [x] Unit tests: auth_notifier + auth_repository (displayName forward),
  profile_notifier_save (no displayName)
- [x] E2E selectors + specs (auth, onboarding, charter-d)
- [x] format + analyze (0 issues) + test (591 passed across touched dirs)
- [ ] commit locally (next)

---

## Session checkpoint — 2026-06-08 (pre-compact handoff)

**Main HEAD:** `52bf93e3` (post Phase 34 closeout #313).

**Nothing in-flight.** No agents running, no open PRs, no pending CI. This
checkpoint exists so next session can pick the right next-task without
re-deriving state.

### What shipped this wave (Phase 34 — see PROJECT.md §4 for full detail)

15 PRs across 4 days closed three workstreams:
- **Auth remediation:** #298 #299 #300 #301 #302 #303 #304 #312 — culminated in
  the typed DB-42501 → session-expired snackbar + Sign-in CTA recovery + the
  provider-init-timing footgun fix in `ProfileNotifier` (saveOnboardingProfile
  + updateTrainingFrequency + toggleWeightUnit now read from
  `authStateProvider.value?.session?.user.id`).
- **Legal compliance:** #305 (Privacy Policy + ToS LGPD/GDPR/medical rewrite)
  + #308 (JSON portability export from Manage Data) + #309 (4 consent UI
  surfaces: signup age gate, bodyweight + gender explicit opt-in, analytics
  opt-out) + #310 (Launch Phase compliance follow-up backlog).
- **UX + bug polish:** #306 (home ActionHero reactivity), #307 (manage-data
  avatar storage leak + exercises CASCADE + reset-all active workouts),
  #311 (signup + Fill Remaining UX mockups — implementations queued).

**Hosted Supabase ops applied:** migration 00073 (locale metadata backfill —
6 users) + migration 00074 (exercises CASCADE) + `delete-user` Edge Function
redeployed with avatar storage removal.

**APK on phone:** SM S938B at HEAD `43c83d07` (= #312 merge before #313
docs-only closeout — production code is up to date). Cumulative #298-#312
installed.

### Queued — your call to dispatch

These have shipped mockups (#311 merged) but no implementation has been
dispatched. Pick when ready.

1. **Signup screen redesign — Option A.** `docs/signup-screen-mockup-v1.html`
   on main is the locked design target. Scope: single-screen form, add
   confirm-password + display_name field (move display_name out of
   onboarding so onboarding only collects fitness signals), add 3-segment
   non-blocking password-strength bar, inline Privacy + Terms links into the
   age-gate checkbox label (drop the separate chip row PR #309 added),
   "CRIAR CONTA" heading in Rajdhani 700. Preserve PR #309's structural
   CTA-disabled-until-checkbox-ticked guarantee (`onPressed = null`). 412dp
   device must not require scrolling.
2. **Fill Remaining UX — Option C.** `docs/fill-remaining-gating-mockup-v1.html`
   on main. Two-method change in `lib/features/workouts/ui/widgets/exercise_card.dart`:
   - `_hasFillableSets` predicate → "any completed AND any incomplete"
     (today's directional check is the bug — only fires when an incomplete
     set's `setNumber > lastCompleted.setNumber`)
   - `fillRemainingSets` → fill all incomplete regardless of `setNumber`
     ordering
   No new UI state. User's grey-out proposal (Option B) was rejected because
   it breaks valid mid-session flows (failed set 1 + completed sets 2-3,
   restart mid-session).

Both can ship in parallel — they touch different files. Either is a small
PR (one screen + tests).

### External / manual items — user side (don't dispatch agents)

From PR #310 Launch Phase compliance follow-ups (also in PROJECT.md §3
Launch Phase prereqs):
- **`dpo@repsaga.app` alias** — required for PR #305 §12 DPO promise to
  honor any LGPD Art. 41 request. Blocked on `repsaga.app` domain
  registration.
- **LGPD Art. 7 IX legitimate-interest balancing memo** — one-page internal
  doc. PR #305 §4a's "balancing test documented and available on request"
  becomes a real commitment when ANPD asks. Store wherever you keep
  internal compliance docs.
- **Domain registration** — `repsaga.com` / `.app` / `.com.br`. Unblocks
  DPO alias + Supabase Site URL fix + assetlinks.json hosting.
- **Supabase Dashboard → Site URL** — currently default `http://localhost:3000`.
  Set to any HTTPS string (e.g. `https://repsaga.app` even before
  registration) as the immediate workaround — `{{ .ConfirmationURL }}`
  redirect then reads as "site can't be reached" rather than
  "localhost: connection refused". Proper fix (Android App Links +
  intent-filter + assetlinks.json + Dart handler) is Launch Phase scope
  per PR #304.
- **Supabase backup retention** — verify Dashboard → Project Settings →
  Database PITR window matches PR #305 §7's "30 days" claim. Free tier =
  7 days; if longer, hedge the policy text in a tiny follow-up PR.

### Open verification pending — user testing

The fresh-signup save bug (DB-42501) recurred 5 times across this wave. PR #312
ships defensive UX (snackbar + Sign-in CTA recovery) AND a fresh-signup E2E
regression that drives the actual app signup form with an ephemeral user.
CI green at 37m41s with that test passing.

**Worth eyeballing on the S938B (already installed):**
1. Sign up with a fresh email+password account → onboarding → save profile.
   If you hit "Couldn't save your profile" → bug is still alive (defense-in-depth
   should have surfaced "Your session expired. Sign in again." + Sign-in CTA
   instead — if you see THAT, defense works but server-side race still fires).
2. Test Manage Data → "Export my data" (#308 ships the JSON export).
3. Test Profile → Settings → PRIVACY toggles (#309) — `Send crash reports`
   already existed, plus new `Send usage analytics` and `Body weight consent`.
4. Test gender editor (Profile Settings) — first open should show the
   disclosure banner, picking any value (including "Not set") should
   extinguish it permanently.

### Recovery instructions (if next session needs to pick up)

1. Read this checkpoint block first.
2. Read `docs/PROJECT.md` §0 Quick Reference (Phase 34 COMPLETE, next is
   Launch Phase) + the Phase 34 §4 entry for the full ship list.
3. `gh pr list --state open` should return empty.
4. Task list in this session: #48 (signup UX) + #51 (Fill Remaining UX) are
   in_progress with the mockup PRs merged but implementation dispatches not
   started. #49 + #50 completed. The next session can re-derive these from
   PROJECT.md if the task list resets.
5. **Lingering disk junk** that doesn't matter:
   `.claude/worktrees/agent-a32a6dd8f4eaa72f4/` exists as an empty
   directory whose inode is held by a Windows background process
   (Search Indexer, Defender, or the IDE file watcher). Will release on
   next IDE/system restart. No git impact — `git worktree list` shows
   only main.

### What's NOT in this checkpoint

Anything mid-implementation. All agents that ran this wave finished cleanly +
had their PRs merged. There are no half-built branches, no uncommitted
changes, no agents to resume via SendMessage. Hard reset is safe.

---
