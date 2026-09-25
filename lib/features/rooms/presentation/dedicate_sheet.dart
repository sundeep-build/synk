import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../catalog/domain/track.dart';
import '../application/room_session_controller.dart';

/// "Dedications" — send a song with a message to someone in the room.
/// Shows up as a highlighted card in chat and adds the song to the queue.
Future<void> showDedicateSheet(BuildContext context, Track track) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => _DedicateSheet(track: track),
);

class _DedicateSheet extends ConsumerStatefulWidget {
  const _DedicateSheet({required this.track});

  final Track track;

  @override
  ConsumerState<_DedicateSheet> createState() => _DedicateSheetState();
}

class _DedicateSheetState extends ConsumerState<_DedicateSheet> {
  final _to = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _to.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_to.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(roomSessionProvider.notifier).dedicate(widget.track, toName: _to.text, note: _note.text);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Dedication sent 🎁')));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showAppError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(roomSessionProvider);
    final others = session?.members.where((m) => m.uid != session.myUid).toList() ?? const [];
    final c = context.synk;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dedicate a song', style: context.text.headlineMedium),
              const SizedBox(height: Space.lg),
              GlassPanel(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    Artwork(url: widget.track.artworkUrl, size: 56, seed: widget.track.seed),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.track.title,
                            style: context.text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(widget.track.artist, style: context.text.bodySmall, maxLines: 1),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              TextField(
                controller: _to,
                maxLength: 30,
                decoration: const InputDecoration(labelText: 'For', hintText: 'maya, the whole room…', counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: others.length,
                    separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
                    itemBuilder: (_, i) {
                      final m = others[i];
                      return ActionChip(
                        avatar: Text(m.emoji),
                        label: Text('@${m.name}'),
                        onPressed: () => setState(() => _to.text = m.name),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: Space.lg),
              TextField(
                controller: _note,
                maxLength: 140,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Message',
                  hintText: 'This one always reminds me of you',
                  hintStyle: context.text.bodyLarge?.copyWith(color: c.textMuted),
                ),
              ),
              const SizedBox(height: Space.xl),
              PrimaryButton(
                label: 'Send dedication',
                icon: Icons.card_giftcard_rounded,
                loading: _busy,
                onPressed: _to.text.trim().isEmpty ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
