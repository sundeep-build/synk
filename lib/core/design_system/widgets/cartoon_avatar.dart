import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Cute cartoon music characters for avatars: six pop, six jazz.
///
/// Drawn in code (no image assets): sharp at any size, free to ship, and a
/// few simple shapes each, so a list full of them paints quickly. Profiles
/// store one as `c:<index>` in the avatar field, where emoji avatars live.
class CartoonAvatar extends StatelessWidget {
  const CartoonAvatar({required this.index, required this.background, this.size = 40, super.key});

  final int index;
  final Color background;
  final double size;

  static const List<String> names = [
    'Pop Cat',
    'Jazz Fox',
    'DJ Panda',
    'Star Bunny',
    'Cool Bear',
    'Sax Owl',
    'Disco Frog',
    'Fedora Pup',
    'Penguin Crooner',
    'Beanie Koala',
    'Party Chick',
    'Blues Monkey',
  ];

  static int get count => names.length;

  /// The value stored for character [index].
  static String code(int index) => 'c:$index';

  /// The character an avatar value refers to, or null for an emoji avatar.
  static int? indexOf(String value) {
    if (!value.startsWith('c:')) return null;
    final i = int.tryParse(value.substring(2));
    return i != null && i >= 0 && i < count ? i : null;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: names[index % count],
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _CartoonPainter(index % count, background)),
    ),
  );
}

// Shared palette.
const _ink = Color(0xFF231B38);
const _white = Color(0xFFFFFFFF);
const _blush = Color(0x99FF7FB0);
const _pink = SynkPalette.pink;
const _violet = SynkPalette.brand;
const _cyan = SynkPalette.cyan;
const _gold = Color(0xFFFFC94A);

class _CartoonPainter extends CustomPainter {
  _CartoonPainter(this.index, this.background);

