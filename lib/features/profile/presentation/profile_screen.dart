import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/di/core_providers.dart';
import '../../auth/application/session.dart';
import '../../catalog/domain/genres.dart';
import '../../library/application/library_providers.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final isGuest = ref.watch(isGuestProvider);
    final likes = ref.watch(likedIdsProvider).length;
    final playlists = ref.watch(playlistsProvider).value?.length ?? 0;
    final themeMode = ref.watch(themeModeProvider);
    final rooms = ref.watch(myRoomsProvider).value?.length ?? 0;
    final c = context.synk;

    return Scaffold(
      body: GridBackdrop(
        child: ListView(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 160),
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
                child: Column(
                  children: [
                    SynkAvatar(emoji: profile.avatarEmoji, colorIndex: profile.avatarColor, size: 104, ring: true),
                    const SizedBox(height: Space.lg),
                    Text(profile.displayName, style: context.text.headlineMedium),
                    Text('@${profile.username}', style: context.text.bodyMedium?.copyWith(color: c.textSecondary)),
                    const SizedBox(height: Space.lg),
                    PillButton(
                      label: 'Edit profile',
                      icon: Icons.edit_rounded,
                      height: 38,
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        useRootNavigator: true,
                        isScrollControlled: true,
                        builder: (_) => _EditProfileSheet(profile: profile),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    _Panel(
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            _Stat(value: '$likes', label: 'Liked'),
                            VerticalDivider(color: c.glassBorder, width: 1),
                            _Stat(value: '$playlists', label: 'Playlists'),
                            VerticalDivider(color: c.glassBorder, width: 1),
                            _Stat(value: '$rooms', label: 'Your rooms'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: context.text.headlineSmall),
        Text(label, style: context.text.bodySmall),
      ],
    ),
  );
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
