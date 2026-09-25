import 'package:flutter/material.dart';

import '../../error/app_exception.dart';
import '../synk_colors.dart';
import '../synk_type.dart';
import '../tokens.dart';

/// Section title with a short accent bar. The first word is heavy and the
/// rest light ("Trending videos" → **Trending** videos). Optional "See all ›".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.action, this.onAction, this.accent, super.key});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  /// Accent bar colour; defaults to the logo's cyan.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final space = title.indexOf(' ');
    final head = space < 0 ? title : title.substring(0, space);
    final tail = space < 0 ? '' : title.substring(space);
    final style = context.text.headlineSmall!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.sm, Space.md),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: accent ?? context.colors.tertiary,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          const SizedBox(width: Space.sm + 2),
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: head, style: context.weight(style, FontWeight.w800)),
                    if (tail.isNotEmpty) TextSpan(text: tail, style: context.weight(style, FontWeight.w400)),
                  ],
                ),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: c.textSecondary, visualDensity: VisualDensity.compact),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!, style: context.text.labelMedium?.copyWith(color: c.textSecondary)),
                  const SizedBox(width: 6),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(color: c.textSecondary, shape: BoxShape.circle),
                    child: Icon(Icons.chevron_right_rounded, size: 14, color: c.background),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Static skeleton block. Deliberately NOT animated: a shimmer on every tile
/// burns GPU on low-end phones; a calm placeholder reads just as "loading".
class Skeleton extends StatelessWidget {
  const Skeleton({this.width, this.height = 16, this.radius = Radii.smAll, super.key});

  final double? width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: context.synk.skeleton, borderRadius: radius),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, this.message, this.action, super.key});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// Below this height (chat pane or queue with the keyboard up, short sheets)
  /// the icon is dropped and the padding tightened.
  static const double _compactBelow = 260;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < _compactBelow;
        final content = Padding(
          padding: EdgeInsets.all(compact ? Space.lg : Space.xxl),
          child: _content(context, c, compact: compact),
        );
        if (!box.hasBoundedHeight) return content;
        // Still centred when it fits; scrolls instead of overflowing when it doesn't
        // (large text scale, tiny panes).
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, SynkColors c, {required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: c.surfaceRaised, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: c.textSecondary),
          ),
          const SizedBox(height: Space.lg),
        ],
        Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            message!,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[SizedBox(height: compact ? Space.md : Space.xl), action!],
      ],
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = AppException.from(error);
    final (icon, title) = switch (e) {
      NetworkException() => (Icons.wifi_off_rounded, 'No connection'),
      ServiceUnavailableException() ||
      YouTubeNotConfiguredException() => (Icons.smart_display_outlined, 'Not available right now'),
      _ => (Icons.error_outline_rounded, 'Something broke'),
    };
    return EmptyState(
      icon: icon,
      title: title,
      message: e.message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
    );
  }
}

extension SnackX on BuildContext {
  void showError(Object error) {
    final e = AppException.from(error);
    if (e is AuthCancelledException) return;
    showSnack(e.message, icon: Icons.error_outline_rounded);
  }

  void showSnack(String message, {IconData? icon}) {
    final messenger = ScaffoldMessenger.maybeOf(this);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: Space.md)],
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}

/// For flows where the originating widget (e.g. a sheet) is already gone:
/// capture `ScaffoldMessenger.of(context)` first, then report through it.
extension MessengerX on ScaffoldMessengerState {
  void showAppError(Object error) {
    final e = AppException.from(error);
    if (e is AuthCancelledException) return;
    showSnackBar(SnackBar(content: Text(e.message)));
  }
}
