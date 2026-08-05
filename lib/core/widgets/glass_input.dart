import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class GlassInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final EdgeInsetsGeometry padding;

  const GlassInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.icon,
    this.obscure = false,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: TextField(
          controller: controller,
          obscureText: obscure,
          maxLines: maxLines,
          maxLength: maxLength,
          onChanged: onChanged,
          style: const TextStyle(color: Tokens.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            icon: icon != null
                ? Icon(icon, size: 18, color: Tokens.textTertiary)
                : null,
            border: InputBorder.none,
            isDense: true,
            counterText: '',
            contentPadding: padding,
            labelStyle: const TextStyle(color: Tokens.textTertiary),
            hintStyle: const TextStyle(color: Tokens.textTertiary),
          ),
        ),
      ),
    );
  }
}
