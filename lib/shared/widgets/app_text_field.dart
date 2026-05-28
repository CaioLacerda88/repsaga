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
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
      ),
    );

    if (widget.semanticsIdentifier != null) {
      field = Semantics(
        container: true,
        identifier: widget.semanticsIdentifier!,
        child: field,
      );
    }

    return field;
  }
}
