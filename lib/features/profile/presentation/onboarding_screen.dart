import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/validators.dart';
import '../../auth/application/session.dart';
import '../../catalog/domain/genres.dart';
import 'avatar_picker.dart';

/// 3 quick steps: name → look → vibes. Each fits on one screen with one
/// obvious primary action, and the username is checked *while typing*
/// (Groic's "please enter a valid username" loop was a top complaint).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _NameStatus { idle, checking, available, taken, invalid, error }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  final _username = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 400));
  int _step = 0;
  _NameStatus _status = _NameStatus.idle;
  String? _nameError;
  String _emoji = SynkPalette.avatarEmojis.first;
  int _color = 0;
  final Set<String> _vibes = {};
  bool _saving = false;

  @override
  void dispose() {
    _pages.dispose();
    _username.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    final error = Validators.username(value);
    setState(() {
      _nameError = error;
      _status = error == null ? _NameStatus.checking : _NameStatus.invalid;
    });
    if (error != null) return;
    _debouncer(() async {
      final checked = value;
      try {
        final free = await ref.read(userRepositoryProvider).isUsernameAvailable(checked);
        if (!mounted || _username.text != checked) return;
        setState(() => _status = free ? _NameStatus.available : _NameStatus.taken);
      } catch (_) {
        if (mounted && _username.text == checked) setState(() => _status = _NameStatus.error);
      }
    });
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pages.animateToPage(step, duration: Motion.medium, curve: Motion.emphasized);
  }

  Future<void> _finish() async {
    final user = ref.read(authUserProvider).value;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .createProfile(
            uid: user.uid,
            username: _username.text,
            avatarEmoji: _emoji,
            avatarColor: _color,
            vibes: _vibes.toList(),
          );
      unawaited(HapticFeedback.mediumImpact());
      // Session becomes Ready → router moves to Home.
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showError(e);
      // Someone grabbed the name in the meantime → back to step 1.
      _goTo(0);
      _onNameChanged(_username.text);
    }
  }

  bool get _canContinue => switch (_step) {
    0 => _status == _NameStatus.available,
    1 => true,
    _ => _vibes.isNotEmpty,
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) _goTo(_step - 1);
      },
      child: Scaffold(
        body: GridBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.gutter, 0),
                  child: Row(
                    children: [
                      AnimatedOpacity(
                        duration: Motion.fast,
                        opacity: _step == 0 ? 0.35 : 1,
                        child: CircleIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          size: 42,
                          onPressed: _step == 0 ? null : () => _goTo(_step - 1),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: AnimatedContainer(
                            duration: Motion.medium,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: Radii.pillAll,
                              color: i <= _step ? context.synk.brand : context.synk.glassBorder,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [_nameStep(), _avatarStep(), _vibesStep()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
                  child: PrimaryButton(
                    label: _step < 2 ? 'Continue' : "Let's go",
                    loading: _saving,
                    onPressed: _canContinue ? (_step < 2 ? () => _goTo(_step + 1) : _finish) : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepScaffold({required int index, required String title, required String subtitle, required Widget child}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Space.lg),
          Text(
            'STEP ${index + 1} OF 3',
            style: context.text.labelSmall?.copyWith(letterSpacing: 2, color: context.colors.primary),
          ),
          const SizedBox(height: Space.sm),
          SplitTitle(title, style: context.text.displaySmall, maxLines: 2),
          const SizedBox(height: Space.sm),
          Text(subtitle, style: context.text.bodyLarge?.copyWith(color: context.synk.textSecondary)),
          const SizedBox(height: Space.xxl),
          child,
        ],
      ),
    );
  }

  Widget _nameStep() {
    final c = context.synk;
    final (Widget? suffix, String? helper) = switch (_status) {
      _NameStatus.checking => (
        const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        'Checking…',
      ),
      _NameStatus.available => (Icon(Icons.check_circle_rounded, color: c.online), "Nice — it's yours"),
      _NameStatus.taken => (const Icon(Icons.cancel_rounded, color: SynkPalette.danger), 'Already taken'),
      _NameStatus.error => (null, "Couldn't check right now — try again"),
      _ => (null, null),
    };
    return _stepScaffold(
      index: 0,
      title: 'Pick a username',
      subtitle: 'This is how people see you in rooms.',
      child: TextField(
        controller: _username,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_.]')),
          LengthLimitingTextInputFormatter(20),
          TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toLowerCase())),
        ],
        style: context.text.titleLarge,
        decoration: InputDecoration(
          prefixText: '@ ',
          hintText: 'yourname',
          suffixIcon: suffix,
          errorText: _status == _NameStatus.invalid ? _nameError : (_status == _NameStatus.taken ? helper : null),
          helperText: _status == _NameStatus.taken || _status == _NameStatus.invalid ? null : helper,
        ),
        onChanged: _onNameChanged,
        onSubmitted: (_) => _canContinue ? _goTo(1) : null,
      ),
    );
  }

  Widget _avatarStep() => _stepScaffold(
    index: 1,
    title: 'Choose your look',
    subtitle: 'Your avatar shows up in chat and on rooms you host.',
    child: AvatarPicker(
      emoji: _emoji,
      color: _color,
      onChanged: (emoji, color) => setState(() {
        _emoji = emoji;
        _color = color;
      }),
    ),
  );

  Widget _vibesStep() => _stepScaffold(
    index: 2,
    title: "What's your vibe?",
    subtitle: 'Pick a few — we use them to suggest rooms and music.',
    child: Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final v in Vibes.all)
          FilterChip(
            avatar: Icon(v.icon, size: 18),
            label: Text(v.label),
            selected: _vibes.contains(v.label),
            onSelected: (on) => setState(() => on ? _vibes.add(v.label) : _vibes.remove(v.label)),
          ),
      ],
    ),
  );
}
