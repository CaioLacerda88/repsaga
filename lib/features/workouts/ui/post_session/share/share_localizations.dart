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
    required this.previewMinimal,
    required this.previewBold,
    required this.previewRetake,
    required this.previewShare,
    required this.wordmark,
    required this.permissionDenied,
    required this.permissionPermanentlyDenied,
    required this.renderError,
    required this.openSettings,
  });

  /// Bridge from the generated [AppLocalizations] to the typed bundle.
  /// Single touchpoint between the share widgets and the ARB layer.
  factory ShareLocalizations.from(AppLocalizations l10n) {
    return ShareLocalizations(
      sheetTitle: l10n.shareSheetTitle,
      takePhoto: l10n.shareSheetTakePhoto,
      fromGallery: l10n.shareSheetFromGallery,
      noPhoto: l10n.shareSheetNoPhoto,
      previewMinimal: l10n.sharePreviewMinimal,
      previewBold: l10n.sharePreviewBold,
      previewRetake: l10n.sharePreviewRetake,
      previewShare: l10n.sharePreviewShare,
      wordmark: l10n.shareWordmark,
      permissionDenied: l10n.sharePermissionDenied,
      permissionPermanentlyDenied: l10n.sharePermissionPermanentlyDenied,
      renderError: l10n.shareRenderError,
      openSettings: l10n.shareOpenSettings,
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

  /// Preview-screen variant toggle: "Mínimo" / "Minimal".
  final String previewMinimal;

  /// Preview-screen variant toggle: "Destaque" / "Bold".
  final String previewBold;

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
}
