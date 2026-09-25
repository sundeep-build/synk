/// Pure validation helpers shared by UI and repositories (and mirrored in the
/// Firestore rules — keep `firebase/firestore.rules` in sync).
abstract final class Validators {
  static final RegExp _username = RegExp(r'^[a-z0-9_.]{3,20}$');
  static const Set<String> _reserved = {'admin', 'support', 'synk', 'official', 'moderator', 'help', 'root', 'system'};

  /// Returns an error message, or null when [raw] is a valid username.
  static String? username(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.length < 3) return 'At least 3 characters';
    if (value.length > 20) return 'Max 20 characters';
    if (!_username.hasMatch(value)) return 'Use letters, numbers, _ or .';
    if (value.startsWith('.') || value.endsWith('.')) return "Can't start or end with a dot";
    if (value.contains('..')) return 'No double dots';
    if (_reserved.contains(value)) return 'That name is reserved';
    return null;
  }

  static String? roomName(String raw) {
    final value = raw.trim();
    if (value.length < 2) return 'Give your room a name';
    if (value.length > 40) return 'Max 40 characters';
    return null;
  }

  static String? playlistName(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Name your playlist';
    if (value.length > 60) return 'Max 60 characters';
    return null;
  }
}
