import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/application/session.dart';
import '../../catalog/domain/genres.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../../library/application/library_providers.dart';
import '../../player/application/play_actions.dart';
import '../../player/application/player_providers.dart';
import '../../rooms/application/room_providers.dart';
import '../../rooms/application/room_session_controller.dart';
import '../domain/user_profile.dart';
import 'avatar_picker.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(WidgetRef ref) async {
    await ref.read(roomSessionProvider.notifier).leave();
    await ref.read(soloPlayerProvider.notifier).stop();
    await ref.read(authRepositoryProvider).signOut();
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref, UserProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text('Your profile, likes and playlists will be permanently deleted. This can’t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SynkPalette.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    try {
      await ref.read(roomSessionProvider.notifier).leave();
      await ref.read(soloPlayerProvider.notifier).stop();
      await ref.read(userRepositoryProvider).deleteProfile(profile);
      await ref.read(authRepositoryProvider).deleteUser();
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  Future<void> _link(BuildContext context, WidgetRef ref, {required bool apple}) async {
    final auth = ref.read(authRepositoryProvider);
    try {
      apple ? await auth.signInWithApple() : await auth.signInWithGoogle();
      if (context.mounted) context.showSnack('Account saved ✓', icon: Icons.verified_rounded);
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  void _edit(BuildContext context, UserProfile profile) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _EditProfileSheet(profile: profile),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final isGuest = ref.watch(isGuestProvider);
    final likes = ref.watch(likedIdsProvider).length;
    final playlists = ref.watch(playlistsProvider).value?.length ?? 0;
    final themeMode = ref.watch(themeModeProvider);
    final rooms = ref.watch(myRoomsProvider).value?.length ?? 0;
    final recent = ref.watch(recentTracksProvider);
    final character = CartoonAvatar.indexOf(profile.avatarEmoji);
    final c = context.synk;

    return Scaffold(
      body: GridBackdrop(
        child: ListView(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 160),
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
                child: _Hero(profile: profile),
              ),
            ),
            const SizedBox(height: Space.md),
            Text(profile.displayName, textAlign: TextAlign.center, style: context.text.headlineMedium),
            const SizedBox(height: 2),
            Text(
              '@${profile.username}',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
            ),
            if (character != null) ...[
              const SizedBox(height: Space.sm),
              Center(
                child: _Tag(icon: Icons.music_note_rounded, label: CartoonAvatar.names[character]),
              ),
            ],
            const SizedBox(height: Space.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PillButton(
                  label: 'Edit profile',
                  icon: Icons.edit_rounded,
                  height: 40,
                  onPressed: () => _edit(context, profile),
                ),
                const SizedBox(width: Space.sm),
                PillButton(
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  height: 40,
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text:
                          'Come listen with me on ${AppConfig.appName} 🎧 I\'m @${profile.username} — '
                          'join my rooms and we\'ll hear every beat together.',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Row(
                children: [
                  _StatTile(
                    icon: Icons.favorite_rounded,
                    color: c.accent,
                    value: likes,
                    label: 'Liked',
                    onTap: () => context.go(Routes.library),
                  ),
                  const SizedBox(width: Space.md),
                  _StatTile(
                    icon: Icons.queue_music_rounded,
                    color: context.colors.tertiary,
                    value: playlists,
                    label: 'Playlists',
                    onTap: () => context.go(Routes.library),
                  ),
                  const SizedBox(width: Space.md),
                  _StatTile(
                    icon: Icons.sensors_rounded,
                    color: context.colors.primary,
                    value: rooms,
                    label: 'Your rooms',
                    onTap: () => context.go(Routes.home),
                  ),
                ],
              ),
            ),
            SectionHeader('Your vibes', accent: c.accent, action: 'Edit', onAction: () => _edit(context, profile)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: profile.vibes.isEmpty
                  ? Text('Pick a few vibes and we\'ll tune Home to them.', style: context.text.bodySmall)
                  : Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        for (final label in profile.vibes)
                          if (Vibes.byLabel(label) case final v?) _VibeChip(vibe: v),
                      ],
                    ),
            ),
            if (recent.isNotEmpty) ...[
              const SectionHeader('Recently played'),
              SizedBox(
                height: TrackCard.railHeight(context),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  itemCount: recent.length.clamp(0, 12),
                  separatorBuilder: (_, _) => const SizedBox(width: Space.md),
                  itemBuilder: (_, i) =>
                      TrackCard(track: recent[i], onTap: () => playTrackFromList(context, ref, recent, i)),
                ),
              ),
            ],
            if (isGuest)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
                child: Container(
                  padding: const EdgeInsets.all(Space.lg),
                  decoration: BoxDecoration(color: c.brand, borderRadius: Radii.xlAll),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Save your account', style: context.text.titleLarge?.copyWith(color: c.onBrand)),
                      const SizedBox(height: Space.xs),
                      Text(
                        "You're a guest. Link an account to keep your likes and username on any phone.",
                        style: context.text.bodyMedium?.copyWith(color: c.onBrand),
                      ),
                      const SizedBox(height: Space.md),
                      Wrap(
                        spacing: Space.sm,
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: SynkPalette.ink950,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _link(context, ref, apple: false),
                            child: const Text('Link Google'),
                          ),
                          if (Platform.isIOS)
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: SynkPalette.ink950,
                              ),
                              onPressed: () => _link(context, ref, apple: true),
                              child: const Text('Link Apple'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            SectionHeader('Settings', accent: c.brand),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_iphone_rounded), label: Text('Auto')),
                ],
                selected: {themeMode},
                onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
              ),
            ),
            const SizedBox(height: Space.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: _Panel(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(
                  children: [
                    _SettingsRow(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy policy',
                      onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl)),
                    ),
                    _SettingsRow(
                      icon: Icons.description_outlined,
                      title: 'Terms of use',
                      onTap: () => launchUrl(Uri.parse(AppConfig.termsUrl)),
                    ),
                    _SettingsRow(
                      icon: Icons.logout_rounded,
                      title: 'Sign out',
                      subtitle: isGuest ? 'Guest data is lost when you sign out' : null,
                      onTap: () => _signOut(ref),
                    ),
                    _SettingsRow(
                      icon: Icons.delete_forever_rounded,
                      title: 'Delete account',
                      danger: true,
                      onTap: () => _deleteAccount(context, ref, profile),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            Center(
              child: Text(
                '${AppConfig.appName} · ${AppConfig.flavor.name}',
                style: context.text.bodySmall?.copyWith(color: c.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Violet banner with painted records, notes and equaliser bars; the avatar
/// sits on its bottom edge.
class _Hero extends StatelessWidget {
  const _Hero({required this.profile});

  final UserProfile profile;

  static const double _banner = 132;
  static const double _avatar = 112;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return SizedBox(
      height: _banner + _avatar / 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _banner,
            child: ClipRRect(
              borderRadius: Radii.xlAll,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BannerPainter(base: c.brand, accent: c.accent),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: c.background, shape: BoxShape.circle),
                child: SynkAvatar(emoji: profile.avatarEmoji, colorIndex: profile.avatarColor, size: _avatar),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerPainter extends CustomPainter {
  _BannerPainter({required this.base, required this.accent});

  final Color base;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.08);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.12);
    // Two records peeking in from the corners.
    for (final (center, r) in [
      (Offset(size.width * 0.08, size.height * 0.95), size.height * 0.7),
      (Offset(size.width * 0.95, size.height * 0.1), size.height * 0.55),
    ]) {
      canvas.drawCircle(center, r, soft);
      for (var f = 0.35; f < 1; f += 0.16) {
        canvas.drawCircle(center, r * f, ring);
      }
      canvas.drawCircle(center, r * 0.22, Paint()..color = accent.withValues(alpha: 0.55));
    }
    // Equaliser bars along the bottom right.
    final bar = Paint()..color = Colors.white.withValues(alpha: 0.18);
    const heights = [0.3, 0.55, 0.4, 0.75, 0.5, 0.35, 0.6];
    for (var i = 0; i < heights.length; i++) {
      final h = size.height * heights[i] * 0.6;
      final x = size.width * 0.66 + i * 9;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h - 10, 5, h), const Radius.circular(3)),
        bar,
      );
    }
    // A few notes.
    final note = Paint()..color = Colors.white.withValues(alpha: 0.35);
    for (final (x, y, s) in [(0.3, 0.3, 1.0), (0.42, 0.62, 0.7), (0.58, 0.25, 0.85)]) {
      _note(canvas, Offset(size.width * x, size.height * y), 7 * s, note);
    }
  }

  void _note(Canvas canvas, Offset at, double r, Paint paint) {
    canvas
      ..drawOval(Rect.fromCenter(center: at, width: r * 2.2, height: r * 1.6), paint)
      ..drawRect(Rect.fromLTWH(at.dx + r * 0.85, at.dy - r * 3.2, r * 0.3, r * 3.2), paint)
      ..drawRect(Rect.fromLTWH(at.dx + r * 0.85, at.dy - r * 3.2, r * 1.3, r * 0.45), paint);
  }

  @override
  bool shouldRepaint(_BannerPainter old) => old.base != base || old.accent != accent;
}

/// Small rounded tag (the avatar's character).
class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 5),
    decoration: BoxDecoration(
      color: context.synk.surfaceOverlay,
      borderRadius: Radii.pillAll,
      border: Border.all(color: context.synk.glassBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.colors.tertiary),
        const SizedBox(width: 6),
        Text(label, style: context.text.labelMedium),
      ],
    ),
  );
}

