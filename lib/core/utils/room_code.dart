import 'dart:math';

/// Human-friendly room codes: 6 chars, no look-alikes (0/O, 1/I/L).
/// 31^6 ≈ 887M combinations; collisions are also guarded server-side.
abstract final class RoomCode {
  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int length = 6;
  static final RegExp _valid = RegExp('^[$alphabet]{$length}\$');

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return String.fromCharCodes(List.generate(length, (_) => alphabet.codeUnitAt(r.nextInt(alphabet.length))));
  }

  /// Normalises pasted/typed input: uppercases and strips spaces and dashes,
  /// so "abc-234" and " ABC 234 " both resolve to "ABC234".
  static String normalize(String input) => input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  static bool isValid(String code) => _valid.hasMatch(code);
}
