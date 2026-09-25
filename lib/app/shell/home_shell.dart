import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_system.dart';
import '../../features/player/presentation/mini_player.dart';
import '../../features/rooms/presentation/room_sheets.dart';

/// Tab scaffold: content scrolls under a single floating glass "dock" that
/// holds the mini player and the nav bar (one blur layer for both).
class HomeShell extends StatelessWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  void _go(int index) {
    HapticFeedback.selectionClick();
    // Re-tapping the current tab pops it to its root, like every major app.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
        child: GlassPanel(
          blur: true,
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
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: Motion.fast,
                    child: Icon(
                      selected ? activeIcon : icon,
                      key: ValueKey(selected),
                      color: selected ? context.synk.textPrimary : context.synk.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: Motion.fast,
                    style: context.text.labelSmall!.copyWith(
                      color: selected ? context.synk.textPrimary : context.synk.textMuted,
                    ),
                    child: Text(label),
                  ),
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

class _GoLiveButton extends StatelessWidget {
  const _GoLiveButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Tooltip(
        message: 'Start a room',
        child: Pressable(
          onTap: () => showCreateRoomSheet(context),
          semanticLabel: 'Start a room',
          child: Container(
            width: 52,
            height: 40,
            decoration: BoxDecoration(color: context.synk.brand, borderRadius: Radii.mdAll),
            child: Icon(Icons.add_rounded, color: context.synk.onBrand, size: 28),
          ),
        ),
      ),
    );
  }
}
