# `lib/core/theme/` — Arcane Ascent Design System

RepSaga's Material Design 3 theme, palette, typography and icon system.
Direction is the locked "Arcane Ascent" design language (Direction B in
the Phase 17.0c material-vs-pixel review), replacing the pixel-art
direction that shipped and was torn down in Phase 17.0c. See
`docs/PROJECT.md` Phase 17 and Phase 26 entries for the design-language
history.

---

## Reward scarcity rule (non-negotiable)

**`AppColors.heroGold` (`#FFB800`) is a reward signal, not a paint color.**

The daily app uses deep violet and `hotViolet` for interactive affordances.
Gold is reserved for:

- Personal-record flashes
- Level-up bursts
- Streak-milestone badges
- First-week onboarding warmth moments (explicitly allowed per PO research)

Any gold that appears on a weekday UI at rest means the system is broken.
Dopamine adapts to predictable stimulants; the variable-ratio reward framing
is what makes the color feel earned three months in.

### Enforcement

- `RewardAccent` (`lib/shared/widgets/reward_accent.dart`) is the **only**
  widget in the codebase allowed to consume `AppColors.heroGold`. Every other
  reference — screens, widgets, painter code — must go through it.
- `scripts/check_reward_accent.sh` grep-lints for
  `heroGold` / `0xFFFFB800` / `0xFFFFC107` / `0xFFFFD54F` outside
  `reward_accent.dart` + the token definition in `app_theme.dart`. It runs
  before `dart analyze` in `make analyze` / `make ci`.
- Custom painters and other non-widget consumers (e.g. `fl_chart` dot
  painters) that need the reward color read it via `RewardAccent.color`
  instead of `AppColors.heroGold` — this keeps the gold reference inside
  the `RewardAccent` file and therefore inside the scarcity budget.

## Palette summary

| Token | Hex | Role |
|-------|-----|------|
| `abyss` | `#0D0319` | App background |
| `surface` | `#1A0F2E` | Cards, sheets |
| `surface2` | `#241640` | Elevated surfaces, input fields |
| `primaryViolet` | `#6A2FA8` | Primary CTAs, tab indicator, FAB |
| `hotViolet` | `#B36DFF` | Active nav, links, selected states |
| `heroGold` | `#FFB800` | **REWARD ONLY** (via `RewardAccent`) |
| `textCream` | `#EEE7FA` | Primary text |
| `textDim` | `#9C8DB8` | Secondary text, captions |
| `success` | `#62C46D` | Positive deltas, done chips |
| `warning` | `#FFB84D` | Warnings (distinct from `heroGold`) |
| `error` | `#FF6B6B` | Errors, destructive |
| `hair` | `rgba(179,109,255,0.14)` | Dividers, card borders |

Raw `Color(0x…)` / `Colors.black*` / `Colors.white*` are linted out by
`scripts/check_hardcoded_colors.sh` under `lib/features/`. Use a palette
token or annotate with `// ignore: hardcoded_color` when the literal is
intentional.

## Typography

Two families, bundled directly via `pubspec.yaml > flutter.fonts:`:

- **Rajdhani** — display, headline, numeric. Condensed humanist sans,
  reads fast under gym fatigue at 18+ dp. Bundled weights: 500/600/700.
- **Inter** — title, body, label. Covers 11-16 dp reading. Bundled
  weights: 400/600.

Both families load synchronously through `TextStyle(fontFamily:
'Rajdhani')` / `'Inter'` references inside `AppTextStyles`. The
`google_fonts` package is forbidden in production code paths (Phase 27
L14: its async API silently fell back to Inter on real-device release
builds, breaking the entire two-family identity). `main.dart` locks
`GoogleFonts.config.allowRuntimeFetching = false` as defence-in-depth;
`scripts/check_typography_call_sites.sh` lints out `GoogleFonts.*` calls
and stray `google_fonts` imports under `lib/features/` + `lib/shared/`.
See `AppTextStyles` dartdoc in `app_theme.dart` for the loading contract.

One display family, one body family, one numeric family. Three families
max. See `AppTextStyles` for the token set.

PressStart2P, Cinzel and Cormorant are explicitly rejected (see PROJECT.md
§17.0c for rationale).

## Icons

`AppIcons` (`app_icons.dart`) exposes inline-SVG icons rendered via
`flutter_svg`. Roughly 20 icons covering navigation, verbs, state.

- The **lift icon** is a side-view barbell with asymmetric rectangle plates.
  Never a circle-on-stick (that's a dumbbell) and never a generic gym emoji.
- Monoline stroke is the default; filled variants exist for selected-nav
  states.

## Radii

`radii.dart` exports `kRadiusSm` (8), `kRadiusMd` (12), `kRadiusLg` (16),
`kRadiusXl` (24). Default Material card rounding is `kRadiusMd`; inputs
and buttons use `kRadiusSm + 2` (10 dp).
