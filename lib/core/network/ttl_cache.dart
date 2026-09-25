import 'dart:collection';

/// Small in-memory LRU cache with per-entry expiry.
///
/// Bounded by [maxEntries] so catalog browsing never grows memory unbounded.
class TtlCache<K, V> {
  TtlCache({this.maxEntries = 64, this.ttl = const Duration(minutes: 5)});

  final int maxEntries;
  final Duration ttl;
  final LinkedHashMap<K, ({V value, DateTime expiresAt})> _entries = LinkedHashMap();

  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) return null;
    _entries[key] = entry; // re-insert → most recently used
    return entry.value;
  }

  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = (value: value, expiresAt: DateTime.now().add(ttl));
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  Future<V> getOrLoad(K key, Future<V> Function() load) async {
    final cached = get(key);
    if (cached != null) return cached;
    final value = await load();
    put(key, value);
    return value;
  }

  void clear() => _entries.clear();
}
