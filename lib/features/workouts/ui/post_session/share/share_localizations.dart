import '../../../../../l10n/app_localizations.dart';

/// Pre-localized string bundle for the share-card flow.
///
/// **Decoupling Rule 2 — widget l10n parameterization.** The share widgets
/// (sheet, preview, error states) never call `AppLocalizations.of(context)`
/// directly. The screen layer resolves every needed key once via
/// [ShareLocalizations.from] and passes the bundle as a constructor param.
/// This keeps the widgets unit-testable without staging an ARB harness.
///
/// **Why a flat value object instead of nesting an [AppLocalizations]?**
/// The set of keys the share flow needs is small (~11) and well-defined.
/// A typed bundle catches a missing key at the screen-layer boundary
/// (compile-time, single touchpoint) instead of at the widget-tree-render
/// boundary (runtime, scattered across files).
class ShareLocalizations {
  const ShareLocalizations({
    required this.sheetTitle,
    required this.takePhoto,
    required this.fromGallery,
    required this.noPhoto,
    required this.previewRetake,
    required this.previewShare,
    required this.wordmark,
    required this.permissionDenied,
    required this.permissionPermanentlyDenied,
    required this.renderError,
    required this.openSettings,
    required this.modeBestiary,
    required this.modeCleanFlex,
  });

  /// Bridge from the generated [AppLocalizations] to the typed bundle.
  /// Single touchpoint between the share widgets and the ARB layer.
  factory ShareLocalizations.from(AppLocalizations l10n) {
    return ShareLocalizations(
      sheetTitle: l10n.shareSheetTitle,
      takePhoto: l10n.shareSheetTakePhoto,
      fromGallery: l10n.shareSheetFromGallery,
      noPhoto: l10n.shareSheetNoPhoto,
      previewRetake: l10n.sharePreviewRetake,
      previewShare: l10n.sharePreviewShare,
      wordmark: l10n.shareWordmark,
      permissionDenied: l10n.sharePermissionDenied,
      permissionPermanentlyDenied: l10n.sharePermissionPermanentlyDenied,
      renderError: l10n.shareRenderError,
      openSettings: l10n.shareOpenSettings,
      modeBestiary: l10n.shareModeBestiary,
      modeCleanFlex: l10n.shareModeCleanFlex,
    );
  }

  /// Bottom-sheet title, e.g. "Compartilhar saga" / "Share your saga".
  final String sheetTitle;

  /// Camera row label, e.g. "Tirar foto" / "Take a photo".
  final String takePhoto;

  /// Gallery row label, e.g. "Escolher da galeria" / "Pick from gallery".
  final String fromGallery;

  /// Discreet row label, e.g. "Sem foto · só a saga" / "No photo · just
  /// the saga".
  final String noPhoto;

  /// Preview-screen retake button, e.g. "Refazer" / "Retake".
  final String previewRetake;

  /// Preview-screen share button, e.g. "Compartilhar" / "Share".
  final String previewShare;

  /// Brand wordmark, e.g. "REPSAGA". Same across locales but kept as a
  /// param for white-label / event-rebrand support.
  final String wordmark;

  /// Snackbar / error-state copy when camera permission is denied this
  /// session (the user can re-prompt).
  final String permissionDenied;

  /// Snackbar / error-state copy when camera permission is permanently
  /// denied. The screen layer also offers an "Open settings" affordance
  /// alongside this copy.
  final String permissionPermanentlyDenied;

  /// Snackbar / error-state copy when [ShareImageRenderer] fails to
  /// produce a sharable image.
  final String renderError;

  /// Snackbar action label paired with [permissionPermanentlyDenied].
  /// Tapping it routes to `openAppSettings()` so the user can flip the
  /// camera-permission toggle and retry.
  final String openSettings;

  /// Share-mode toggle segment label for the Bestiary (creature) card.
  final String modeBestiary;

  /// Share-mode toggle segment label for the Clean Flex (stats) card.
  final String modeCleanFlex;
}

/// Pre-localized string bundle for the Phase 39 share-card overlay grammar
/// (Bestiary + Clean Flex modes).
///
/// **Why a separate bundle from [ShareCardStrings]?** [ShareCardStrings]
/// holds the legacy Achievement-Frame / Discreet copy; the Phase 39 chassis
/// cards need their own grammar (Bestiary eyebrow, rank/XP/tonnage fragments,
/// Clean-Flex stat keys). Keeping them in a dedicated bundle means the
/// screen-layer composer fills exactly the slots the active mode renders,
/// and the render widgets stay l10n-harness-free (Decoupling Rule 2 — the
/// beast name + phrase are already-localized on the `BeastCard`; these are
/// the surrounding chrome strings).
class BestiaryShareStrings {
  const BestiaryShareStrings({
    required this.wordmark,
    required this.bestiaryEyebrow,
    required this.bossEyebrow,
    required this.rankLabel,
    required this.xpLabel,
    required this.tonnageLabel,
    required this.cleanFlexEyebrow,
    required this.cleanFlexHeroValue,
    required this.cleanFlexStatLabels,
    this.cleanFlexHeroUnit,
    this.cleanFlexHeroContext,
    required this.cleanFlexStatValues,
  });

  /// Brand wordmark, e.g. "REPSAGA".
  final String wordmark;

  /// Bestiary eyebrow for a non-boss encounter, e.g. "⚔ Hoje você abateu".
  final String bestiaryEyebrow;

  /// Bestiary eyebrow for a boss / legendary, e.g. "⚜ Chefe derrotado".
  final String bossEyebrow;

  /// Rank token, e.g. "RANK C".
  final String rankLabel;

  /// XP fragment (rendered in heroGold), e.g. "+618 XP".
  final String xpLabel;

  /// Tonnage fragment, e.g. "8,4 t".
  final String tonnageLabel;

  /// Clean-Flex eyebrow, e.g. "Bulwark · Nível 9".
  final String cleanFlexEyebrow;

  /// Clean-Flex hero leading value, e.g. "130" (PR weight) or the tonnage
  /// fallback.
  final String cleanFlexHeroValue;

  /// Clean-Flex hero unit suffix, e.g. " kg × 3". `null` for a standalone
  /// numeral hero.
  final String? cleanFlexHeroUnit;

  /// Clean-Flex hero context line, e.g. "Supino · Peito 18 → 19". `null`
  /// collapses the line.
  final String? cleanFlexHeroContext;

  /// The four-stat strip values in order: XP, tonnage, sets, duration.
  final List<String> cleanFlexStatValues;

  /// The four-stat strip keys in order: e.g. ["XP", "TON", "SÉRIES", "DUR"].
  final List<String> cleanFlexStatLabels;
}
