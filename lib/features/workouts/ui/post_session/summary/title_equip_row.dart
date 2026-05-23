import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

/// Single-purpose widget: "Novo título · {name} · [EQUIPAR] [depois]" row
/// on the summary panel.
///
/// **Decoupling Rule 7 — RPC injected as callback.** The widget takes
/// [onEquipPressed] (an injected async function the screen wires to the
/// `equip_title` RPC). The row is unit-testable without Supabase by
/// passing a mock callback.
///
/// **States:**
///   * Idle — shows EQUIPAR + depois.
///   * Loading — shows spinner instead of EQUIPAR; both buttons disabled.
///   * Equipped (`equippedLabel` non-null) — collapses to "{equippedLabel}".
class TitleEquipRow extends StatefulWidget {
  const TitleEquipRow({
    super.key,
    required this.eyebrowLabel,
    required this.titleName,
    required this.equipLabel,
    required this.laterLabel,
    required this.equippedLabel,
    required this.onEquipPressed,
    this.onLaterPressed,
  });

  /// "Novo título" eyebrow (pre-localized).
  final String eyebrowLabel;

  /// Display name of the title.
  final String titleName;

  /// "EQUIPAR" button label.
  final String equipLabel;

  /// "depois" label.
  final String laterLabel;

  /// "Equipado ✓" label shown after a successful equip. When non-null on
  /// initial render, the row starts in the equipped state (e.g. user
  /// already had this title equipped before this session).
  final String equippedLabel;

  /// Invoked when the user taps EQUIPAR. Returning a Future allows the
  /// row to show a loading spinner during the RPC round-trip; on success
  /// the row transitions to the equipped state.
  final Future<void> Function() onEquipPressed;

  /// Invoked when the user taps "depois". The screen layer typically
  /// collapses the row in response (or no-ops to let the user dismiss it
  /// later).
  final VoidCallback? onLaterPressed;

  @override
  State<TitleEquipRow> createState() => _TitleEquipRowState();
}

class _TitleEquipRowState extends State<TitleEquipRow> {
  bool _isLoading = false;
  bool _isEquipped = false;
  bool _isCollapsed = false;

  Future<void> _handleEquip() async {
    if (_isLoading || _isEquipped) return;
    setState(() => _isLoading = true);
    try {
      await widget.onEquipPressed();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isEquipped = true;
      });
    } catch (_) {
      // The screen layer surfaces error snackbars; this widget just resets
      // the row so the user can retry.
      if (!mounted) return;
      setState(() => _isLoading = false);
      rethrow;
    }
  }

  void _handleLater() {
    if (_isLoading) return;
    setState(() => _isCollapsed = true);
    widget.onLaterPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCollapsed) return const SizedBox.shrink();

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-title-equip-row',
      label: '${widget.eyebrowLabel} · ${widget.titleName}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.eyebrowLabel.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTextStyles.label.copyWith(
                color: AppColors.hotViolet,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.titleName,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleDisplay,
            ),
            const SizedBox(height: 8),
            if (_isEquipped)
              Text(
                widget.equippedLabel,
                textAlign: TextAlign.center,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.success,
                  fontSize: 12,
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _isLoading ? null : _handleEquip,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryViolet,
                        foregroundColor: AppColors.textCream,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textCream,
                              ),
                            )
                          : Text(widget.equipLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _isLoading ? null : _handleLater,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textDim,
                    ),
                    child: Text(widget.laterLabel),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
