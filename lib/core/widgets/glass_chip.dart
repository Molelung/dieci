import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class GlassChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? selectedColor;

  const GlassChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selectedColor ?? Tokens.brandPink;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? accent.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : Tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
