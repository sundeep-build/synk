import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/utils/debouncer.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../../player/application/play_actions.dart';
import '../../rooms/presentation/room_sheets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 350));
  String _query = '';
  bool _radio = false;

  @override
  void dispose() {
    _controller.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  /// Radio searches as you type (free). YouTube searches only on submit: each
  /// one costs 100 of the API's 10,000 daily units.
  void _setQuery(String value, {bool immediate = false}) {
    void apply() {
      if (!mounted) return;
      setState(() => _query = value.trim());
      if (value.trim().length > 1) ref.read(localStoreProvider).addRecentSearch(value);
    }

    if (immediate) {
      apply();
    } else if (_radio) {
      _debouncer(apply);
    } else {
      setState(() {}); // just refresh the clear button; wait for submit
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(localStoreProvider);
    // Clears the floating dock.
    final bottomInset = MediaQuery.paddingOf(context).bottom + 160;

    return Scaffold(
      body: GridBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Room code" lives beside the title so the filter row below never
                    // has to share its width (it overflowed on 360dp phones).
                    Row(
                      children: [
                        const Expanded(child: SplitTitle('Search music')),
                        PillButton(
                          label: 'Room code',
                          icon: Icons.pin_rounded,
                          onPressed: () => showJoinRoomSheet(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.lg),
                    TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onChanged: _setQuery,
                      onSubmitted: (v) => _setQuery(v, immediate: true),
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: _radio ? 'Stations, cities, genres' : 'Songs, artists, videos — then search',
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _controller.clear();
                                  _setQuery('', immediate: true);
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.smart_display_rounded, size: 16),
                          label: const Text('Videos'),
                          selected: !_radio,
                          onSelected: (_) => setState(() => _radio = false),
                        ),
                        const SizedBox(width: Space.sm),
                        ChoiceChip(
                          avatar: const Icon(Icons.radio_rounded, size: 16),
                          label: const Text('Radio'),
                          selected: _radio,
                          onSelected: (_) => setState(() {
                            _radio = true;
                            _query = _controller.text.trim(); // radio results are free: show them now
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _query.isEmpty
                    ? _RecentSearches(
                        searches: store.recentSearches,
                        onPick: (q) {
                          _controller.text = q;
                          _setQuery(q, immediate: true);
                        },
                        onClear: () async {
                          await store.clearRecentSearches();
                          setState(() {});
                        },
                      )
                    : _Results(query: _query, radio: _radio, bottomInset: bottomInset),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.radio, required this.bottomInset});

  final String query;
  final bool radio;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Track>> results = radio
        ? ref.watch(stationSearchProvider(query))
        : ref.watch(videoSearchProvider(query));
    return results.when(
      loading: () => const SingleChildScrollView(child: TrackListSkeleton()),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () =>
            radio ? ref.invalidate(stationSearchProvider(query)) : ref.invalidate(videoSearchProvider(query)),
      ),
      data: (tracks) => tracks.isEmpty
          ? EmptyState(icon: Icons.search_off_rounded, title: 'No matches', message: 'Nothing for "$query" yet.')
          : TrackListView(
              tracks: tracks,
              onTap: (i) => playTrackFromList(context, ref, tracks, i),
              padding: EdgeInsets.only(bottom: bottomInset),
            ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.searches, required this.onPick, required this.onClear});

  final List<String> searches;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (searches.isEmpty) {
      return const EmptyState(
        icon: Icons.travel_explore_rounded,
        title: 'Find your sound',
        message: 'Songs and music videos from YouTube, plus thousands of live radio stations.',
      );
    }
    final c = context.synk;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        SectionHeader('Recent searches', action: 'Clear', onAction: onClear),
        for (final q in searches)
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.surfaceOverlay, shape: BoxShape.circle),
              child: Icon(Icons.history_rounded, size: 18, color: c.textSecondary),
            ),
            title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Icon(Icons.north_west_rounded, size: 18, color: c.textMuted),
            onTap: () => onPick(q),
          ),
      ],
    );
  }
}
