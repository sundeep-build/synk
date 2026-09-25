import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';

/// Emoji + gradient avatar builder (used in onboarding and profile edit).
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({required this.emoji, required this.color, required this.onChanged, super.key});

  final String emoji;
  final int color;
  final void Function(String emoji, int color) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: SynkAvatar(emoji: emoji, colorIndex: color, size: 120, ring: true),
        ),
        const SizedBox(height: Space.xxl),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Space.sm,
          crossAxisSpacing: Space.sm,
          children: [
            for (final e in SynkPalette.avatarEmojis)
              Semantics(
                selected: e == emoji,
                button: true,
                label: 'Avatar $e',
                child: InkWell(
                  borderRadius: Radii.mdAll,
                  onTap: () => onChanged(e, color),
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: Radii.mdAll,
                      color: e == emoji ? context.colors.primaryContainer : context.synk.surfaceRaised,
                      border: Border.all(color: e == emoji ? context.colors.primary : Colors.transparent, width: 1.5),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.xl),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < SynkPalette.identity.length; i++)
              Semantics(
                selected: i == color,
                button: true,
                label: 'Color ${i + 1}',
                child: InkResponse(
                  onTap: () => onChanged(emoji, i),
                  radius: 28,
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SynkPalette.identity[i],
                      border: Border.all(color: i == color ? context.synk.textPrimary : Colors.transparent, width: 3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
