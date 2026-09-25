import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:synk/core/network/ttl_cache.dart';
import 'package:synk/core/utils/formatters.dart';
import 'package:synk/core/utils/room_code.dart';
import 'package:synk/core/utils/validators.dart';

void main() {
  group('RoomCode', () {
    test('generates valid, unambiguous codes', () {
      final r = Random(7);
      for (var i = 0; i < 500; i++) {
        final code = RoomCode.generate(r);
        expect(RoomCode.isValid(code), isTrue, reason: code);
        expect(code, isNot(matches(RegExp('[01ILO]'))));
      }
    });

    test('normalises pasted input', () {
      expect(RoomCode.normalize(' abc-234 '), 'ABC234');
      expect(RoomCode.isValid(RoomCode.normalize('abc 234')), isTrue);
      expect(RoomCode.isValid('ABC12'), isFalse);
      expect(RoomCode.isValid('ABCD0O'), isFalse);
    });
  });

  group('Validators.username', () {
    test('accepts good names', () {
      for (final n in ['maya', 'dj_sandy', 'a.b.c', 'user123']) {
        expect(Validators.username(n), isNull, reason: n);
      }
    });

    test('rejects bad names with a helpful reason', () {
      expect(Validators.username('ab'), contains('3'));
      expect(Validators.username('has space'), isNotNull);
      expect(Validators.username('.dot'), isNotNull);
      expect(Validators.username('a..b'), isNotNull);
      expect(Validators.username('admin'), contains('reserved'));
      expect(Validators.username('x' * 21), isNotNull);
    });
  });

  group('Formatters', () {
    test('duration', () {
      expect(Formatters.duration(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(Formatters.duration(const Duration(hours: 1, minutes: 2, seconds: 45)), '1:02:45');
    });

    test('compact numbers', () {
      expect(Formatters.compact(999), '999');
      expect(Formatters.compact(1200), '1.2K');
      expect(Formatters.compact(15000), '15K');
      expect(Formatters.compact(3400000), '3.4M');
    });
  });

  group('TtlCache', () {
    test('evicts least-recently-used beyond capacity', () {
      final c = TtlCache<String, int>(maxEntries: 2)
        ..put('a', 1)
        ..put('b', 2);
      expect(c.get('a'), 1); // touch a → b is now LRU
      c.put('c', 3);
      expect(c.get('b'), isNull);
      expect(c.get('a'), 1);
      expect(c.get('c'), 3);
    });

    test('expires entries', () async {
      final c = TtlCache<String, int>(ttl: const Duration(milliseconds: 10))..put('a', 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.get('a'), isNull);
    });

    test('getOrLoad loads once', () async {
      final c = TtlCache<String, int>();
      var calls = 0;
      Future<int> load() async => ++calls;
      await c.getOrLoad('k', load);
      await c.getOrLoad('k', load);
      expect(calls, 1);
    });
  });
}
