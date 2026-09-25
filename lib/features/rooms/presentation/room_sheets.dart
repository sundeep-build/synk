import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/utils/room_code.dart';
import '../../../core/utils/validators.dart';
import '../../auth/application/session.dart';
import '../../catalog/domain/genres.dart';
import '../../catalog/domain/track.dart';
import '../application/room_providers.dart';
import '../application/room_session_controller.dart';
import '../domain/room.dart';

// ── Create ────────────────────────────────────────────────────────────────
Future<void> showCreateRoomSheet(BuildContext context, {Track? startWith}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => _CreateRoomSheet(startWith: startWith),
);

class _CreateRoomSheet extends ConsumerStatefulWidget {
  const _CreateRoomSheet({this.startWith});

  /// "Listen together" from a song: the room opens already playing it.
  final Track? startWith;

  @override
  ConsumerState<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends ConsumerState<_CreateRoomSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late RoomMode _mode = widget.startWith?.isLive ?? false ? RoomMode.radio : RoomMode.music;
  RoomVisibility _visibility = RoomVisibility.public;
  int _capacity = AppConfig.defaultRoomCapacity;
  String? _vibe;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final me = ref.read(currentProfileProvider);
    _name = TextEditingController(text: me == null ? '' : "${me.username}'s room");
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final me = ref.read(currentProfileProvider);
    if (me == null) return;
    setState(() => _busy = true);
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    try {
      final room = await ref
          .read(roomRepositoryProvider)
          .create(host: me, name: _name.text, visibility: _visibility, mode: _mode, capacity: _capacity, vibe: _vibe);
      final session = ref.read(roomSessionProvider.notifier);
      await session.join(room.id);
      if (widget.startWith != null) await session.playOrQueue(widget.startWith!);
      navigator.pop();
      unawaited(router.push(Routes.room(room.id)));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        context.showError(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Start a room', style: context.text.headlineMedium),
                const SizedBox(height: Space.xs),
                Text(
                  'Watch YouTube or listen to live radio together, in sync.',
                  style: context.text.bodyMedium?.copyWith(color: context.synk.textSecondary),
                ),
                const SizedBox(height: Space.xl),
                TextFormField(
                  controller: _name,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Room name', counterText: ''),
                  validator: (v) => Validators.roomName(v ?? ''),
                ),
                const SizedBox(height: Space.lg),
                SegmentedButton<RoomMode>(
                  style: const ButtonStyle(visualDensity: VisualDensity.comfortable),
                  segments: const [
                    ButtonSegment(
                      value: RoomMode.music,
                      icon: Icon(Icons.smart_display_rounded),
                      label: Text('Videos'),
                    ),
                    ButtonSegment(value: RoomMode.radio, icon: Icon(Icons.radio_rounded), label: Text('Radio')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: Space.md),
                SegmentedButton<RoomVisibility>(
                  segments: const [
                    ButtonSegment(
                      value: RoomVisibility.public,
                      icon: Icon(Icons.public_rounded),
                      label: Text('Public'),
                    ),
                    ButtonSegment(
                      value: RoomVisibility.private,
                      icon: Icon(Icons.lock_rounded),
                      label: Text('Code only'),
                    ),
                  ],
                  selected: {_visibility},
                  onSelectionChanged: (s) => setState(() => _visibility = s.first),
                ),
                const SizedBox(height: Space.xl),
                Text('Vibe', style: context.text.titleMedium),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final v in Vibes.all)
                      ChoiceChip(
                        label: Text(v.label),
                        avatar: Icon(v.icon, size: 16),
                        selected: _vibe == v.label,
                        onSelected: (on) => setState(() => _vibe = on ? v.label : null),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xl),
                Text('Max listeners', style: context.text.titleMedium),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.sm,
                  children: [
                    for (final n in const [10, 25, AppConfig.maxRoomCapacity])
                      ChoiceChip(
                        label: Text('$n'),
                        selected: _capacity == n,
                        onSelected: (_) => setState(() => _capacity = n),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xxl),
                PrimaryButton(label: 'Go live', icon: Icons.sensors_rounded, loading: _busy, onPressed: _create),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Join by code ──────────────────────────────────────────────────────────
Future<void> showJoinRoomSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => const _JoinRoomSheet(),
);

class _JoinRoomSheet extends ConsumerStatefulWidget {
  const _JoinRoomSheet();

  @override
  ConsumerState<_JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends ConsumerState<_JoinRoomSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    try {
      final roomId = await ref.read(roomRepositoryProvider).resolveCode(_code.text);
      navigator.pop();
      unawaited(router.push(Routes.room(roomId)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppException.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = RoomCode.isValid(RoomCode.normalize(_code.text));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Join with a code', style: context.text.headlineMedium),
              const SizedBox(height: Space.xl),
              TextField(
                controller: _code,
                autofocus: true,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: RoomCode.length,
                style: context.text.displaySmall?.copyWith(letterSpacing: 10),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase())),
                ],
                decoration: InputDecoration(hintText: 'ABC234', counterText: '', errorText: _error),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => ready ? _join() : null,
              ),
              const SizedBox(height: Space.xl),
              PrimaryButton(label: 'Join room', loading: _busy, onPressed: ready ? _join : null),
            ],
          ),
        ),
      ),
    );
  }
}
