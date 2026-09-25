import 'package:flutter/material.dart';

import '../../error/app_exception.dart';
import '../synk_colors.dart';
import '../tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.action, this.onAction, super.key});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.sm, Space.md),
      child: Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(title, style: context.text.headlineSmall)),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
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
