import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/design_system/design_system.dart';
import '../../application/room_providers.dart';
import '../../application/room_session_controller.dart';
import '../../domain/room_live_models.dart';
import '../add_music_sheet.dart';
import '../dedicate_sheet.dart';

/// Live-stream style chat (avatar · name · text), newest at the bottom.
class RoomChatView extends ConsumerWidget {
  const RoomChatView({required this.roomId, required this.myUid, super.key});

  final String roomId;
  final String myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(roomChatProvider(roomId));
    if (messages.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.waving_hand_rounded,
          title: 'Say hi 👋',
          message: 'Chat, react, dedicate a song.',
        ),
      );
    }
    final count = messages.length;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
      itemCount: count,
      itemBuilder: (_, i) {
        final m = messages[count - 1 - i];
        final prev = count - 2 - i >= 0 ? messages[count - 2 - i] : null;
        final grouped =
            prev != null &&
            prev.uid == m.uid &&
            prev.kind == ChatKind.text &&
            m.kind == ChatKind.text &&
            m.ts - prev.ts < 120000;
        return switch (m.kind) {
          ChatKind.dedication => _DedicationCard(message: m),
          ChatKind.system => _SystemLine(text: m.text),
          ChatKind.text => _ChatLine(message: m, mine: m.uid == myUid, grouped: grouped),
        };
      },
    );
  }
}

/// A chat bubble: yours on the right in brand violet; everyone else's on the
/// left with their avatar and name (once per run of messages).
class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.message, required this.mine, required this.grouped});

  final ChatMessage message;
  final bool mine;
  final bool grouped;

  static const _round = Radius.circular(18);
  static const _tail = Radius.circular(6);

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
      decoration: BoxDecoration(
        color: mine ? c.brand : c.surfaceRaised,
        border: mine ? null : Border.all(color: c.glassBorder),
        borderRadius: BorderRadius.only(
          topLeft: !mine && !grouped ? _tail : _round,
          topRight: mine && !grouped ? _tail : _round,
          bottomLeft: _round,
          bottomRight: _round,
        ),
      ),
      child: Text(message.text, style: context.text.bodyMedium?.copyWith(color: mine ? c.onBrand : c.textPrimary)),
    );
    final top = EdgeInsets.only(top: grouped ? 3 : Space.md);
    if (mine) {
      return Padding(
        padding: top,
        child: Align(alignment: Alignment.centerRight, child: bubble),
      );
    }
    return Padding(
      padding: top,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: grouped ? null : SynkAvatar(emoji: message.emoji, colorIndex: message.color, size: 30),
          ),
          const SizedBox(width: Space.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!grouped)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.xs, bottom: 2),
                    child: Text(
                      message.name,
                      style: context.text.labelSmall?.copyWith(color: c.identityText(message.color)),
                    ),
                  ),
                bubble,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.md),
    child: Center(child: Text(text, style: context.text.bodySmall)),
  );
}

class _DedicationCard extends StatelessWidget {
  const _DedicationCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final track = message.track;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(color: context.synk.brand, borderRadius: Radii.lgAll),
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: context.synk.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.lg - 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '🎁 '),
                    TextSpan(text: message.name, style: context.weight(context.text.bodyMedium, FontWeight.w800)),
                    const TextSpan(text: ' dedicated a song to '),
                    TextSpan(
                      text: message.toName ?? 'the room',
                      style: context.weight(context.text.bodyMedium, FontWeight.w800),
                    ),
                  ],
                ),
                style: context.text.bodyMedium,
              ),
              if (track != null) ...[
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Artwork(url: track.artworkUrl, size: 44, seed: track.seed),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleSmall,
                          ),
                          Text(track.artist, maxLines: 1, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              if (message.text.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text('“${message.text}”', style: context.text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Reaction bar + message field + dedicate. Reactions are spawned locally
/// right away (via [onLocalReaction]) so the tap feels instant.
class RoomComposer extends ConsumerStatefulWidget {
  const RoomComposer({required this.radio, required this.onLocalReaction, super.key});

  final bool radio;
  final ValueChanged<String> onLocalReaction;

  @override
  ConsumerState<RoomComposer> createState() => _RoomComposerState();
}

class _RoomComposerState extends ConsumerState<RoomComposer> {
  final _text = TextEditingController();
  DateTime _lastReaction = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sending = false;

  /// The reaction tray above the field (folded away to save chat space).
  bool _tray = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _handleError(Object e) {
    if (!mounted) return;
    // RTDB rules reject bursts (>1 msg/sec) with permission-denied.
    if (e is FirebaseException && e.code.contains('permission')) {
      context.showSnack('Easy there — slow down a little.');
    } else {
      context.showError(e);
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(roomSessionProvider.notifier).sendMessage(text);
      _text.clear();
    } catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _react(String emoji) {
    final now = DateTime.now();
    if (now.difference(_lastReaction) < const Duration(milliseconds: 350)) return;
    _lastReaction = now;
    HapticFeedback.lightImpact();
    widget.onLocalReaction(emoji);
    ref.read(roomSessionProvider.notifier).react(emoji).catchError(_handleError);
  }

  void _dedicate() {
    showAddMusicSheet(
      context,
      radio: false,
      onPick: (track) {
        if (mounted) showDedicateSheet(context, track);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: Motion.fast,
              curve: Motion.standard,
              child: !_tray
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: Radii.pillAll,
                          border: Border.all(color: c.glassBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            for (final e in Reaction.allowed)
                              Semantics(
                                button: true,
                                label: 'React $e',
                                child: InkResponse(
                                  onTap: () => _react(e),
                                  radius: 24,
                                  child: Padding(
                                    padding: const EdgeInsets.all(Space.sm),
                                    child: Text(e, style: const TextStyle(fontSize: 24)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            Row(
              children: [
                CircleIconButton(
                  icon: _tray ? Icons.close_rounded : Icons.emoji_emotions_outlined,
                  tooltip: _tray ? 'Hide reactions' : 'React',
                  size: 42,
                  onPressed: () => setState(() => _tray = !_tray),
                ),
                if (!widget.radio)
                  IconButton(
                    tooltip: 'Dedicate a song',
                    icon: const Icon(Icons.card_giftcard_rounded),
                    color: c.accent,
                    onPressed: _dedicate,
                  )
                else
                  const SizedBox(width: Space.sm),
                Expanded(
                  child: TextField(
                    controller: _text,
                    maxLength: AppConfig.maxChatLength,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    onTap: () {
                      if (_tray) setState(() => _tray = false);
                    },
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: 'Say something…',
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: c.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                      border: const OutlineInputBorder(borderRadius: Radii.pillAll, borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: Radii.pillAll,
                        borderSide: BorderSide(color: c.glassBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: Radii.pillAll,
                        borderSide: BorderSide(color: context.colors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                ValueListenableBuilder(
                  valueListenable: _text,
                  builder: (_, value, _) => IconButton.filled(
                    tooltip: 'Send',
                    style: IconButton.styleFrom(backgroundColor: c.brand, foregroundColor: c.onBrand),
                    onPressed: value.text.trim().isEmpty || _sending ? null : _send,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
