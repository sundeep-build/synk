import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';

/// Avatar builder (onboarding and profile edit): a cartoon character or an
/// emoji, on a background colour.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({required this.emoji, required this.color, required this.onChanged, super.key});

  /// The avatar value: `c:<n>` for a character, otherwise an emoji.
  final String emoji;
  final int color;
  final void Function(String emoji, int color) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final character = CartoonAvatar.indexOf(emoji);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              SynkAvatar(emoji: emoji, colorIndex: color, size: 124, ring: true),
              const SizedBox(height: Space.sm),
              Text(
                character != null ? CartoonAvatar.names[character] : 'Emoji',
                style: context.text.titleSmall?.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        const _Label('Characters', 'Pop & jazz crew'),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Space.md,
          crossAxisSpacing: Space.md,
          children: [
            for (var i = 0; i < CartoonAvatar.count; i++)
              _Choice(
                selected: character == i,
                label: CartoonAvatar.names[i],
                onTap: () => onChanged(CartoonAvatar.code(i), color),
                child: LayoutBuilder(
                  builder: (_, box) => CartoonAvatar(
                    index: i,
                    background: SynkPalette.identityColor(color),
                    size: box.biggest.shortestSide,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.xl),
        const _Label('Emoji', null),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Space.sm,
          crossAxisSpacing: Space.sm,
          children: [
            for (final e in SynkPalette.avatarEmojis)
              _Choice(
                selected: e == emoji,
                label: 'Avatar $e',
                onTap: () => onChanged(e, color),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
              ),
          ],
        ),
        const SizedBox(height: Space.xl),
        const _Label('Background', null),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (var i = 0; i < SynkPalette.identity.length; i++)
              Semantics(
                selected: i == color,
                button: true,
                label: 'Colour ${i + 1}',
                child: InkResponse(
                  onTap: () => onChanged(emoji, i),
                  radius: 26,
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SynkPalette.identity[i],
                      border: Border.all(color: i == color ? c.textPrimary : Colors.transparent, width: 3),
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

class _Label extends StatelessWidget {
  const _Label(this.title, this.caption);

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: context.text.titleMedium),
        if (caption != null) ...[const SizedBox(width: Space.sm), Text(caption!, style: context.text.bodySmall)],
      ],
    ),
  );
}

/// A pickable tile: rounded, outlined in brand violet when selected.
class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.label, required this.onTap, required this.child});

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: Radii.lgAll,
            color: selected ? c.brand.withValues(alpha: 0.18) : c.surfaceRaised,
            border: Border.all(color: selected ? c.brand : c.glassBorder, width: selected ? 2 : 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