  final int index;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas
      ..save()
      ..scale(s)
      ..clipPath(Path()..addOval(const Rect.fromLTWH(0, 0, 100, 100)));
    canvas
      ..drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = background)
      // A soft spotlight behind the character.
      ..drawCircle(const Offset(50, 54), 40, Paint()..color = _white.withValues(alpha: 0.1));
    switch (index) {
      case 0:
        _cat(canvas);
      case 1:
        _fox(canvas);
      case 2:
        _panda(canvas);
      case 3:
        _bunny(canvas);
      case 4:
        _bear(canvas);
      case 5:
        _owl(canvas);
      case 6:
        _frog(canvas);
      case 7:
        _pup(canvas);
      case 8:
        _penguin(canvas);
      case 9:
        _koala(canvas);
      case 10:
        _chick(canvas);
      default:
        _monkey(canvas);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CartoonPainter old) => old.index != index || old.background != background;

  // ── Characters ───────────────────────────────────────────────────────────
  void _cat(Canvas c) {
    const fur = Color(0xFFFFB453);
    _body(c, fur);
    _tri(c, const Offset(24, 46), const Offset(29, 17), const Offset(46, 34), fur);
    _tri(c, const Offset(76, 46), const Offset(71, 17), const Offset(54, 34), fur);
    _tri(c, const Offset(29, 40), const Offset(31, 24), const Offset(41, 34), const Color(0xFFFF9BB8));
    _tri(c, const Offset(71, 40), const Offset(69, 24), const Offset(59, 34), const Color(0xFFFF9BB8));
    _oval(c, 50, 58, 28, 24, fur);
    _oval(c, 50, 67, 10, 7, const Color(0xFFFFF1DC));
    _eyes(c, y: 56, gap: 10.5);
    _cheeks(c, y: 65, gap: 17);
    _tri(c, const Offset(47.5, 63.5), const Offset(52.5, 63.5), const Offset(50, 66.5), const Color(0xFFFF6F91));
    _catMouth(c, 50, 67.5);
    for (final dy in [-1.5, 2.5]) {
      _line(c, Offset(33, 65 + dy), Offset(22, 63 + dy * 1.8), _ink.withValues(alpha: 0.5), 1);
      _line(c, Offset(67, 65 + dy), Offset(78, 63 + dy * 1.8), _ink.withValues(alpha: 0.5), 1);
    }
    _headphones(c, band: _violet, cup: _pink);
  }

  void _fox(Canvas c) {
    const fur = Color(0xFFF2843F);
    const cream = Color(0xFFFFF1E0);
    _body(c, fur);
    _tri(c, const Offset(21, 48), const Offset(26, 15), const Offset(46, 33), fur);
    _tri(c, const Offset(79, 48), const Offset(74, 15), const Offset(54, 33), fur);
    _tri(c, const Offset(26, 42), const Offset(28, 22), const Offset(40, 33), const Color(0xFF7A3B1E));
    _tri(c, const Offset(74, 42), const Offset(72, 22), const Offset(60, 33), const Color(0xFF7A3B1E));
    _oval(c, 50, 58, 29, 24, fur);
    _oval(c, 37, 68, 13, 10, cream);
    _oval(c, 63, 68, 13, 10, cream);
    _oval(c, 50, 72, 9, 6, cream);
    _eyes(c, y: 57, gap: 10);
    _cheeks(c, y: 65, gap: 18);
    _oval(c, 50, 66, 3.6, 2.6, _ink);
    _smile(c, 50, 69, 4);
    // Black beret, worn at a jaunty angle.
    c
      ..save()
      ..translate(54, 32)
      ..rotate(-0.22);
    _oval(c, 0, 0, 22, 8, const Color(0xFF221C33));
    _oval(c, 0, -2.5, 18, 5.5, const Color(0xFF2E2745));
    _oval(c, 2, -8.5, 2.2, 2.6, const Color(0xFF221C33));
    c.restore();
  }

  void _panda(Canvas c) {
    const white = Color(0xFFFAFAFD);
    const black = Color(0xFF26222F);
    _body(c, black);
    _oval(c, 28, 36, 9.5, 9.5, black);
    _oval(c, 72, 36, 9.5, 9.5, black);
    _oval(c, 50, 58, 28, 25, white);
    for (final side in [-1, 1]) {
      c
        ..save()
        ..translate(50 + side * 11.5, 58)
        ..rotate(side * -0.45);
      _oval(c, 0, 0, 7.5, 9.5, black);
      c.restore();
      _oval(c, 50 + side * 11, 57, 3.2, 3.6, _white);
      _oval(c, 50 + side * 11, 57.5, 2, 2.4, _ink);
    }
    _oval(c, 50, 67, 3.6, 2.5, black);
    _smile(c, 50, 70, 3.5);
    _cheeks(c, y: 67, gap: 19);
    _headphones(c, band: _cyan, cup: _cyan, inner: const Color(0xFF1B8FB5));
  }

  void _bunny(Canvas c) {
    const fur = Color(0xFFF3EEFF);
    const inner = Color(0xFFFFB3CE);
    _body(c, fur);
    for (final side in [-1, 1]) {
      c
        ..save()
        ..translate(50 + side * 12, 26)
        ..rotate(side * 0.18);
      _oval(c, 0, 0, 7.5, 19, fur);
      _oval(c, 0, 1, 4, 14, inner);
      c.restore();
    }
    _oval(c, 50, 60, 27, 24, fur);
    _cheeks(c, y: 67, gap: 16);
    _oval(c, 50, 64.5, 3, 2.2, const Color(0xFFFF6F91));
    _catMouth(c, 50, 66.5);
    c.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(47.5, 68, 5, 4.5), const Radius.circular(1.2)),
      Paint()..color = _white,
    );
    // Star shades.
    for (final side in [-1, 1]) {
      _star(c, Offset(50 + side * 10.5, 56), 9.5, _gold);
      _star(c, Offset(50 + side * 10.5, 56), 6.2, const Color(0xFFFF9F1C));
    }
    _line(c, const Offset(46, 55), const Offset(54, 55), _gold, 2);
  }

  void _bear(Canvas c) {
    const fur = Color(0xFFA8744F);
    const light = Color(0xFFE6BF96);
    _body(c, fur);
    _oval(c, 27, 36, 10.5, 10.5, fur);
    _oval(c, 73, 36, 10.5, 10.5, fur);
    _oval(c, 27, 36, 5.5, 5.5, light);
    _oval(c, 73, 36, 5.5, 5.5, light);
    _oval(c, 50, 59, 28, 25, fur);
    _oval(c, 50, 68, 11.5, 8.5, light);
    _oval(c, 50, 64.5, 4.2, 3.1, _ink);
    _smile(c, 50, 69, 4);
    _cheeks(c, y: 66, gap: 19);
    _roundShades(c, y: 55, lens: const Color(0xFF1F1A2E), frame: const Color(0xFF1F1A2E));
  }

  void _owl(Canvas c) {
    const feather = Color(0xFF9C7A5B);
    const disc = Color(0xFFF3E3C7);
    _body(c, feather);
    _tri(c, const Offset(24, 42), const Offset(24, 20), const Offset(38, 32), feather);
    _tri(c, const Offset(76, 42), const Offset(76, 20), const Offset(62, 32), feather);
    _oval(c, 50, 58, 29, 27, feather);
    _oval(c, 39.5, 56, 11.5, 11.5, disc);
    _oval(c, 60.5, 56, 11.5, 11.5, disc);
    for (final x in [39.5, 60.5]) {
      _oval(c, x, 56.5, 5.5, 5.8, _ink);
      _oval(c, x + 1.6, 54.6, 1.8, 1.8, _white);
    }
    // Gold spectacles.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _gold;
    c
      ..drawCircle(const Offset(39.5, 56), 9.8, rim)
      ..drawCircle(const Offset(60.5, 56), 9.8, rim);
    _line(c, const Offset(49, 55), const Offset(51, 55), _gold, 2);
    c.drawPath(
      Path()
        ..moveTo(50, 62)
        ..lineTo(46.5, 66)
        ..lineTo(50, 71)
        ..lineTo(53.5, 66)
        ..close(),
      Paint()..color = const Color(0xFFFF9F43),
    );
  }

  void _frog(Canvas c) {
    const skin = Color(0xFF68C77A);
    const belly = Color(0xFFD9F5C8);
    _body(c, skin);
    _oval(c, 34, 44, 11, 10.5, skin);
    _oval(c, 66, 44, 11, 10.5, skin);
    _oval(c, 50, 63, 31, 22, skin);
    _oval(c, 50, 72, 18, 9, belly);
    // Heart shades over the eye bumps.
    _heart(c, const Offset(34, 45), 11, _pink);
    _heart(c, const Offset(66, 45), 11, _pink);
    _oval(c, 30.5, 42, 2.4, 1.6, _white.withValues(alpha: 0.7));
    _oval(c, 62.5, 42, 2.4, 1.6, _white.withValues(alpha: 0.7));
    _line(c, const Offset(44, 46), const Offset(56, 46), _pink, 2);
    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = _ink;
    c.drawArc(const Rect.fromLTWH(37, 52, 26, 16), 0.35, math.pi - 0.7, false, mouth);
    _cheeks(c, y: 63, gap: 20);
  }

  void _pup(Canvas c) {
    const fur = Color(0xFFF1D5AE);
    const ear = Color(0xFF9E6B45);
    _body(c, fur);
    for (final side in [-1, 1]) {
      c
        ..save()
        ..translate(50 + side * 25, 58)
        ..rotate(side * -0.35);
      _oval(c, 0, 0, 8.5, 17, ear);
      c.restore();
    }
    _oval(c, 50, 60, 26, 24, fur);
    _oval(c, 60, 56, 7.5, 7, const Color(0xFFD9A774));
    _eyes(c, y: 56, gap: 10);
    _cheeks(c, y: 66, gap: 16);
    _oval(c, 50, 65, 5, 3.6, _ink);
    _oval(c, 50, 73, 3, 3.6, const Color(0xFFFF6F91));
    _smile(c, 50, 69, 4.5);
    // Fedora.
    _oval(c, 50, 37, 29, 5.5, const Color(0xFF2B2140));
    c.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(34, 19, 32, 18),
        topLeft: const Radius.circular(9),
        topRight: const Radius.circular(9),
      ),
      Paint()..color = const Color(0xFF2B2140),
    );
    c.drawRect(const Rect.fromLTWH(34, 30, 32, 4.5), Paint()..color = _violet);
    _oval(c, 50, 20.5, 7, 2.2, const Color(0xFF3A2F55));
  }

  void _penguin(Canvas c) {
    const dark = Color(0xFF2A2F48);
    const face = Color(0xFFF7F7FB);
    _body(c, dark, belly: face);
    _oval(c, 50, 57, 28, 26, dark);
    _oval(c, 41.5, 60, 12, 14, face);
    _oval(c, 58.5, 60, 12, 14, face);
    _oval(c, 50, 68, 15, 10, face);
    _eyes(c, y: 57, gap: 8.5);
    _cheeks(c, y: 66, gap: 15);
    _oval(c, 50, 65, 5, 3.2, const Color(0xFFFFA630));
    // Red bow tie.
    _tri(c, const Offset(50, 88), const Offset(38, 82), const Offset(38, 94), const Color(0xFFE5173F));
    _tri(c, const Offset(50, 88), const Offset(62, 82), const Offset(62, 94), const Color(0xFFE5173F));
    _oval(c, 50, 88, 3, 3, const Color(0xFFB80F31));
  }

  void _koala(Canvas c) {
    const fur = Color(0xFFA9AEC4);
    const fluff = Color(0xFFE7E9F2);
    _body(c, fur);
    _oval(c, 24, 48, 13, 13, fur);
    _oval(c, 76, 48, 13, 13, fur);
    _oval(c, 24, 48, 8, 8, fluff);
    _oval(c, 76, 48, 8, 8, fluff);
    _oval(c, 50, 61, 27, 24, fur);
    _eyes(c, y: 58, gap: 9.5, size: 0.85);
    _cheeks(c, y: 67, gap: 17);
    _oval(c, 50, 66, 6.5, 8, const Color(0xFF3A3550));
    // Knit beanie with a pompom.
    c.drawPath(
      Path()
        ..moveTo(25, 46)
        ..cubicTo(25, 22, 75, 22, 75, 46)
        ..close(),
      Paint()..color = _cyan,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(23, 40, 54, 8), const Radius.circular(4)),
      Paint()..color = const Color(0xFF1EA7D4),
    );
    _oval(c, 50, 23, 5.5, 5.5, _white);
  }

  void _chick(Canvas c) {
    const feather = Color(0xFFFFD54F);
    _body(c, feather);
    for (final (dx, angle) in [(-4.0, -0.5), (0.0, 0.0), (4.0, 0.5)]) {
      c
        ..save()
        ..translate(50 + dx, 34)
        ..rotate(angle);
      _oval(c, 0, -4, 2.8, 6, feather);
      c.restore();
    }
    _oval(c, 50, 60, 27, 26, feather);
    _eyes(c, y: 57, gap: 9.5);
    _cheeks(c, y: 65, gap: 16);
    _tri(c, const Offset(45, 63), const Offset(55, 63), const Offset(50, 69), const Color(0xFFFF9F43));
    // Striped party hat.
    c
      ..save()
      ..translate(62, 30)
      ..rotate(0.35);
    final hat = Path()
      ..moveTo(-9, 6)
      ..lineTo(9, 6)
      ..lineTo(0, -20)
      ..close();
    c
      ..drawPath(hat, Paint()..color = _pink)
      ..save()
      ..clipPath(hat);
    for (var y = -18.0; y < 8; y += 7) {
      c.drawRect(Rect.fromLTWH(-12, y, 24, 3), Paint()..color = _violet);
    }
    c.restore();
    _oval(c, 0, -20, 3, 3, _gold);
    c.restore();
  }

  void _monkey(Canvas c) {
    const fur = Color(0xFF8D5B3F);
    const face = Color(0xFFF0CFA8);
    _body(c, fur);
    _oval(c, 22, 58, 9.5, 9.5, fur);
    _oval(c, 78, 58, 9.5, 9.5, fur);
    _oval(c, 22, 58, 5.5, 5.5, face);
    _oval(c, 78, 58, 5.5, 5.5, face);
    _oval(c, 50, 57, 27, 26, fur);
    _oval(c, 42, 54, 10.5, 10, face);
    _oval(c, 58, 54, 10.5, 10, face);
    _oval(c, 50, 67, 16, 11.5, face);
    _oval(c, 47.5, 65, 1.3, 1.3, _ink);
    _oval(c, 52.5, 65, 1.3, 1.3, _ink);
    _smile(c, 50, 69.5, 5);
    _cheeks(c, y: 66, gap: 20);
    // Blue round shades.
    _roundShades(c, y: 54, lens: const Color(0xFF2F5BFF), frame: const Color(0xFF1B1ED2));
  }

  // ── Parts ────────────────────────────────────────────────────────────────
  /// Shoulders peeking in at the bottom.
  void _body(Canvas c, Color color, {Color? belly}) {
    _oval(c, 50, 102, 30, 20, color);
    if (belly != null) _oval(c, 50, 104, 18, 16, belly);
  }

  void _eyes(Canvas c, {required double y, required double gap, double size = 1}) {
    for (final side in [-1, 1]) {
      final x = 50 + side * gap;
      _oval(c, x, y, 3.6 * size, 4.4 * size, _ink);
      _oval(c, x + 1.1 * size, y - 1.5 * size, 1.3 * size, 1.3 * size, _white);
    }
  }

  void _cheeks(Canvas c, {required double y, required double gap}) {
    _oval(c, 50 - gap, y, 4.5, 2.8, _blush);
    _oval(c, 50 + gap, y, 4.5, 2.8, _blush);
  }

  void _smile(Canvas c, double x, double y, double w) => c.drawArc(
    Rect.fromCenter(center: Offset(x, y - w / 2), width: w * 2, height: w * 1.4),
    0.2,
    math.pi - 0.4,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = _ink,
  );

  /// The little "w" mouth.
  void _catMouth(Canvas c, double x, double y) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = _ink;
    c
      ..drawArc(Rect.fromCenter(center: Offset(x - 2.2, y), width: 4.4, height: 4), 0, math.pi, false, p)
      ..drawArc(Rect.fromCenter(center: Offset(x + 2.2, y), width: 4.4, height: 4), 0, math.pi, false, p);
  }

  void _headphones(Canvas c, {required Color band, required Color cup, Color? inner}) {
    c.drawArc(
      const Rect.fromLTWH(22, 26, 56, 56),
      math.pi * 1.02,
      math.pi * 0.96,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = band,
    );
    for (final x in [17.0, 73.0]) {
      c
        ..drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, 47, 10, 20), const Radius.circular(5)),
          Paint()..color = cup,
        )
        ..drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + (x < 50 ? 6 : 0), 50, 4, 14), const Radius.circular(2)),
          Paint()..color = inner ?? _ink.withValues(alpha: 0.35),
        );
    }
  }

  void _roundShades(Canvas c, {required double y, required Color lens, required Color frame}) {
    for (final side in [-1, 1]) {
      final center = Offset(50 + side * 10.5, y);
      c
        ..drawCircle(center, 8.5, Paint()..color = lens)
        ..drawCircle(
          center,
          8.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = frame,
        )
        ..drawArc(
          Rect.fromCircle(center: center, radius: 5.5),
          math.pi * 1.1,
          math.pi * 0.45,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = _white.withValues(alpha: 0.7),
        );
    }
    _line(c, Offset(48, y - 1), Offset(52, y - 1), frame, 2);
  }

  void _star(Canvas c, Offset center, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = center + Offset(math.cos(a) * radius, math.sin(a) * radius);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    c.drawPath(path..close(), Paint()..color = color);
  }

  void _heart(Canvas c, Offset center, double r, Color color) {
    final x = center.dx;
    final y = center.dy;
    c.drawPath(
      Path()
        ..moveTo(x, y + r * 0.85)
        ..cubicTo(x - r * 1.3, y, x - r * 0.75, y - r * 0.95, x, y - r * 0.35)
        ..cubicTo(x + r * 0.75, y - r * 0.95, x + r * 1.3, y, x, y + r * 0.85)
        ..close(),
      Paint()..color = color,
    );
  }

  void _oval(Canvas c, double x, double y, double rx, double ry, Color color) =>
      c.drawOval(Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2), Paint()..color = color);

  void _tri(Canvas c, Offset a, Offset b, Offset d, Color color) => c.drawPath(
    Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(d.dx, d.dy)
      ..close(),
    Paint()..color = color,
  );

  void _line(Canvas c, Offset a, Offset b, Color color, double width) => c.drawLine(
    a,
    b,
    Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round,
  );
}
