import 'package:flutter/material.dart';

import '../synk_colors.dart';
import '../tokens.dart';
import 'pressable.dart';

/// Primary call-to-action: solid brand violet, flat. The brand colour as a fill is
/// kept for the main thing to do on a screen, so it always means "tap here".
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 56,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final onBrand = context.synk.onBrand;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: onBrand))
        else ...[
          if (icon != null) ...[Icon(icon, color: onBrand, size: 22), const SizedBox(width: Space.sm)],
          Text(label, style: context.text.labelLarge?.copyWith(color: onBrand)),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      // excludeSemantics drops the child's tap action, so re-expose it here.
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          opacity: enabled || loading ? 1 : 0.45,
          duration: Motion.fast,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            decoration: BoxDecoration(color: context.synk.brand, borderRadius: Radii.pillAll),
            child: content,
          ),
        ),
      ),
    );
  }
}
