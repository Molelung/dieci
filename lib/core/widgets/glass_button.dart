import 'package:flutter/material.dart';
import '../theme/tokens.dart';

enum GlassButtonStyle { filled, outline, ghost }

class GlassButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final GlassButtonStyle style;
  final bool loading;
  final double radius;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.style = GlassButtonStyle.filled,
    this.loading = false,
    this.radius = 999,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;

    final Widget content = switch (widget.style) {
      GlassButtonStyle.filled => DecoratedBox(
          decoration: BoxDecoration(
            gradient: Tokens.brandGradient,
            boxShadow: [
              BoxShadow(
                color: Tokens.brandPink.withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: -4,
              ),
            ],
          ),
          child: _inner(),
        ),
      GlassButtonStyle.outline => DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            color: Colors.white.withValues(alpha: 0.06),
          ),
          child: _inner(),
        ),
      GlassButtonStyle.ghost => DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
          ),
          child: _inner(),
        ),
    };

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _inner() {
    final Color fg = widget.style == GlassButtonStyle.filled
        ? Colors.white
        : Tokens.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.loading) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 10),
          ] else if (widget.icon != null) ...[
            Icon(widget.icon, size: 18, color: fg),
            const SizedBox(width: 8),
          ],
          Text(
            widget.label,
            style: TextStyle(
              color: fg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
