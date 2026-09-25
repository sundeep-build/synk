import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../application/session.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: GridBackdrop(
        child: Center(
          child: session is SessionError
              ? ErrorState(error: session.error, onRetry: () => retrySession(ref))
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(borderRadius: Radii.lgAll, child: AppLogo(size: 72)),
                    SizedBox(height: Space.xl),
                    EqualizerBars(size: 22, bars: 5),
                  ],
                ),
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

/// One welcome headline: (text, tone) runs, where tone 0 = bright, 1 = muted,
/// 2 = pink.
typedef _Headline = List<(String, int)>;

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  static const _headlines = <_Headline>[
    [('Listen to ', 0), ('the\n', 1), ('Best ', 0), ('Music\n', 2), ('Together', 0)],
    [('Watch ', 0), ('videos\n', 1), ('in perfect ', 0), ('sync', 2)],
    [('Talk it out\n', 0), ('in a ', 1), ('huddle', 2), (',\nlive', 0)],
  ];
  static const _captions = [
    'Rooms where friends hear the same beat at the same second.',
    'YouTube watch parties and live radio, synced for everyone in the room.',
    'Voice and video calls right inside the room, over the music.',
  ];
  static const _storyLength = Duration(seconds: 4);

  _Method? _busy;
  int _story = 0;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Stories advance on their own, unless the OS asks for less motion.
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) {
      _timer = Timer.periodic(_storyLength, (_) => setState(() => _story = (_story + 1) % _headlines.length));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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
    final tones = [c.textPrimary, c.textMuted, c.accent];
    return Scaffold(
      body: GridBackdrop(
        child: SafeArea(
          // Fills the screen, the records taking whatever height is spare;
          // scrolls instead of overflowing on short phones at large text.
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _story = (_story + 1) % _headlines.length),
                        child: _StorySegments(count: _headlines.length, index: _story),
                      ),
                    ),
                    const Expanded(child: _VinylCollage()),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConfig.appName.toUpperCase(),
                            style: context.weight(context.text.labelLarge, FontWeight.w800).copyWith(letterSpacing: 3),
                          ),
                          const SizedBox(height: Space.sm),
                          AnimatedSwitcher(
                            duration: Motion.slow,
                            layoutBuilder: (current, previous) =>
                                Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                            child: Column(
                              key: ValueKey(_story),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      for (final (text, tone) in _headlines[_story])
                                        TextSpan(
                                          text: text,
                                          style: TextStyle(color: tones[tone]),
                                        ),
                                    ],
                                  ),
                                  style: context.text.displaySmall?.copyWith(height: 1.15),
                                ),
                                const SizedBox(height: Space.md),
                                Text(
                                  _captions[_story],
                                  style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.xl),
                          PrimaryButton(
                            label: 'Continue with Google',
                            icon: Icons.account_circle_rounded,
                            loading: _busy == _Method.google,
                            onPressed: () => _signIn(_Method.google),
                          ),
                          if (Platform.isIOS) ...[
                            const SizedBox(height: Space.md),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: OutlinedButton.icon(
                                onPressed: _busy == null ? () => _signIn(_Method.apple) : null,
                                icon: _busy == _Method.apple
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.apple_rounded),
                                label: const Text('Continue with Apple'),
                              ),
                            ),
                          ],
                          const SizedBox(height: Space.sm),
                          Center(
                            child: TextButton(
                              onPressed: () => _signIn(_Method.guest),
                              child: _busy == _Method.guest
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Not now? ',
                                            style: context
                                                .weight(context.text.labelLarge, FontWeight.w500)
                                                .copyWith(color: c.textSecondary),
                                          ),
                                          TextSpan(
                                            text: 'Just look around',
                                            style: TextStyle(color: context.colors.tertiary),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                          Text(
                            'By continuing you agree to our Terms and Privacy Policy.',
                            textAlign: TextAlign.center,
                            style: context.text.bodySmall?.copyWith(color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Story-style progress bars along the top; the current one fills up.
class _StorySegments extends StatelessWidget {
  const _StorySegments({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i <= index ? c.textPrimary : c.textMuted.withValues(alpha: 0.3),
                  borderRadius: Radii.pillAll,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Records fanned across the middle of the screen, with a field of faint
/// discs behind. Painted, not photos: sharp at any size, and no image
/// rights to worry about.
class _VinylCollage extends StatelessWidget {
  const _VinylCollage();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _VinylPainter(
          background: context.synk.background,
          labels: const [SynkPalette.cyan, SynkPalette.brand, SynkPalette.pink, SynkPalette.coral],
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  _VinylPainter({required this.background, required this.labels});

  final Color background;
  final List<Color> labels;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final unit = math.min(size.width / 3.4, size.height / 2.2);

    // Background field of faint discs.
    final faint = Paint()..color = Colors.white.withValues(alpha: 0.03);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.035);
    final step = unit * 0.9;
    for (var y = step * 0.5; y < size.height; y += step) {
      for (var x = step * 0.5; x < size.width + step; x += step) {
        final o = Offset(x - ((y / step).floor().isOdd ? step / 2 : 0), y);
        canvas
          ..drawCircle(o, step * 0.38, faint)
          ..drawCircle(o, step * 0.24, ring);
      }
    }

    // Front records: left, right, then the big centre one on top.
    final cy = size.height * 0.52;
    final records = [
      (Offset(size.width * 0.18, cy + unit * 0.28), unit * 0.62, labels[0]),
      (Offset(size.width * 0.82, cy + unit * 0.28), unit * 0.62, labels[2]),
      (Offset(size.width * 0.34, cy - unit * 0.12), unit * 0.7, labels[3]),
      (Offset(size.width * 0.66, cy - unit * 0.12), unit * 0.7, labels[0]),
      (Offset(size.width * 0.5, cy + unit * 0.05), unit * 0.86, labels[1]),
    ];
    for (final (center, radius, label) in records) {
      _record(canvas, center, radius, label);
    }
  }

  void _record(Canvas canvas, Offset c, double r, Color label) {
    canvas
      ..drawCircle(c + Offset(0, r * 0.08), r, Paint()..color = Colors.black.withValues(alpha: 0.35))
      ..drawCircle(c, r, Paint()..color = const Color(0xFF0A0A12));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var f = 0.46; f < 0.97; f += 0.07) {
      groove.color = Colors.white.withValues(alpha: 0.05 + 0.03 * ((f * 100).round() % 2));
      canvas.drawCircle(c, r * f, groove);
    }
    // A sheen across the grooves so it reads as vinyl.
    canvas
      ..drawArc(
        Rect.fromCircle(center: c, radius: r * 0.8),
        -2.2,
        0.9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.3
          ..color = Colors.white.withValues(alpha: 0.05),
      )
      ..drawCircle(c, r * 0.36, Paint()..color = label)
      ..drawCircle(
        c,
        r * 0.36,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black.withValues(alpha: 0.25),
      )
      ..drawCircle(c, r * 0.06, Paint()..color = background);
  }

  @override
  bool shouldRepaint(_VinylPainter old) => old.background != background || old.labels != labels;
}