/// One number with a coloured icon disc; taps through to where it lives.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Expanded(
      child: Pressable(
        onTap: onTap,
        semanticLabel: '$value $label',
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.lgAll,
            border: Border.all(color: c.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(height: Space.sm),
              Text(Formatters.compact(value), style: context.text.headlineSmall),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// A vibe as a solid colour chip with its icon.
class _VibeChip extends StatelessWidget {
  const _VibeChip({required this.vibe});

  final Vibe vibe;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: () => context.push(Routes.genre(vibe.label)),
    semanticLabel: '${vibe.label} vibe',
    child: Container(
      padding: const EdgeInsets.fromLTRB(Space.sm, 6, Space.md, 6),
      decoration: BoxDecoration(color: SynkPalette.identityColor(vibe.colorIndex), borderRadius: Radii.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vibe.icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(vibe.label, style: context.text.labelMedium?.copyWith(color: Colors.white)),
        ],
      ),
    ),
  );
}

/// Rounded surface for grouped content.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.symmetric(vertical: Space.lg)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: context.synk.surface,
      borderRadius: Radii.xlAll,
      border: Border.all(color: context.synk.glassBorder),
    ),
    child: child,
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final color = danger ? SynkPalette.danger : c.textPrimary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: danger ? SynkPalette.danger.withValues(alpha: 0.14) : c.surfaceOverlay,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: danger ? SynkPalette.danger : c.textSecondary),
      ),
      title: Text(title, style: context.text.titleMedium?.copyWith(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Icon(Icons.chevron_right_rounded, color: c.textMuted),
      onTap: onTap,
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.profile.displayName);
  late String _emoji = widget.profile.avatarEmoji;
  late int _color = widget.profile.avatarColor;
  late final Set<String> _vibes = {...widget.profile.vibes};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(userRepositoryProvider)
          .updateProfile(
            widget.profile.copyWith(
              displayName: name,
              avatarEmoji: _emoji,
              avatarColor: _color,
              vibes: _vibes.toList(),
            ),
          );
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showAppError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit profile', style: context.text.headlineMedium),
              const SizedBox(height: Space.xl),
              AvatarPicker(
                emoji: _emoji,
                color: _color,
                onChanged: (e, c) => setState(() {
                  _emoji = e;
                  _color = c;
                }),
              ),
              const SizedBox(height: Space.xl),
              TextField(
                controller: _name,
                maxLength: 30,
                decoration: const InputDecoration(labelText: 'Display name', counterText: ''),
              ),
              const SizedBox(height: Space.lg),
              Text('Vibes', style: context.text.titleMedium),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final v in Vibes.all)
                    FilterChip(
                      label: Text(v.label),
                      selected: _vibes.contains(v.label),
                      onSelected: (on) => setState(() => on ? _vibes.add(v.label) : _vibes.remove(v.label)),
                    ),
                ],
              ),
              const SizedBox(height: Space.xl),
              PrimaryButton(label: 'Save', loading: _saving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
