import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/beast_card.dart';
import '../../../domain/share_payload.dart';
import '../../../providers/share_controller.dart';
import '../share/share_card_renderer.dart';
import '../share/share_localizations.dart';
import '../share/share_preview_screen.dart';
import '../share/share_sheet.dart';
import 'post_session_summary_panel.dart' show PostSessionCinematicButton;

/// Share CTA on the post-session summary panel.
///
/// **Flow** (mockup §7):
///   1. User taps "Compartilhar saga".
///   2. We read the current camera permission status (sync API call).
///   3. Open the [ShareSheet] bottom modal — user picks
///      camera / gallery / discreet.
///   4. ShareSheet's row taps dispatch into [ShareController] — the
///      controller transitions through `pickingPhoto → preview` (or
///      `error` / `cancelled`).
///   5. When [ShareController]'s state is `preview`, this widget listens
///      to that transition and pushes [SharePreviewScreen] onto the
///      navigator.
///
/// **Why coordinate navigation in this widget instead of the screen?**
/// The screen layer (`PostSessionScreen`) is route-agnostic per
/// Decoupling Rule 8 — it gets `onContinue` callbacks injected by the
/// route container. Adding share navigation to it would broaden that
/// surface. This widget already owns the share-CTA tap, so coordinating
/// the resulting navigation here keeps the responsibility local.
///
/// **Decoupling Rule 2.** Pre-localized strings via [ShareLocalizations];
/// the widget never calls `AppLocalizations.of(context)`.
class ShareCtaButton extends ConsumerStatefulWidget {
  const ShareCtaButton({
    super.key,
    required this.label,
    required this.payload,
    required this.strings,
    required this.l10n,
    this.beastCard,
    this.bestiaryStrings,
  });

  /// CTA label, e.g. "Compartilhar saga" (no glyph baked in — the camera
  /// icon renders as a leading Material icon).
  final String label;

  /// Pre-composed share payload — forwarded into the sheet + preview.
  final SharePayload payload;

  /// Pre-localized text bundle for the share-card overlay grammar.
  final ShareCardStrings strings;

  /// Pre-localized labels for the sheet + preview-screen affordances.
  final ShareLocalizations l10n;

  /// Phase 39 — the resolved Bestiary card (null falls back to the legacy
  /// card path on the preview).
  final BeastCard? beastCard;

  /// Phase 39 — pre-localized chrome strings for the chassis cards.
  final BestiaryShareStrings? bestiaryStrings;

  @override
  ConsumerState<ShareCtaButton> createState() => _ShareCtaButtonState();
}

class _ShareCtaButtonState extends ConsumerState<ShareCtaButton> {
  /// True after a `pickingPhoto` transition has fired — guards against
  /// re-pushing the preview screen on a state-machine rewind.
  bool _previewActive = false;

  @override
  Widget build(BuildContext context) {
    // Listen to share controller transitions. When the controller lands
    // in `preview`, push the preview screen. We do this in `listen`
    // (not `watch`) so we react to transitions exactly once — `watch`
    // would re-build this widget on every state change.
    ref.listen<ShareState>(shareControllerProvider, (previous, next) {
      if (next is ShareStatePreview && !_previewActive) {
        _previewActive = true;
        _pushPreview();
      }
    });

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-share-cta',
      child: PostSessionCinematicButton(
        label: widget.label,
        backgroundColor: AppColors.surface2,
        foregroundColor: AppColors.textCream,
        leadingIcon: Icons.camera_alt_outlined,
        onPressed: _onShareTapped,
      ),
    );
  }

  Future<void> _onShareTapped() async {
    final controller = ref.read(shareControllerProvider.notifier);
    final cameraStatus = await controller.refreshCameraPermission();
    if (!mounted) return;
    await ShareSheet.open(
      context,
      l10n: widget.l10n,
      cameraStatus: cameraStatus,
    );
  }

  Future<void> _pushPreview() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => SharePreviewScreen(
          payload: widget.payload,
          strings: widget.strings,
          l10n: widget.l10n,
          beastCard: widget.beastCard,
          bestiaryStrings: widget.bestiaryStrings,
          onClose: () => Navigator.of(ctx).maybePop(),
        ),
      ),
    );
    if (mounted) {
      // Preview was popped — reset the latch so a future tap-CTA flow
      // can re-push when state transitions to preview again.
      _previewActive = false;
    }
  }
}
