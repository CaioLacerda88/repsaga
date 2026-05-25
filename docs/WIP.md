# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.


---

## Phase 30 · Implementation Plan

> Canonical spec: `docs/post-session-screen-mockup-v2.html` (Round 2, all 11 states + Path A pivot in §4½ — mid-workout flash layer retired; events pass through to the post-session ceremony + photo-overlay share card + 6 implementation gaps). Mockup is locked; do not deviate without surfacing via the "Open questions" subsection.
>
> Decomposed into **4 PRs**: 29.5 (retire 5 legacy mid-workout overlays + scaffold PersonalRecord variant + SlotPolicy — **MERGED via #255**), 30a (post-session screen + state machine + summary panel + finish-coordinator wiring — **MERGED via #259, 2026-05-24** at fae2f6d), 30b (share card pipeline), 30c (cleanup + deprecate `pr_celebration_screen.dart` + E2E migration + docs + **test-hygiene audit** absorbing the 3 remaining audit candidates).
>
> Status (2026-05-24): **PR 30a merged (#259)** — 69 files / +9663 / -83 / 5 bugs (C/D/E/F/G + visual) closed in-merge. 4 cluster ledger entries added: safearea-system-overlay-overlap, spec-caption-vs-implementation-drift (Bug C as canonical Dart-predicate surface), jsonb-payload-vs-typed-dart, developer-log-invisible-logcat. Bugs A + B (weekly_plan RPC + history routine pre-existing) queued as separate PRs. **Next: dispatch PR 30b (share card pipeline)** once Bug A + Bug B land.

### PR 30b — Share card pipeline

**Status (2026-05-24):** In flight on `feature/30b-share-card`. Dispatched in 3 passes to keep scope tractable: Pass 1 = widget + domain layer (variants A/B/Discreet, ShareCardRenderer, SharePayload, unit + widget + golden tests; NO IO, NO pubspec changes); Pass 2 = IO services (Context7-pinned `image_picker` / `share_plus` / `permission_handler` + ShareImageRenderer + ShareService + AndroidManifest); Pass 3 = ShareController + ShareSheet + SharePreviewScreen + wire `share_cta_button.dart` + E2E spec. Task graph in TaskList (#1 setup, #2 Pass 1, #3 Pass 2, #4 Pass 3, #5 ship).

**Pass 1 checklist (in flight):**

- [x] `lib/features/workouts/domain/share_payload.dart` — Freezed model + dominantBodyPart + dominantHue + factory `SharePayload.fromPostSessionState`
- [x] `make gen` to produce `share_payload.freezed.dart`
- [x] `test/unit/features/workouts/domain/share_payload_test.dart` — 8 composition cases (day-zero / baseline / single PR / multi PR / single rank-up / multi rank-up / title / class-change) + idempotency
- [x] `lib/features/workouts/ui/post_session/share/variants/share_card_variant_a.dart` — Minimal Strip layout (bottom strip + hue accent + XP + PR + bar + REPSAGA wordmark)
- [x] `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_a_test.dart`
- [x] `lib/features/workouts/ui/post_session/share/variants/share_card_variant_b.dart` — Full-bleed collar layout w/ `CustomClipper<Path>` top + bottom diagonals
- [x] `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_b_test.dart`
- [x] `lib/features/workouts/ui/post_session/share/variants/share_card_discreet.dart` — Hue flood + reused `paintCutSlash` + d-hero numeric + REPSAGA
- [x] `test/unit/features/workouts/ui/post_session/share/variants/share_card_discreet_test.dart`
- [x] `lib/features/workouts/ui/post_session/share/share_card_renderer.dart` — composer (photo zone | discreet flood) + variant overlay
- [x] `test/unit/features/workouts/ui/post_session/share/share_card_renderer_test.dart`
- [x] `test/unit/features/workouts/ui/post_session/share/share_card_renderer_golden_test.dart` — 3 goldens (A baseline, B PR, Discreet class-change)
- [x] `dart format .` + `dart analyze --fatal-infos` + `flutter test test/unit/features/workouts/` final gates (522 tests passing)
- [x] commits split across 4 atomic groups: `b9a911f` (payload tests) → `f3497cf` (3 variants) → `675bf81` (renderer) → `c7abcda` (goldens + closeout)

**Pass 2 checklist (in flight):**

- [x] Pin compatible versions for `image_picker` / `share_plus` / `permission_handler` against Flutter SDK 3.11.4 (held `share_plus` at 10.1.4 — 11.x bumps Dart min beyond 3.11.4)
- [x] `pubspec.yaml` — add the three deps + explicit `cross_file` / `path_provider` (transitive promotion to keep imports declared)
- [x] `flutter pub get` resolves cleanly
- [x] `android/app/src/main/AndroidManifest.xml` — `<uses-permission android:name="android.permission.CAMERA"/>` + `<queries>` intents (IMAGE_CAPTURE / GET_CONTENT / PICK image/*)
- [x] `flutter build apk --debug` compiles (no Kotlin/Gradle/SDK friction)
- [x] `lib/features/workouts/data/share_image_renderer.dart` — DI seams (`BoundaryResolver` / `ImageEncoder` / `TempDirResolver` / `NowMillis`) + 1.2MB overflow → pixelRatio-2.0 retry + PNG output (TODO(pass-3) for JPEG via `image` pkg)
- [x] `test/unit/features/workouts/data/share_image_renderer_test.dart` — 8 cases (pixelRatio fwd, .png suffix, deterministic filename, non-null XFile, retry on overflow, no-retry-when-small, no-retry-below-fallback, StateError on detached key)
- [x] `lib/features/workouts/data/share_service.dart` — `pickFromCamera` / `pickFromGallery` / `share(file, text:)` / `requestCameraPermission` / `cameraPermissionStatus`; DI via `ImageSourcePicker` / `FileShareSink` / `PermissionRequester` / `PermissionStatusReader` typedefs
- [x] `test/unit/features/workouts/data/share_service_test.dart` — 10 cases covering each method + cancel/denial/permanentlyDenied paths
- [x] `dart format .` + `dart analyze --fatal-infos` (project-wide, 0 issues) + `flutter test test/unit/features/workouts/` (540 / 540 pass; +18 over Pass 1's 522)
- [x] commits split across 3 groups: `e7262d8` (deps + manifest) → `4c557ad` (renderer + tests) → `62bdf92` (share service + tests)

**Pass 3 checklist (complete):**

- [x] Group A — `SharePayload.rankProgressFraction` field + `bpProgressFractionAfter` parameter on `fromPostSessionState`; drops the `(rank % 10) / 10` placeholder from the renderer + regenerated 3 goldens (commit `454dc33`)
- [x] Group B — `ShareController` (Riverpod `Notifier`) state machine `idle → pickingPhoto → preview → rendering → sharing → idle` with `cancelled` / `error` branches; `shareServiceProvider` + `shareImageRendererProvider` DI seams; 12 behavior-not-wiring tests covering all transitions (commit `6e23d54`)
- [x] Group C — `ShareSheet` bottom-modal (3 rows: camera / gallery / discreet) with permanentlyDenied-hides-camera rule; `ShareLocalizations` value-object bridge (Decoupling Rule 2); 7 widget tests (commit `66c3a6c`)
- [x] Group D — `SharePreviewScreen` with 1080×1920 offscreen `RepaintBoundary` + FittedBox-scaled visible preview; A↔B variant toggle (locked on Discreet); retake + share CTAs; tap-to-hide XP/PR overlays; vertical drag-to-reframe via `Transform.translate`; 8 widget tests (commit `90fab21`)
- [x] Group E — ARB keys (13 new strings in `app_en.arb` + `app_pt.arb`); rewrote `ShareCtaButton` as a `ConsumerStatefulWidget` that opens the sheet + pushes `SharePreviewScreen` on the controller's preview transition; `PostSessionState.bpProgressFractionAfter` field; `PostSessionSummaryPanel` constructor took `sharePayload` / `shareCardStrings` / `shareLocalizations` params; updated 12 summary-panel tests + 4 goldens (commit `6923c41`)
- [x] Group F — `test/e2e/specs/share_flow.spec.ts` (4 tests @smoke) + `SHARE_FLOW` selector map; final gates green: `dart format` + `dart analyze --fatal-infos` (0 issues) + `flutter test test/unit/` (**2061 / 2061 pass; +1494 over Pass 2's 540 — includes all suites, not just workouts**) + `flutter build apk --debug` succeeded
- [x] Carry-forwards documented in final report: `VitalityStateStyles.bodyPartColor` layer violation deferred to PR 30c; Mystery glyph in Variant A golden flagged for physical-Android visual verification at ship time; sheet permission read is sync-at-mount (acceptable per mockup §7).

**Branch:** `feature/30b-share-card` off `main` (after 30a merges).

**Scope summary**

- Add three new pubspec dependencies: `image_picker` (camera + gallery), `share_plus` (native share sheet + camera roll save), `permission_handler` (graceful camera permission denial). All Context7-verified for current Flutter SDK 3.11.4.
- Implement the 4-screen capture/preview/export flow (mockup §7): bottom sheet → camera/gallery → preview → native share sheet.
- Implement **Variant A (Minimal Strip)** + **Variant B (Full Bleed corner collars)** + **Discreet mode** share-card renderers (mockup §6) using `RepaintBoundary` + `RenderRepaintBoundary.toImage(pixelRatio: 3.0)` at 1080×1920 9:16, JPEG quality 88.
- Wire the **summary panel share CTA** (placeholder added in 30a) to open the bottom sheet.
- Toggle controls on preview screen: tap-to-hide XP / tap-to-hide PR / drag-to-reframe / Variant A↔B toggle / retake.
- Permission deny path: graceful — "Tirar foto" disappears from bottom sheet if camera permission denied, no re-prompt.

**Files created**

- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\share_card_renderer.dart` — pure widget that composes (photo | discreet-flood) + overlay (Variant A | Variant B). Used both as the visible preview AND as the offscreen `RepaintBoundary` for export.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\variants\share_card_variant_a.dart` — bottom strip layout. Hue accent + XP + (optional) PR line + bar + REPSAGA wordmark.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\variants\share_card_variant_b.dart` — top + bottom collar layout with `clip-path: polygon` equivalent (Flutter `CustomClipper<Path>`). Class + PR + lift detail + XP.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\variants\share_card_discreet.dart` — no-photo cinematic still. Hue flood + slash + d-hero numeric + REPSAGA.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\share_sheet.dart` — modal bottom sheet (step 1): TIRAR FOTO + ESCOLHER DA GALERIA + Sem foto.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\share_preview_screen.dart` — full-screen preview (step 3): photo zone + overlay + variant toggle + retake + share button. Drag-to-reframe gesture + tap-to-hide affordances.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\domain\share_payload.dart` — pure model. Composes from `(WorkoutSummary, CelebrationQueueResult)`: dominant BP, XP, PR (if any), class, body-part rank progress. Drives the variant renderers.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\data\share_image_renderer.dart` — service. `Future<XFile> render({required GlobalKey repaintKey, double pixelRatio = 3.0, int jpegQuality = 88})`. Wraps `RenderRepaintBoundary.toImage` + JPEG encode + `path_provider` temp file. Returns the temp file path.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\data\share_service.dart` — repository layer. Wraps `share_plus.Share.shareXFiles` + `image_picker.ImagePicker.pickImage`. Single source of truth for sharing IO.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\providers\share_controller.dart` — `AsyncNotifier` orchestrating: pick photo → render → share. Handles permission denial path.

**Files modified**

- `C:\Users\caiol\Projects\repsaga\pubspec.yaml` — add `image_picker` (pin version per Context7), `share_plus` (pin), `permission_handler` (pin). Specific versions deferred to tech-lead at PR open — must use Context7 `query-docs` per CLAUDE.md.
- `C:\Users\caiol\Projects\repsaga\android\app\src\main\AndroidManifest.xml` — add `<uses-permission android:name="android.permission.CAMERA"/>` + `<queries><intent>` block for `image_picker` per its README.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\summary\share_cta_button.dart` — replace the 30a placeholder snackbar with `shareSheet.open(context, payload: …)`.
- `C:\Users\caiol\Projects\repsaga\lib\l10n\app_en.arb` + `app_pt.arb` — add ~8 new keys (share flow labels).
- `C:\Users\caiol\Projects\repsaga\test\e2e\helpers\selectors.ts` — add share-flow selectors. **E2E NOTE:** image_picker/share_plus on Flutter web fall back to browser native APIs which Playwright cannot fully drive — share-flow E2E coverage stays widget-level. Web build keeps the share CTA but the picker shows a browser file-input.
- `C:\Users\caiol\Projects\repsaga\test\e2e\fixtures\` — add a `fixtures/share-card-photo.jpg` sample photo for preview testing where applicable.

**Files deleted** — none.

**Dependencies**

- Merges after 30a. The summary panel `share_cta_button.dart` exists as a placeholder in 30a; 30b wires it up. If 30a is delayed, 30b can be split: variant renderers (no IO) ship independently as widget tests; permission + picker + share wiring lands when 30a's CTA is available.
- New pubspec deps. **Tech-lead MUST run Context7 `query-docs` on `image_picker`, `share_plus`, `permission_handler` before pinning versions** — see CLAUDE.md "Library API lookups". The versions are deferred to PR-open time, not specified in this plan, because Flutter SDK 3.11.4 minor version compatibility matters.

**Acceptance criteria**

1. `flutter build apk --debug` succeeds with the 3 new pubspec deps and the Android manifest permissions.
2. Bottom sheet → tap "TIRAR FOTO" → `image_picker.pickImage(source: ImageSource.camera)` invoked; mocked in tests.
3. Bottom sheet → tap "ESCOLHER DA GALERIA" → `image_picker.pickImage(source: ImageSource.gallery)` invoked.
4. Bottom sheet → tap "Sem foto · só a saga" → directly proceeds to preview with discreet variant.
5. Preview screen: tap A/B toggle → variant switches (verified by widget hierarchy diff).
6. Preview screen: tap "↻ refazer" → returns to bottom sheet.
7. Preview screen: tap share → `share_image_renderer.render` produces a 1080×1920 JPEG ≤ 1.2MB; `share_plus.shareXFiles` invoked with the file.
8. Permission denied path: `permission_handler.Permission.camera.request()` returns `denied` → bottom sheet renders WITHOUT the "TIRAR FOTO" option; "ESCOLHER DA GALERIA" + "Sem foto" remain.
9. Render-to-image golden test: at 1080×1920 with a fixed mock photo + fixed `SharePayload`, the rendered bytes match a stored golden fixture (Variant A baseline, Variant B PR, Discreet class-change — 3 goldens).
10. `make ci` green including Android debug build.

**Test coverage plan**

| File | Type | What it pins |
|---|---|---|
| `test/unit/features/workouts/domain/share_payload_test.dart` | unit | Compose from `WorkoutSummary + queueResult`: dominant BP selection, PR carry, class carry. 8 cases mirroring mockup §5 states. |
| `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_a_test.dart` | widget | Hue accent matches dominant BP; PR line conditional; XP renders. |
| `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_b_test.dart` | widget | Top + bottom collar layout; clip-path renders (verified by RenderObject `Clip.antiAlias`). |
| `test/unit/features/workouts/ui/post_session/share/variants/share_card_discreet_test.dart` | widget | Discreet flood + slash + d-hero + d-wordmark. Hue swap on class-change. |
| `test/unit/features/workouts/ui/post_session/share/share_card_renderer_golden_test.dart` | golden | 3 goldens (A baseline, B PR, Discreet class-change) at 1080×1920. |
| `test/unit/features/workouts/ui/post_session/share/share_sheet_test.dart` | widget | Permission denied → camera option removed; "Sem foto" present in all states. |
| `test/unit/features/workouts/ui/post_session/share/share_preview_screen_test.dart` | widget | A↔B toggle; retake; tap-to-hide XP; tap-to-hide PR; drag-to-reframe (verified by gesture detector callback). |
| `test/unit/features/workouts/data/share_image_renderer_test.dart` | unit | Mocked `RepaintBoundary.toImage`; assert JPEG bytes < 1.2MB at quality 88; assert temp file cleanup. |
| `test/unit/features/workouts/data/share_service_test.dart` | unit | Mocktail-backed; verify `share_plus.shareXFiles` called with correct args; permission denial returns Result.denied. |
| `test/widget/features/workouts/providers/share_controller_test.dart` | widget | End-to-end: tap CTA → sheet opens → mock picker returns file → preview shows → tap share → service called. |
| `test/e2e/specs/share_flow.spec.ts` | E2E (new) | Tagged `@smoke`. Smoke only — Playwright drives bottom-sheet open + variant toggle + "Sem foto" → preview. Camera/gallery picker assertions skipped on web (browser native UI). |

**l10n surface** — ~10 new keys:

| Key | pt-BR | en |
|---|---|---|
| `shareSheetTitle` | "Compartilhar saga" | "Share saga" |
| `shareTakePhoto` | "📷 TIRAR FOTO" | "📷 TAKE PHOTO" |
| `shareFromGallery` | "🖼 ESCOLHER DA GALERIA" | "🖼 FROM GALLERY" |
| `shareNoPhoto` | "Sem foto · só a saga" | "No photo · saga only" |
| `sharePreviewRetake` | "↻ refazer" | "↻ retake" |
| `sharePreviewMinimal` | "Mínimo" | "Minimal" |
| `sharePreviewBold` | "Destaque" | "Bold" |
| `shareCardWordmark` | "REPSAGA" | "REPSAGA" |
| `sharePermissionDenied` | "Permissão da câmera negada." | "Camera permission denied." |
| `shareRenderError` | "Não foi possível gerar a imagem." | "Could not generate the image." |

**Migration / data shape changes**

- New pubspec deps; bump locks via `flutter pub get`.
- Android manifest gains `CAMERA` permission + `image_picker` intent query block (no autoGoogle deps changes).
- No SQL, no Hive.

**Risks + mitigations**

| Risk | Mitigation |
|---|---|
| `image_picker` API shape changed between training-data version and pinned version | Context7 `query-docs` first; pin to current stable. Read the changelog for breaking changes since SDK 3.11.4 launched. |
| `RepaintBoundary.toImage` returns black on Flutter web | Document web limitation; share-flow gated to native platforms on web (CTA hidden). Verify in widget test on web build. |
| 1080×1920 render at pixelRatio 3.0 exceeds 1.2MB budget | Pixel ratio falls back to 2.0 if encoded size > 1.2MB; documented in `share_image_renderer.dart`. |
| Permission re-prompt on every share open feels intrusive | `permission_handler` is invoked **only on TIRAR FOTO tap**, not on bottom sheet open. Permission state cached per session. |
| Saving to camera roll fails silently on Android Q+ scoped storage | `share_plus.shareXFiles` uses `Intent.ACTION_SEND` which doesn't require WRITE_EXTERNAL_STORAGE on Q+; verified by integration test. |
| Drag-to-reframe gesture conflicts with native scroll on preview | Preview screen is full-screen; no scroll parent. `GestureDetector` is the only consumer. |

---

### PR 30c — Cleanup + deprecate PR celebration screen + final E2E migration + docs

**Branch:** `feature/30c-post-session-cleanup` off `main` (after 30b merges).

**Scope summary**

- Delete `pr_celebration_screen.dart` (476 LOC) and its route `/pr-celebration`. The post-session screen subsumes it — PR confirmation lives in B3 PR cut + summary panel detail row.
- Remove the deprecated overlay selector aliases from `test/e2e/helpers/selectors.ts` that PR 29.5 kept around for one cycle.
- Final E2E pass: grep every `specs/*.spec.ts` for stale references to `pr-celebration`, `rank-up-overlay`, `level-up-overlay`, `first-awakening-overlay`, `title-unlock-sheet`, `class-change-overlay`. Replace remaining hits or delete the assertions.
- Condense Phase 30 in `docs/PROJECT.md` §4: 4-5 bullets per PR. Move full spec from this WIP.md section to git history. Mark `mockup-v2.html` as canonical reference (keep in `docs/`).
- Add auto-memory entry `project_phase_30_post_session.md` capturing: cinematic 3-beat structure (Path A — no mid-workout flash layer; post-session screen carries the full celebration), slot-policy, RewardTier derivation (Threshold-anticipatory variant accepts `hasPR || hasRankUp`), share-card pipeline, EQUIP migration from mid-workout to post-session summary panel.
- Add cluster ledger row in PROJECT.md §0 if any new pattern emerged during 30a/30b that's worth grep-tagging future bugs.
- Remove `docs/WIP.md` Phase 30 section entirely (this section).
- **Test-hygiene audit** (absorbed from #252's discovery — user directive 2026-05-21). Apply the per-test reseed pattern from `28d67d6` (crash-recovery) + `e2e089e` (weekly-plan) to the 3 remaining audit candidates flagged during #252:

  | Spec | Logins / Reseeds | Risk under Phase 30 SQL chain |
  |---|---|---|
  | `test/e2e/specs/workouts.spec.ts` | 17 / 0 | Highest — deepest workout state, most tests |
  | `test/e2e/specs/personal-records.spec.ts` | 2 / 0 | PR tracking depends on prior peak state |
  | `test/e2e/specs/offline-sync.spec.ts` | 3 / 0 | Hive box state leaks across tests |

  Per spec: add a per-spec `reseed<UserName>User()` helper that cleans (workouts cascade + xp_events + body_part_progress + exercise_peak_loads + exercise_peak_loads_by_rep_range + personal_records + earned_titles + backfill_progress), call it in `beforeEach` before login, add `test.describe.configure({ mode: 'serial' })` for intra-worker safety under `--repeat-each`. Acceptance: each spec runs green at `--workers=4 --repeat-each=3`.

  Estimated added scope: ~400-600 LOC (~120 LOC per spec × 3 + shared helper extraction).

**Files created**

- `C:\Users\caiol\.claude\projects\C--Users-caiol-Projects-repsaga\memory\project_phase_30_post_session.md` — auto-memory entry indexed in MEMORY.md.

**Files modified**

- `C:\Users\caiol\Projects\repsaga\docs\PROJECT.md` — §4 Completed Phases gets a "Phase 30 — Post-session cinematic" entry with 4 sub-bullets (PR 29.5 / 30a / 30b / 30c). Progress snapshot table gets 4 new rows. Cluster Ledger adds rows if applicable.
- `C:\Users\caiol\Projects\repsaga\docs\WIP.md` — remove the entire Phase 30 implementation plan section (kept until 30c merges).
- `C:\Users\caiol\Projects\repsaga\lib\core\router\app_router.dart` — remove the `/pr-celebration` route.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\coordinators\post_workout_navigator.dart` — strip the deprecated PR-celebration branch entirely; `prResult` is consumed by the post-session screen, not the navigator.
- `C:\Users\caiol\Projects\repsaga\test\e2e\helpers\selectors.ts` — delete the deprecated alias section added in PR 29.5.
- `C:\Users\caiol\Projects\repsaga\test\e2e\specs\workouts.spec.ts` (+ any other spec referencing `pr-celebration`) — replace assertions with post-session route assertions.
- `C:\Users\caiol\.claude\projects\C--Users-caiol-Projects-repsaga\memory\MEMORY.md` — add the new project entry to the index.

**Files deleted**

- `C:\Users\caiol\Projects\repsaga\lib\features\personal_records\ui\pr_celebration_screen.dart` (476 LOC)
- All `pr_celebration_screen_test.dart` + `pr_celebration_screen_golden_test.dart` files.

**Dependencies**

- Merges after 30b. Cannot strip `pr_celebration_screen.dart` while the route is still wired.
- Final phase — closes Phase 30.

**Acceptance criteria**

1. `flutter analyze --fatal-infos` green after deletions; no dangling imports.
2. `grep -rn "pr-celebration" lib/ test/` returns zero hits.
3. `grep -rn "rank-up-overlay\|level-up-overlay\|first-awakening-overlay\|title-unlock-sheet\|class-change-overlay" test/` returns zero hits.
4. PROJECT.md §4 has the Phase 30 condensed entry (4 bullets).
5. WIP.md Phase 30 section deleted.
6. Auto-memory `project_phase_30_post_session.md` written + indexed.
7. `make ci` green. Full E2E run green.

**Test coverage plan** — no new tests. Verify existing post-session + share-flow E2E specs still pass after the PR-celebration route is gone.

**l10n surface** — none.

**Migration / data shape changes** — none.

**Risks + mitigations**

| Risk | Mitigation |
|---|---|
| Dropping `/pr-celebration` route breaks a deep link a user has bookmarked | The route was internal-only, never deep-linked. Hash-route URLs on web aren't share-stable. No risk. |
| Memory entry overlaps existing entries | Cross-reference + dedupe at index time. Run `grep` in MEMORY.md for prior post-session entries. |
| Lingering text search in non-spec files (e.g. comments) | Acceptable — comments referencing deleted widgets surface as drift but don't block. Reviewer may request scrubbing in same PR. |

---

### Critical path / dependency graph

```
PR 29.5  ─────────►  MERGED (#255, 2026-05-22, Path A pivot)
                     Retired 5 legacy mid-workout overlays (1656 LOC); scaffolded
                     CelebrationEvent.personalRecord variant + CelebrationQueue.SlotPolicy
                     enum for post-session consumption. celebration_player → pass-through.
                                                                     │
                                                                     ▼
PR 30a   ─────────────────────────►  post-session screen + state machine + summary panel + finish-coord wiring + EQUIP migration
                                                                     │
                                                                     ▼
PR 30b   ─────────────────────────►  share card pipeline (depends on 30a's CTA placeholder)
                                                                     │
                                                                     ▼
PR 30c   ─────────────────────────►  cleanup: deprecate pr_celebration_screen + final E2E migration + docs

Phase 29 PR 2 (#252) and PR 3 (#253) MERGED on a parallel track — no file overlap with Phase 30.
```

**Total estimated PR LOC** (excluding tests + l10n):
- PR 29.5: **−3577 LOC actual** (1656 LOC of legacy overlays retired + 1037 LOC of v1 mockup deleted) + 1011 LOC additions (PersonalRecordEvent variant + SlotPolicy enum + 9 SlotPolicy + 3 PR equality unit tests + extracted flipbook + Path A rationale docs). Bigger reduction than originally estimated because Path A pivot killed the planned `thin_flash_overlay.dart` widget entirely.
- PR 30a: ~2400 LOC across screen, state machine, 7 cut widgets, summary panel, choreographer, coordinator wiring
- PR 30b: ~1500 LOC across share pipeline + variant renderers + permission handling
- PR 30c: −476 (pr_celebration_screen) + ~100 (docs + auto-memory) ≈ **net −376 LOC**

Phase 30 cumulative net: ~−50 LOC, with **~2820 LOC of legacy retired** (1656 overlays + 1037 mockup-v1 + 476 pr_celebration_screen). Net feature surface is ≈+2770 LOC of additions offset by ~2820 LOC of legacy retirement.

### CI considerations

| Gate | Status | Where |
|---|---|---|
| `scripts/check_typography_call_sites.sh` | EXISTING · enforced | Continues to enforce — new post-session widgets must use AppTextStyles. Reviewer flags any raw `TextStyle(fontFamily:)` in new files |
| `scripts/check_exercise_translation_coverage.sh` | EXISTING · unaffected | No new default exercises shipped in Phase 30 |
| `dart analyze --fatal-infos` | EXISTING · enforced | New widget files must pass; unused_import will catch leftover imports from deleted overlays |
| Golden test reference goldens | NEW · 30a + 30b | 10 post-session state goldens (30a) + 3 share-card goldens (30b). Stored in `test/unit/.../goldens/` per Flutter convention. Re-baseline only on intentional design changes; reviewer must approve baseline updates |
| E2E smoke gate | EXISTING · enforced | New specs (`celebration_flashes.spec.ts` in 29.5, `post_session.spec.ts` in 30a, `share_flow.spec.ts` in 30b) all tagged `@smoke` |
| Android debug APK build | EXISTING · enforced | Critical for PR 30b due to manifest + Kotlin compile of new deps |

### E2E selector migration table

| PR | Old identifier | New identifier | Notes |
|---|---|---|---|
| 29.5 | `[flt-semantics-identifier="rank-up-overlay"]` + 4 sibling overlay identifiers (`level-up-overlay`, `first-awakening-overlay`, `title-unlock-sheet`, `class-change-overlay`) | DELETED (Path A) | All 5 legacy mid-workout overlay identifiers retired with the widgets in PR 29.5; no thin-flash replacement selectors (Path A killed the widget). E2E specs that previously asserted overlay visibility now assert URL navigation + DB parity only. |
| 30a | `[flt-semantics-identifier="pr-celebration-screen"]` | `[flt-semantics-identifier="post-session-screen"]` | Route + screen renamed; legacy `/pr-celebration` route alive until 30c |
| 30a | (none) | `[flt-semantics-identifier="post-session-b1-xp"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-b2-tally"]` | New (`variant=single|sequential|cascade|elevated`) |
| 30a | (none) | `[flt-semantics-identifier="post-session-b3-pr"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-b3-title"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-b3-class-change"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-summary"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-continue-cta"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-title-equip-row"]` | New (replaces `title-unlock-sheet-equip-button`) |
| 30a | (none) | `[flt-semantics-identifier="empty-session-guard-sheet"]` | New |
| 30b | (none) | `[flt-semantics-identifier="share-sheet"]` | New |
| 30b | (none) | `[flt-semantics-identifier="share-preview-screen"]` | New |
| 30b | (none) | `[flt-semantics-identifier="share-variant-toggle"]` | New (Minimal ↔ Destaque) |
| 30c | All deprecated aliases | DELETED | Final scrub |

### Open questions for user — **RESOLVED 2026-05-21**

All 9 questions answered by user; **all plan defaults accepted**. Locked decisions:

1. **rank_up_overlay.dart RETIRED** along with the other 4 widgets (5 retired total). Originally planned to flow through `thin_flash_overlay.dart`; under the Path A pivot (2026-05-22) no replacement widget shipped — all 5 event types now pass through to the post-session screen carrying the full celebration (PR 30a).
2. **PR detection fires DURING FINISH-DRAIN only**, not per-set real-time. Same path as rank-up.
3. **PR 29.5 dispatches AFTER #252 merges** (Phase 29 PR 2). Serial timeline.
4. Baseline B1 copy alternates via **session-number % 2** between "ENCERRADO. MAIS FORTE." and "CONSISTÊNCIA VENCE."
5. Share CTA visible when queue contains **any of PR / rank-up / title / class-change**.
6. Title EQUIP success → **"Equipado ✓" inline, no auto-advance**.
7. **Post-session screen is ephemeral**, fires once per finish, never replayable from history.
8. **Long-press skip disabled on the summary panel** (avoids ambiguity with EQUIP row tap).
9. **Web platform: Android-first**. Share preview renders; export uses `navigator.share()` if available else download link. Documented as known limitation.

Historical question text preserved below for traceability.

---

1. **PR 29.5 retains `rank_up_overlay.dart`?** The mockup §4½ lists rank-up as a NEW mid-workout flash variant ("Replaces · (no current overlay — added)") — meaning the existing 491-LOC `rank_up_overlay.dart` is the POST-finish overlay used by `celebration_player`, not a mid-workout one. The plan currently retires it along with the other 4 because `thin_flash_overlay.dart` is the single dispatch target for `celebration_player` post-redesign. Is that the intent? Or should rank-up keep its rich 1100ms post-finish ceremony while only being added as a mid-workout flash variant? **Plan default:** retire `rank_up_overlay.dart` along with the others; post-finish celebrations all play as 400ms flashes (consistent with the mockup's "mid-workout = brief environmental notification" framing). Confirm or override.

2. **PR ordering vs Phase 29 PR 2 (#252) and PR 3.** Both are in flight on parallel tracks. The plan assumes Phase 29 PRs are merged or independent. Confirm: dispatch PR 29.5 immediately after Phase 29 PR 2 merges (current sequence), or before? Phase 30 only depends on the celebration event surface, not the XP formula. **Plan default:** wait for #252 to merge, then dispatch 29.5 off main.

3. **B1 baseline copy alternation.** Mockup §5 State 2 script says "ENCERRADO. MAIS FORTE." alternates with "CONSISTÊNCIA VENCE." session-over-session, "alternation seeded from session number; deterministic." The plan has both as separate ARB keys; the alternation logic lives in `RewardTier.derive` (returns one of two for baseline tier based on `workoutSessionNumber % 2`). Confirm that's the right hook — or should the alternation be more complex (e.g. weighted, time-of-day, mood-based)? **Plan default:** session-number-modulo-2 alternation, no more complexity.

4. **PR detection source-of-truth for the mid-workout flash.** PRs are detected per-workout in `peak_loads_repository.dart` at finish time. Should the mid-workout PR flash (mockup §4½ variant — new!) fire AT THE MOMENT the set is logged (requires real-time peak comparison on every set save) or DURING the celebration drain at finish? **Plan default:** during the finish drain only — same path as rank-up. Real-time per-set PR detection is a follow-up if telemetry shows users miss the mid-workout PR moment. Confirm or escalate.

5. **Share CTA visibility rule.** Mockup §5 shows the share CTA on State 3 (PR), 4 (multi-PR), 5 (rank-up), 6 (multi rank-up), 8 (title), 9 (class change), 10 (max combo). NOT on State 1 (day-zero), 2 (baseline), or 7 (level-up). The plan implements this as "show share CTA when `queueResult` contains ANY of: PR, rank-up, title, class-change." Confirm.

6. **Title EQUIP success behavior.** When the user taps EQUIPAR in the summary panel and the RPC succeeds, the plan updates the row to "Equipado ✓" inline and the user can still tap CONTINUAR to leave. No auto-advance. Confirm — or should equipping auto-advance to home?

7. **Backfill: should the post-session screen replay for the in-flight workout if the user backs out and re-enters via history?** The plan locks: post-session is ephemeral, fires once per finish, never replayable from history. History details remain on the workout-detail screen. Confirm.

8. **Skip-to-skip gesture range.** Long-press 500ms anywhere → jump to summary. Does that include the summary panel itself (no-op) and the title EQUIP row (would be ambiguous)? **Plan default:** long-press disabled once the summary panel is visible; the title row has its own tap target inside that surface. Confirm.

9. **Web platform parity.** PR 30b's share flow degrades gracefully on Flutter web (browser file-input vs native picker; no camera roll save). Is web parity a blocker for launch, or is it acceptable as a known limitation that surfaces a "Use the mobile app for the full share experience" hint? **Plan default:** Android-first; web shows the share preview but the export goes through `navigator.share()` if available, else a download link. Documented as known limitation.

---

## Compact-restore checklist

When restoring after `/compact`:

1. Re-read this WIP.md FIRST — Phase 30 plan is the canonical section.
2. Phase 29 is FULLY SHIPPED (PRs #251, #252, #253 all merged; migration `00065` on hosted Supabase). No Phase 29 state to track.
3. Read `docs/post-session-screen-mockup-v2.html` if any Phase 30 work resumes (locked spec).
4. If user authorizes PR 30a dispatch → tech-lead reads `lib/features/rpg/models/celebration_event.dart` (post-Path-A, includes `personalRecord` variant) + `lib/features/rpg/domain/celebration_queue.dart` (includes `SlotPolicy` enum) + `lib/features/rpg/ui/celebration_player.dart` (pass-through; PR 30a re-wires this to surface events into the post-session screen state machine) + `lib/features/workouts/ui/coordinators/celebration_orchestrator.dart` (saga-intro wait + pulse-write only post-Path-A) + `lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart` (route push site) + `lib/features/personal_records/ui/pr_celebration_screen.dart` (legacy, retires in PR 30c) before writing the new post-session screen + state machine + 7 cut widgets + summary panel.
5. Auto-memory entries referenced by the plan: `project_phase_29_v2_formula.md`, `feedback_pr_decomposition_parity_invariant.md`, `feedback_engineering_quality_bar.md`, `feedback_design_token_sweep_on_new_tokens.md`, `feedback_widget_l10n_parameterization.md`

## Active background processes

None. Phase 29 fully merged (PRs #251, #252, #253). PR 29.5 merged (#255, Path A pivot). Phase 30 post-merge docs cleanup landed via #256 (PROJECT.md condense), #257 (mockup-v2 UX-critic Path A drift audit), and this PR (WIP.md drift cleanup). Ready for next dispatch: **PR 30a post-session screen + state machine** — mockup-v2 §5–§8 + WIP.md PR 30a section both now Path-A-clean.
