import 'package:flutter/material.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.prefixIcon,
    this.focusNode,
    this.onFieldSubmitted,
    this.maxLength,
    this.showCounter = true,
    this.semanticsIdentifier,
    this.autofillHints,
    this.obscureTooltipShow,
    this.obscureTooltipHide,
    this.onObscureToggle,
  });

  final String label;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final IconData? prefixIcon;
  final FocusNode? focusNode;
  final ValueChanged<String>? onFieldSubmitted;
  final int? maxLength;

  /// When `false`, suppresses Flutter's automatic `N/M` counter while still
  /// enforcing `maxLength`. Only needed for fixed-height layouts where the
  /// ~22px counter row overflows — see `onboarding_screen.dart`. Raw
  /// `TextField` call sites handle the same case by passing
  /// `counterText: ''` directly.
  final bool showCounter;

  /// Optional Semantics identifier for locale-independent E2E selectors.
  /// When non-null, wraps the field in `Semantics(container: true, identifier: ...)`.
  final String? semanticsIdentifier;

  /// OS-level autofill hints (e.g. [AutofillHints.email],
  /// [AutofillHints.password], [AutofillHints.newPassword]). Forwarded
  /// verbatim to the underlying [TextFormField.autofillHints]; when the
  /// containing form is wrapped in an [AutofillGroup], Flutter surfaces the
  /// OS save / fill prompts (Android Credential Manager on API 34+, the
  /// iOS Passwords sheet on iOS 12+). Defaults to `null` so existing call
  /// sites stay opt-out.
  final Iterable<String>? autofillHints;

  /// Tooltip shown on the reveal-password eye while the field is obscured
  /// (i.e. tapping it will SHOW the password). Material 3 derives the
  /// IconButton's semantics label from this tooltip, so screen readers and
  /// E2E tooling get a stable, localized handle. Only meaningful when
  /// [obscureText] is true; defaults to `null` (no tooltip / unchanged
  /// behavior for existing call sites).
  final String? obscureTooltipShow;

  /// Tooltip shown on the reveal-password eye while the field is revealed
  /// (i.e. tapping it will HIDE the password). See [obscureTooltipShow].
  final String? obscureTooltipHide;

  /// Fired after the obscure state toggles via the eye button. Lets callers
  /// react to the first reveal (e.g. dismiss a one-time "tap the eye" hint).
  /// Defaults to `null`.
  final VoidCallback? onObscureToggle;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync the local obscure state when the obscureText prop changes.
    // Without this, a State object reused across a widget swap (Flutter
    // reconciles same-typed siblings by position when they lack keys) keeps
    // its old `_obscured` — e.g. an email field inheriting a password field's
    // State would render masked. cluster: missing-key-state-reuse.
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field = TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      obscureText: _obscured,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      focusNode: widget.focusNode,
      onFieldSubmitted: widget.onFieldSubmitted,
      maxLength: widget.maxLength,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        counterText: widget.showCounter ? null : '',
        prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
        suffixIcon: widget.obscureText
            ? IconButton(
                icon: Icon(_obscured ? Icons.visibility_off : Icons.visibility),
                // Material 3 surfaces the tooltip as the IconButton's
                // semantics label, so the reveal affordance is announced and
                // E2E-addressable. State-aware: show vs hide.
                tooltip: _obscured
                    ? widget.obscureTooltipShow
                    : widget.obscureTooltipHide,
                onPressed: () {
                  setState(() => _obscured = !_obscured);
                  widget.onObscureToggle?.call();
                },
              )
            : null,
      ),
    );

    if (widget.semanticsIdentifier != null) {
      // cluster: semantics-identifier-pair-rule — every Semantics(identifier:)
      // needs container:true + explicitChildNodes:true so the AOM emits a
      // dedicated node that Playwright's role-based selectors can resolve.
      field = Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: widget.semanticsIdentifier!,
        child: field,
      );
    }

    return field;
  }
}
