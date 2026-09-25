import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/utils/debouncer.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../application/room_session_controller.dart';

/// In-room music picker. Radio rooms search stations; music rooms search songs.
/// With [onPick], the chosen track is returned instead of being queued
/// (used by the dedication flow).
Future<void> showAddMusicSheet(BuildContext context, {required bool radio, void Function(Track track)? onPick}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        builder: (_, controller) => _AddMusicSheet(radio: radio, onPick: onPick, scroll: controller),
      ),
    );

class _AddMusicSheet extends ConsumerStatefulWidget {
  const _AddMusicSheet({required this.radio, required this.scroll, this.onPick});

  final bool radio;
  final ScrollController scroll;
  final void Function(Track track)? onPick;

  @override
  ConsumerState<_AddMusicSheet> createState() => _AddMusicSheetState();
}

class _AddMusicSheetState extends ConsumerState<_AddMusicSheet> {
  final _debouncer = Debouncer(const Duration(milliseconds: 350));
  String _query = '';

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _choose(Track track) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();
    if (widget.onPick != null) {
      widget.onPick!(track);
      return;
    }
    try {
      await ref.read(roomSessionProvider.notifier).playOrQueue(track);
      messenger.showSnackBar(SnackBar(content: Text('${track.title} added')));
    } catch (e) {
      messenger.showAppError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = switch ((_query.isEmpty, widget.radio)) {
      (true, true) => ref.watch(nearbyStationsProvider),
      (true, false) => ref.watch(trendingVideosProvider),
      (false, true) => ref.watch(stationSearchProvider(_query)),
      (false, false) => ref.watch(videoSearchProvider(_query)),
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
          child: TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: widget.radio ? 'Search stations' : 'Search songs or videos, then press search',
            ),
            // Stations search as you type (free); YouTube only on submit (100 quota units).
            onChanged: widget.radio
                ? (v) => _debouncer(() {
                    if (mounted) setState(() => _query = v.trim());
                  })
                : null,
            onSubmitted: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _query.isEmpty ? (widget.radio ? 'Popular near you' : 'Trending music videos') : 'Results',
              style: context.text.titleSmall?.copyWith(color: context.synk.textSecondary),
            ),
          ),
        ),
        Expanded(
          child: results.when(
            loading: () => const TrackListSkeleton(),
            error: (e, _) => ErrorState(error: e),
            data: (tracks) => tracks.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Nothing found',
                    message: 'Try another search.',
                  )
                : ListView.builder(
                    controller: widget.scroll,
                    itemCount: tracks.length,
                    itemBuilder: (_, i) => TrackTile(
                      track: tracks[i],
                      onTap: () => _choose(tracks[i]),
                      trailing: IconButton(
                        tooltip: 'Add',
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        onPressed: () => _choose(tracks[i]),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
