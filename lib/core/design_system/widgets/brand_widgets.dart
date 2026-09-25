import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../synk_colors.dart';
import '../synk_type.dart';
import '../tokens.dart';

/// The Synk mark (the "S" with a play button) on its tile. Built with the
/// launcher icons by scripts/brand/build_icons.py.
class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 56, super.key});

  static const asset = 'assets/brand/logo_tile.png';

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: size,
    height: size,
    // Decode at display size, not the 512 px source.
    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Synk logo',
  );
}

/// Logo + spaced-out wordmark, for screen headers.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({this.name = 'SYNK', this.size = 34, super.key});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: Radii.smAll,
        child: AppLogo(size: size),
      ),
      const SizedBox(width: Space.md),
      Text(name, style: context.weight(context.text.titleLarge, FontWeight.w800).copyWith(letterSpacing: 2.4)),
    ],
  );
}

/// Round icon button on a raised disc (search, back, share, more).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 46,
    this.fill,
    this.foreground,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? fill;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: size * 0.46),
      style: IconButton.styleFrom(
        backgroundColor: fill ?? c.surfaceOverlay,
        foregroundColor: foreground ?? c.textPrimary,
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        side: BorderSide(color: c.glassBorder),
      ),
    );
  }
}

/// Back arrow on a raised disc, for app bars (`AppBar.leading`).
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({this.icon = Icons.arrow_back_rounded, this.tooltip = 'Back', this.onPressed, super.key});

  final IconData icon;
  final String tooltip;

  /// Defaults to popping the current route.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: Space.sm),
    child: Center(
      child: CircleIconButton(
        icon: icon,
        tooltip: tooltip,
        size: 42,
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      ),
    ),
  );
}

/// Two-weight title: first word heavy, the rest light ("**Your** library").
class SplitTitle extends StatelessWidget {
  const SplitTitle(this.text, {this.style, this.lightColor, this.maxLines = 1, super.key});

  final String text;
  final TextStyle? style;

  /// Colour for the light part; defaults to the heavy part's colour.
  final Color? lightColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final space = text.indexOf(' ');
    final base = style ?? context.text.headlineLarge;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: space < 0 ? text : text.substring(0, space)),
          if (space >= 0)
            TextSpan(
              text: text.substring(space),
              style: context.weight(base, FontWeight.w400).copyWith(color: lightColor),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: context.weight(base, FontWeight.w800),
    );
  }
}

/// Faint studio grid behind brand screens. Static: painted once, cached by
/// its RepaintBoundary, so scrolling content above it costs nothing extra.
class GridBackdrop extends StatelessWidget {
  const GridBackdrop({required this.child, this.cell = 46, super.key});

  final Widget child;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return ColoredBox(
      color: c.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _GridPainter(color: c.glassBorder.withValues(alpha: 0.05), cell: cell),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.color, required this.cell});

  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = cell; x < size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = cell; y < size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color || old.cell != cell;
}

/// Page indicator as short bars: the current one long and bright.
class SegmentIndicator extends StatelessWidget {
  const SegmentIndicator({required this.count, required this.index, super.key});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.standard,
              width: i == index ? 30 : 16,
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == index ? c.textPrimary : c.textMuted.withValues(alpha: 0.35),
                borderRadius: Radii.pillAll,
              ),
            ),
        ],
      ),
    );
  }
}

/// Round play control for track rows: play, or pause on the brand colour for
/// the track that's playing.
class PlayStateButton extends StatelessWidget {
  const PlayStateButton({required this.active, required this.playing, this.onPressed, this.size = 34, super.key});

  /// This row's track is the current one.
  final bool active;
  final bool playing;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final showPause = active && playing;
    return Semantics(
      container: true,
      button: onPressed != null,
      label: showPause ? 'Pause' : 'Play',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active ? c.brand : c.surfaceOverlay,
            shape: BoxShape.circle,
            border: Border.all(color: active ? c.brand : c.glassBorder),
          ),
          child: Icon(
            showPause ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: size * 0.56,
            color: active ? c.onBrand : c.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Small pill action ("Play" / "Playing", "Join"). [selected] turns it into
/// an outlined cyan pill.
class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.height = 34,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final accent = context.colors.tertiary;
    final fg = selected ? accent : c.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? Colors.transparent : c.surfaceOverlay,
        shape: StadiumBorder(side: BorderSide(color: selected ? accent : c.glassBorder)),
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A photo tinted with one flat colour, like a gig poster (the colour keeps
/// the image's light and shade). Tinted while painting (the image's own
/// colour filter), so it costs no extra layer.
class DuotoneCover extends StatelessWidget {
  const DuotoneCover({required this.url, required this.color, required this.decodeWidth, this.icon, super.key});

  final String? url;
  final Color color;

  /// Logical width the image is shown at (it's decoded at that size).
  final double decodeWidth;

  /// Shown when there's no image.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: color,
      child: icon == null ? null : Center(child: Icon(icon, size: 56, color: Colors.white.withValues(alpha: 0.35))),
    );
    if (url == null || url!.isEmpty) return fallback;
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: url!,
          memCacheWidth: (decodeWidth * MediaQuery.devicePixelRatioOf(context)).round(),
          fit: BoxFit.cover,
          color: color,
          colorBlendMode: BlendMode.color,
          fadeInDuration: Motion.fast,
          placeholder: (_, _) => fallback,
          errorWidget: (_, _, _) => fallback,
        ),
        // Deepens the tint so white text on top always reads.
        ColoredBox(color: color.withValues(alpha: 0.28)),
      ],
    );
  }
}
