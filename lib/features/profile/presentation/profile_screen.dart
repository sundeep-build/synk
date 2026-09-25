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
    final c = context.synk;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Space.xxl),
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
                  OutlinedButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      builder: (_) => _EditProfileSheet(profile: profile),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit profile'),
                  ),
                  const SizedBox(height: Space.xl),
                  Row(
                    children: [
                      _Stat(value: '$likes', label: 'Liked'),
                      _Stat(value: '$playlists', label: 'Playlists'),
                      _Stat(value: '${profile.vibes.length}', label: 'Vibes'),
                    ],
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
                decoration: BoxDecoration(color: c.brand, borderRadius: Radii.lgAll),
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
          const SectionHeader('Settings'),
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
          const SizedBox(height: Space.md),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of use'),
            onTap: () => launchUrl(Uri.parse(AppConfig.termsUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            subtitle: isGuest ? const Text('Guest data is lost when you sign out') : null,
            onTap: () => _signOut(ref),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: SynkPalette.danger),
            title: const Text('Delete account', style: TextStyle(color: SynkPalette.danger)),
            onTap: () => _deleteAccount(context, ref, profile),
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
