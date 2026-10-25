import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/glow_colors.dart';
import '../theme/motion.dart';

/// Text field with a ≥ 3 : 1 boundary that brightens and glows while
/// focused, and turns rose on error. The error is announced (UX-03, UX-19).
class GlowField extends StatefulWidget {
  const GlowField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.obscure = false,
    this.autofocus = false,
    this.enabled = true,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.textAlign = TextAlign.start,
    this.letterSpacing,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? errorText;
  final TextInputType? keyboardType;
  final bool obscure;
  final bool autofocus;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final TextAlign textAlign;
  final double? letterSpacing;
  final FocusNode? focusNode;

  @override
  State<GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<GlowField> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final focused = _focus.hasFocus;
    final accent = hasError ? GlowColors.error : GlowColors.cyan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(widget.label, style: const TextStyle(color: GlowColors.textMuted, fontSize: 13)),
        ),
        AnimatedContainer(
          duration: Motion.micro,
          curve: Motion.move,
          decoration: BoxDecoration(
            color: GlowColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: focused || hasError ? accent : GlowColors.outlineStrong,
              width: focused || hasError ? 1.6 : 1.2,
            ),
            boxShadow: focused || hasError ? glow(accent, intensity: 0.4) : const [],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            obscureText: widget.obscure,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            autofillHints: widget.autofillHints,
            textAlign: widget.textAlign,
            style: TextStyle(fontSize: 17, letterSpacing: widget.letterSpacing),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: GlowColors.textMuted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.micro,
          curve: Motion.enter,
          child: hasError
              ? Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, top: 8),
                    child: Text(
                      widget.errorText!,
                      style: const TextStyle(color: GlowColors.error, fontSize: 13),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
