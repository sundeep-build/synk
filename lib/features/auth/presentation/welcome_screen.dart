import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../application/session.dart';

/// The Synk mark (the "S" with a play button) on its navy-black tile. Built
/// with the launcher icons by scripts/brand/build_icons.py.
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
    semanticLabel: '${AppConfig.appName} logo',
  );
}

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: Center(
        child: session is SessionError
            ? ErrorState(error: session.error, onRetry: () => retrySession(ref))
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppLogo(size: 72),
                  SizedBox(height: Space.xl),
                  EqualizerBars(size: 22, bars: 5),
                ],
              ),
      ),
    );
  }
}

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

enum _Method { google, apple, guest }

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  _Method? _busy;

  Future<void> _signIn(_Method method) async {
    if (_busy != null) return;
    setState(() => _busy = method);
    final auth = ref.read(authRepositoryProvider);
    try {
      await switch (method) {
        _Method.google => auth.signInWithGoogle(),
        _Method.apple => auth.signInWithApple(),
        _Method.guest => auth.continueAsGuest(),
      };
      // Router redirects automatically once the session changes.
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppLogo(size: 40),
                    const SizedBox(width: Space.md),
                    Text(AppConfig.appName, style: context.text.headlineSmall),
                  ],
                ),
                const Spacer(),
                Text('Why listen\nalone?', style: context.text.displayLarge),
                const SizedBox(height: Space.lg),
                Text(
                  'Rooms where friends hear the same beat at the same second — '
                  'with live chat, reactions and song dedications.',
                  style: context.text.bodyLarge?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: Space.xl),
                const Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    _Perk(icon: Icons.sync_rounded, label: 'Perfectly in sync'),
                    _Perk(icon: Icons.smart_display_rounded, label: 'YouTube watch parties'),
                    _Perk(icon: Icons.radio_rounded, label: 'Radio plays in background'),
                  ],
                ),
                const Spacer(),
                _SignInButton(
                  label: 'Continue with Google',
                  icon: Icons.account_circle_rounded,
                  loading: _busy == _Method.google,
                  onPressed: () => _signIn(_Method.google),
                ),
                if (Platform.isIOS) ...[
                  const SizedBox(height: Space.md),
                  _SignInButton(
                    label: 'Continue with Apple',
                    icon: Icons.apple_rounded,
                    loading: _busy == _Method.apple,
                    onPressed: () => _signIn(_Method.apple),
                  ),
                ],
                const SizedBox(height: Space.md),
                Center(
                  child: TextButton(
                    onPressed: () => _signIn(_Method.guest),
                    child: _busy == _Method.guest
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Just look around'),
                  ),
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'By continuing you agree to our Terms and Privacy Policy.',
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => GlassPanel(
    radius: Radii.pillAll,
    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: context.colors.primary),
        const SizedBox(width: 6),
        Text(label, style: context.text.labelMedium),
      ],
    ),
  );
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.label, required this.icon, required this.loading, required this.onPressed});

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: c.textPrimary, foregroundColor: c.background),
        onPressed: loading ? null : onPressed,
        icon: loading
            ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.background))
            : Icon(icon),
        label: Text(label),
      ),
    );
  }
}
