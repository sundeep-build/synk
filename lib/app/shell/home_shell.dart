import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_system.dart';
import '../../features/player/presentation/mini_player.dart';
import '../../features/rooms/presentation/room_sheets.dart';
import 'exit_guard.dart';

/// Tab scaffold: content scrolls under one floating "dock" that holds the mini
/// player and the nav bar. The dock is a solid panel, not a live blur: a
/// backdrop blur re-renders on every frame of scrolling beneath it.
class HomeShell extends StatelessWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  void _go(int index) {
    HapticFeedback.selectionClick();
    // Re-tapping the current tab pops it to its root, like every major app.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  /// Back on another tab's root goes to Home first; on Home it asks to exit.
  bool _backToHome() {
    if (shell.currentIndex == 0) return false;
    shell.goBranch(0);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ExitGuard(
      onBack: _backToHome,
      child: Scaffold(
        extendBody: true,
        body: shell,
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
          child: GlassPanel(
            color: context.synk.surface,
            radius: Radii.xlAll,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                _NavRow(current: shell.currentIndex, onTap: _go),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.current, required this.onTap});

  final int current;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.search_rounded, Icons.manage_search_rounded, 'Search'),
    (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget item(int i) {
      final (icon, activeIcon, label) = _items[i];
      final selected = i == current;
      final color = selected ? context.synk.textPrimary : context.synk.textMuted;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          onTap: () => onTap(i),
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => onTap(i),
            radius: 32,
            child: SizedBox(
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: Motion.fast,
                    child: Icon(selected ? activeIcon : icon, key: ValueKey(selected), color: color, size: 24),
                  ),
                  const SizedBox(height: 3),
                  Text(label, style: context.text.labelSmall!.copyWith(color: color)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: Row(children: [item(0), item(1), const _GoLiveButton(), item(2), item(3)]),
    );
  }
}

/// The dock's centrepiece: a raised brand disc that starts a room.
class _GoLiveButton extends StatelessWidget {
  const _GoLiveButton();

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Tooltip(
        message: 'Start a room',
        child: Pressable(
          onTap: () => showCreateRoomSheet(context),
          semanticLabel: 'Start a room',
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: c.brand,
              shape: BoxShape.circle,
              border: Border.all(color: c.background, width: 3),
              boxShadow: [
                BoxShadow(color: c.brand.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(Icons.add_rounded, color: c.onBrand, size: 28),
          ),
        ),
      ),
    );
  }
}
