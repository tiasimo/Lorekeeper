import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/library_store.dart';

/// Feste con le loro decorazioni sugli scaffali.
const seasons = {
  'compleanno': 'Il tuo compleanno',
  'anniversario': 'Anniversario di Lorekeeper',
  'natale': 'Natale (1–26 dicembre)',
  'capodanno': 'Capodanno (27 dicembre – 5 gennaio)',
  'epifania': 'Epifania (6 gennaio)',
  'sanvalentino': 'San Valentino (10–15 febbraio)',
  'carnevale': 'Carnevale (giovedì grasso – martedì grasso)',
  'pasqua': 'Pasqua (dal giovedì santo a Pasquetta)',
  'repubblica': 'Festa della Repubblica (2 giugno)',
  'halloween': 'Halloween (24 ottobre – 1 novembre)',
  'primavera': 'Primavera',
  'estate': 'Estate',
  'autunno': 'Autunno',
  'inverno': 'Inverno',
  'saga': 'Compleanno della saga (il giorno in cui l\'hai aggiunta)',
};

DateTime _easter(int y) {
  final a = y % 19, b = y ~/ 100, c = y % 100, d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30, i = c ~/ 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31, day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(y, month, day);
}

/// La decorazione di oggi: prima le feste, altrimenti la stagione.
String currentSeason([DateTime? now]) {
  final d = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  bool between(DateTime a, DateTime b) => !day.isBefore(a) && !day.isAfter(b);
  String two(int n) => n.toString().padLeft(2, '0');
  final app = LibraryStore.I.app;
  // compleanno salvato come "AAAA-MM-GG" (o "MM-GG" nelle versioni precedenti)
  final bd = app.birthday;
  if (bd != null && bd.endsWith('${two(d.month)}-${two(d.day)}')) return 'compleanno';
  final inst = DateTime.tryParse(app.installedOn ?? '');
  if (inst != null && inst.year < d.year && inst.month == d.month && inst.day == d.day) return 'anniversario';
  if (d.month == 12 && d.day <= 26) return 'natale';
  if ((d.month == 12 && d.day >= 27) || (d.month == 1 && d.day <= 5)) return 'capodanno';
  if (d.month == 1 && d.day == 6) return 'epifania';
  if (d.month == 2 && d.day >= 10 && d.day <= 15) return 'sanvalentino';
  final easter = _easter(d.year);
  if (between(easter.subtract(const Duration(days: 52)), easter.subtract(const Duration(days: 47)))) return 'carnevale';
  if (between(easter.subtract(const Duration(days: 3)), easter.add(const Duration(days: 1)))) return 'pasqua';
  if (d.month == 6 && d.day == 2) return 'repubblica';
  if ((d.month == 10 && d.day >= 24) || (d.month == 11 && d.day == 1)) return 'halloween';
  final md = d.month * 100 + d.day;
  if (md >= 321 && md < 621) return 'primavera';
  if (md >= 621 && md < 923) return 'estate';
  if (md >= 923 && md < 1221) return 'autunno';
  return 'inverno';
}

/// Anni che compi oggi (se hai indicato l'anno di nascita).
int? birthdayAge() {
  final b = LibraryStore.I.app.birthday;
  if (b == null || b.length < 10) return null;
  final y = int.tryParse(b.substring(0, 4));
  return y == null ? null : DateTime.now().year - y;
}

/// Anni da quando è stato installato Lorekeeper.
int lorekeeperYears() {
  final inst = DateTime.tryParse(LibraryStore.I.app.installedOn ?? '');
  return inst == null ? 1 : DateTime.now().year - inst.year;
}

/// Decorazioni disegnate sopra uno scaffale: [boardTop] è dove inizia il ripiano.
class SeasonalDecor extends StatelessWidget {
  final String season;
  final double boardTop;
  final int seed;
  final bool sagaBirthday; // in più: torta della saga
  const SeasonalDecor({super.key, required this.season, required this.boardTop, this.seed = 0, this.sagaBirthday = false});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _DecorPainter(season, boardTop, seed))),
          if (sagaBirthday) Positioned.fill(child: CustomPaint(painter: _DecorPainter('saga', boardTop, seed))),
        ]),
      );
}

class _DecorPainter extends CustomPainter {
  final String season;
  final double boardTop;
  final int seed;
  _DecorPainter(this.season, this.boardTop, this.seed);

  void _garland(Canvas c, Size s, Color rope, List<Color> bulbs, {double sag = 26, bool hearts = false}) {
    final left = const Offset(8, 10), right = Offset(s.width - 8, 10);
    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..quadraticBezierTo(s.width / 2, left.dy + sag * 2, right.dx, right.dy);
    c.drawPath(
        path,
        Paint()
          ..color = rope
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final m = path.computeMetrics().first;
    final n = (m.length / 26).floor();
    for (var i = 1; i < n; i++) {
      final t = m.getTangentForOffset(m.length * i / n)!.position;
      final col = bulbs[i % bulbs.length];
      if (hearts) {
        _heart(c, t + const Offset(0, 8), 7, col);
      } else {
        c.drawCircle(t + const Offset(0, 7), 7, Paint()..color = col.withValues(alpha: 0.25));
        c.drawOval(Rect.fromCenter(center: t + const Offset(0, 7), width: 7, height: 10), Paint()..color = col);
        c.drawRect(Rect.fromCenter(center: t + const Offset(0, 1.5), width: 4, height: 3), Paint()..color = const Color(0xFF3A3A3A));
      }
    }
  }

  void _heart(Canvas c, Offset o, double r, Color col) {
    final p = Path()
      ..moveTo(o.dx, o.dy + r * 0.9)
      ..cubicTo(o.dx - r * 1.6, o.dy - r * 0.2, o.dx - r * 0.6, o.dy - r * 1.3, o.dx, o.dy - r * 0.4)
      ..cubicTo(o.dx + r * 0.6, o.dy - r * 1.3, o.dx + r * 1.6, o.dy - r * 0.2, o.dx, o.dy + r * 0.9);
    c.drawPath(p, Paint()..color = col);
  }

  void _confetti(Canvas c, Size s, math.Random r, List<Color> cols, int n) {
    for (var i = 0; i < n; i++) {
      final p = Paint()..color = cols[i % cols.length].withValues(alpha: 0.85);
      final o = Offset(14 + r.nextDouble() * (s.width - 28), 6 + r.nextDouble() * (boardTop * 0.35));
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(r.nextDouble() * math.pi);
      c.drawRect(const Rect.fromLTWH(-2.5, -1.2, 5, 2.4), p);
      c.restore();
    }
  }

  void _cake(Canvas c, Offset base, {int candles = 1, Color cream = const Color(0xFFFFF3E0), Color body = const Color(0xFFF48FB1)}) {
    final w = 30.0;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(base.dx - w / 2, base.dy - 16, w, 16), const Radius.circular(3)), Paint()..color = body);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(base.dx - w / 2, base.dy - 19, w, 6), const Radius.circular(3)), Paint()..color = cream);
    for (var i = 0; i < candles; i++) {
      final x = base.dx - (candles - 1) * 4 + i * 8;
      c.drawRect(Rect.fromLTWH(x - 1.2, base.dy - 28, 2.4, 9), Paint()..color = const Color(0xFF64B5F6));
      c.drawOval(Rect.fromCenter(center: Offset(x, base.dy - 31), width: 4, height: 6), Paint()..color = const Color(0xFFFFB300));
    }
  }

  void _balloon(Canvas c, Offset top, Color col) {
    c.drawLine(top + const Offset(0, 12), top + const Offset(-2, 46), Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 0.8);
    c.drawOval(Rect.fromCenter(center: top, width: 18, height: 23), Paint()..color = col);
    c.drawCircle(top + const Offset(-4, -5), 2.5, Paint()..color = Colors.white.withValues(alpha: 0.6));
  }

  void _bunting(Canvas c, Size s, List<Color> cols) {
    final path = Path()
      ..moveTo(8, 10)
      ..quadraticBezierTo(s.width / 2, 34, s.width - 8, 10);
    c.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF8D6E63)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4);
    final m = path.computeMetrics().first;
    final n = (m.length / 22).floor();
    for (var i = 0; i < n; i++) {
      final t = m.getTangentForOffset(m.length * (i + 0.5) / n)!.position;
      c.drawPath(
          Path()
            ..moveTo(t.dx - 7, t.dy)
            ..lineTo(t.dx + 7, t.dy)
            ..lineTo(t.dx, t.dy + 14)
            ..close(),
          Paint()..color = cols[i % cols.length]);
    }
  }

  void _leaf(Canvas c, Offset o, double a, Color col, double size) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(a);
    c.drawPath(
        Path()
          ..moveTo(0, -size)
          ..quadraticBezierTo(size * 0.8, 0, 0, size)
          ..quadraticBezierTo(-size * 0.8, 0, 0, -size),
        Paint()..color = col);
    c.drawLine(Offset(0, -size), Offset(0, size * 1.3), Paint()
      ..color = col.withValues(alpha: 0.8)
      ..strokeWidth = 1);
    c.restore();
  }

  void _flower(Canvas c, Offset o, Color petal) {
    for (var i = 0; i < 5; i++) {
      final a = i * 2 * math.pi / 5;
      c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * 4, 3.4, Paint()..color = petal);
    }
    c.drawCircle(o, 2.4, Paint()..color = const Color(0xFFFFD54F));
  }

  void _flake(Canvas c, Offset o, double r) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.1;
    for (var i = 0; i < 3; i++) {
      final a = i * math.pi / 3;
      c.drawLine(o - Offset(math.cos(a), math.sin(a)) * r, o + Offset(math.cos(a), math.sin(a)) * r, p);
    }
  }

  // ---------------- elementi in più ----------------

  void _tree(Canvas c, Offset base, double h) {
    c.drawRect(Rect.fromCenter(center: base + Offset(0, -h * 0.08), width: h * 0.14, height: h * 0.16), Paint()..color = const Color(0xFF5D4037));
    const greens = [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF388E3C)];
    for (var i = 0; i < 3; i++) {
      final w = h * (0.7 - i * 0.17), top = base.dy - h * (0.42 + i * 0.22), bottom = base.dy - h * (0.14 + i * 0.22);
      c.drawPath(
          Path()
            ..moveTo(base.dx - w / 2, bottom)
            ..lineTo(base.dx, top)
            ..lineTo(base.dx + w / 2, bottom)
            ..close(),
          Paint()..color = greens[i]);
    }
    const lights = [Color(0xFFFFEB3B), Color(0xFFE53935), Color(0xFF42A5F5)];
    for (var i = 0; i < 7; i++) {
      final y = base.dy - h * (0.2 + (i % 4) * 0.15), x = base.dx + ((i * 37) % 9 - 4) * h * 0.035;
      c.drawCircle(Offset(x, y), 1.8, Paint()..color = lights[i % 3]);
    }
    _star(c, Offset(base.dx, base.dy - h * 0.86), 5, const Color(0xFFFFD54F));
  }

  void _star(Canvas c, Offset o, double r, Color col) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = o + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    c.drawPath(p..close(), Paint()..color = col);
  }

  void _gift(Canvas c, Offset base, double w, Color box, Color ribbon) {
    final rect = Rect.fromLTWH(base.dx - w / 2, base.dy - w * 0.8, w, w * 0.8);
    c.drawRect(rect, Paint()..color = box);
    c.drawRect(Rect.fromCenter(center: rect.center, width: w * 0.16, height: rect.height), Paint()..color = ribbon);
    c.drawRect(Rect.fromCenter(center: rect.center, width: w, height: w * 0.12), Paint()..color = ribbon);
    final bow = Paint()..color = ribbon;
    c.drawOval(Rect.fromCenter(center: Offset(base.dx - w * 0.13, rect.top - w * 0.08), width: w * 0.28, height: w * 0.18), bow);
    c.drawOval(Rect.fromCenter(center: Offset(base.dx + w * 0.13, rect.top - w * 0.08), width: w * 0.28, height: w * 0.18), bow);
  }

  void _hangingBall(Canvas c, Offset top, double len, Color col) {
    c.drawLine(top, top + Offset(0, len), Paint()
      ..color = const Color(0xFFB0905A)
      ..strokeWidth = 0.9);
    final o = top + Offset(0, len + 7);
    c.drawCircle(o, 7, Paint()..color = col);
    c.drawRect(Rect.fromCenter(center: o + const Offset(0, -7), width: 4, height: 3), Paint()..color = const Color(0xFFE2B84B));
    c.drawCircle(o + const Offset(-2.5, -2.5), 1.8, Paint()..color = Colors.white.withValues(alpha: 0.7));
  }

  void _candyCane(Canvas c, Offset base) {
    final p = Path()
      ..moveTo(base.dx, base.dy)
      ..lineTo(base.dx, base.dy - 22)
      ..arcToPoint(Offset(base.dx + 9, base.dy - 22), radius: const Radius.circular(4.5));
    c.drawPath(p, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round);
    for (double y = base.dy - 2; y > base.dy - 22; y -= 5) {
      c.drawLine(Offset(base.dx - 1.7, y), Offset(base.dx + 1.7, y - 2), Paint()
        ..color = const Color(0xFFE53935)
        ..strokeWidth = 1.6);
    }
  }

  void _icicles(Canvas c, Size s, math.Random r) {
    final p = Paint()..color = const Color(0xFFE3F2FD).withValues(alpha: 0.9);
    for (double x = 10; x < s.width - 10; x += 9 + r.nextDouble() * 6) {
      final h = 6 + r.nextDouble() * 14;
      c.drawPath(
          Path()
            ..moveTo(x - 3, 0)
            ..lineTo(x + 3, 0)
            ..lineTo(x, h)
            ..close(),
          p);
    }
  }

  void _snowman(Canvas c, Offset base) {
    final w = Paint()..color = Colors.white;
    c.drawCircle(base + const Offset(0, -9), 9, w);
    c.drawCircle(base + const Offset(0, -23), 6.5, w);
    c.drawRect(Rect.fromCenter(center: base + const Offset(0, -16.5), width: 15, height: 3), Paint()..color = const Color(0xFFC62828));
    c.drawRect(Rect.fromCenter(center: base + const Offset(0, -31), width: 10, height: 6), Paint()..color = const Color(0xFF263238));
    c.drawRect(Rect.fromCenter(center: base + const Offset(0, -28), width: 15, height: 1.6), Paint()..color = const Color(0xFF263238));
    final eye = Paint()..color = const Color(0xFF263238);
    c.drawCircle(base + const Offset(-2.2, -24.5), 1, eye);
    c.drawCircle(base + const Offset(2.2, -24.5), 1, eye);
    c.drawPath(
        Path()
          ..moveTo(base.dx, base.dy - 23)
          ..lineTo(base.dx + 6, base.dy - 22)
          ..lineTo(base.dx, base.dy - 21.5)
          ..close(),
        Paint()..color = const Color(0xFFFF7043));
  }

  void _pumpkin(Canvas c, Offset pc, double w) {
    c.drawOval(Rect.fromCenter(center: pc, width: w, height: w * 0.72), Paint()..color = const Color(0xFFEF6C00));
    c.drawOval(Rect.fromCenter(center: pc, width: w * 0.48, height: w * 0.72), Paint()..color = const Color(0xFFF57C00));
    c.drawRect(Rect.fromCenter(center: pc + Offset(0, -w * 0.42), width: w * 0.13, height: w * 0.2), Paint()..color = const Color(0xFF4E342E));
    final face = Paint()..color = const Color(0xFF3E2723);
    for (final sx in [-1.0, 1.0]) {
      c.drawPath(
          Path()
            ..moveTo(pc.dx + sx * w * 0.26, pc.dy - w * 0.08)
            ..lineTo(pc.dx + sx * w * 0.13, pc.dy - w * 0.22)
            ..lineTo(pc.dx + sx * w * 0.06, pc.dy - w * 0.08)
            ..close(),
          face);
    }
    c.drawArc(Rect.fromCenter(center: pc + Offset(0, w * 0.06), width: w * 0.46, height: w * 0.26), 0.2, math.pi - 0.4, false, Paint()
      ..color = const Color(0xFF3E2723)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  void _web(Canvas c, Offset o, double size, bool flip) {
    final web = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final base = flip ? math.pi / 2 : 0.0;
    for (var i = 0; i <= 4; i++) {
      final a = base + i * math.pi / 8;
      c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * size, web);
    }
    for (var k = 1; k <= 4; k++) {
      final p = Path();
      for (var i = 0; i <= 4; i++) {
        final a = base + i * math.pi / 8;
        final pt = o + Offset(math.cos(a), math.sin(a)) * (k * size / 4.2);
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      c.drawPath(p, web);
    }
  }

  void _spider(Canvas c, Offset top, double len) {
    c.drawLine(top, top + Offset(0, len), Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 0.7);
    final o = top + Offset(0, len + 4);
    final leg = Paint()
      ..color = const Color(0xFF212121)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final dy = -3 + i * 2.0;
      c.drawPath(Path()..moveTo(o.dx, o.dy)..quadraticBezierTo(o.dx - 6, o.dy + dy - 3, o.dx - 9, o.dy + dy + 2), leg);
      c.drawPath(Path()..moveTo(o.dx, o.dy)..quadraticBezierTo(o.dx + 6, o.dy + dy - 3, o.dx + 9, o.dy + dy + 2), leg);
    }
    c.drawOval(Rect.fromCenter(center: o, width: 7, height: 8), Paint()..color = const Color(0xFF212121));
  }

  void _ghost(Canvas c, Offset o) {
    final p = Path()
      ..moveTo(o.dx - 9, o.dy + 10)
      ..lineTo(o.dx - 9, o.dy - 2)
      ..arcToPoint(Offset(o.dx + 9, o.dy - 2), radius: const Radius.circular(9))
      ..lineTo(o.dx + 9, o.dy + 10)
      ..lineTo(o.dx + 5, o.dy + 7)
      ..lineTo(o.dx + 1.5, o.dy + 10)
      ..lineTo(o.dx - 2, o.dy + 7)
      ..lineTo(o.dx - 5.5, o.dy + 10)
      ..close();
    c.drawPath(p, Paint()..color = Colors.white.withValues(alpha: 0.85));
    c.drawCircle(o + const Offset(-3, -2), 1.4, Paint()..color = const Color(0xFF212121));
    c.drawCircle(o + const Offset(3, -2), 1.4, Paint()..color = const Color(0xFF212121));
  }

  void _bat(Canvas c, Offset b, double k) {
    c.drawPath(
        Path()
          ..moveTo(b.dx, b.dy)
          ..quadraticBezierTo(b.dx - 6 * k, b.dy - 6 * k, b.dx - 12 * k, b.dy - k)
          ..quadraticBezierTo(b.dx - 7 * k, b.dy + k, b.dx, b.dy + 3 * k)
          ..quadraticBezierTo(b.dx + 7 * k, b.dy + k, b.dx + 12 * k, b.dy - k)
          ..quadraticBezierTo(b.dx + 6 * k, b.dy - 6 * k, b.dx, b.dy),
        Paint()..color = const Color(0xFF2B2B2B));
  }

  void _candle(Canvas c, Offset base, double h) {
    c.drawRect(Rect.fromLTWH(base.dx - 3, base.dy - h, 6, h), Paint()..color = const Color(0xFFF5F0E1));
    c.drawCircle(Offset(base.dx, base.dy - h - 5), 6, Paint()..color = const Color(0x55FFB300));
    c.drawOval(Rect.fromCenter(center: Offset(base.dx, base.dy - h - 4), width: 4, height: 7), Paint()..color = const Color(0xFFFFB300));
  }

  void _butterfly(Canvas c, Offset o, Color col) {
    final p = Paint()..color = col;
    c.drawOval(Rect.fromCenter(center: o + const Offset(-4, -2), width: 7, height: 8), p);
    c.drawOval(Rect.fromCenter(center: o + const Offset(4, -2), width: 7, height: 8), p);
    c.drawOval(Rect.fromCenter(center: o + const Offset(-3, 3), width: 5, height: 5), p);
    c.drawOval(Rect.fromCenter(center: o + const Offset(3, 3), width: 5, height: 5), p);
    c.drawLine(o + const Offset(0, -4), o + const Offset(0, 5), Paint()
      ..color = const Color(0xFF3E2723)
      ..strokeWidth = 1.2);
  }

  void _pot(Canvas c, Offset base, Color flower) {
    c.drawPath(
        Path()
          ..moveTo(base.dx - 8, base.dy - 12)
          ..lineTo(base.dx + 8, base.dy - 12)
          ..lineTo(base.dx + 6, base.dy)
          ..lineTo(base.dx - 6, base.dy)
          ..close(),
        Paint()..color = const Color(0xFFBF6F45));
    for (final dx in [-5.0, 0.0, 5.0]) {
      c.drawLine(Offset(base.dx + dx * 0.4, base.dy - 12), Offset(base.dx + dx, base.dy - 24), Paint()
        ..color = const Color(0xFF558B2F)
        ..strokeWidth = 1.2);
      _flower(c, Offset(base.dx + dx, base.dy - 26), flower);
    }
  }

  void _beachBall(Canvas c, Offset o, double r) {
    const cols = [Color(0xFFE53935), Colors.white, Color(0xFF1E88E5), Colors.white, Color(0xFFFFC107), Colors.white];
    for (var i = 0; i < 6; i++) {
      c.drawArc(Rect.fromCircle(center: o, radius: r), i * math.pi / 3, math.pi / 3, true, Paint()..color = cols[i]);
    }
  }

  void _shell(Canvas c, Offset o, Color col) {
    final p = Path()..moveTo(o.dx, o.dy);
    p.arcTo(Rect.fromCenter(center: o + const Offset(0, -4), width: 12, height: 10), math.pi, math.pi, false);
    p.close();
    c.drawPath(p, Paint()..color = col);
    for (var i = -2; i <= 2; i++) {
      c.drawLine(o, o + Offset(i * 2.5, -8), Paint()
        ..color = col.withValues(alpha: 0.5)
        ..strokeWidth = 0.6);
    }
  }

  void _mushroom(Canvas c, Offset base) {
    c.drawRect(Rect.fromLTWH(base.dx - 2.5, base.dy - 9, 5, 9), Paint()..color = const Color(0xFFF5E6CC));
    c.drawArc(Rect.fromCenter(center: base + const Offset(0, -9), width: 16, height: 12), math.pi, math.pi, true, Paint()..color = const Color(0xFFC62828));
    c.drawCircle(base + const Offset(-3, -12), 1.4, Paint()..color = Colors.white);
    c.drawCircle(base + const Offset(3, -11), 1.2, Paint()..color = Colors.white);
  }

  void _acorn(Canvas c, Offset o) {
    c.drawOval(Rect.fromCenter(center: o, width: 7, height: 9), Paint()..color = const Color(0xFFA1887F));
    c.drawArc(Rect.fromCenter(center: o + const Offset(0, -3), width: 9, height: 6), math.pi, math.pi, true, Paint()..color = const Color(0xFF5D4037));
  }

  void _bottle(Canvas c, Offset base) {
    final g = Paint()..color = const Color(0xFF1B5E20);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(base.dx - 5, base.dy - 22, 10, 22), const Radius.circular(3)), g);
    c.drawRect(Rect.fromLTWH(base.dx - 2, base.dy - 32, 4, 11), g);
    c.drawRect(Rect.fromLTWH(base.dx - 2.5, base.dy - 34, 5, 4), Paint()..color = const Color(0xFFE2B84B));
    c.drawRect(Rect.fromLTWH(base.dx - 5, base.dy - 16, 10, 7), Paint()..color = const Color(0xFFF6E3A8));
  }

  void _glass(Canvas c, Offset base) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    c.drawLine(base, base + const Offset(0, -8), p);
    c.drawLine(base + const Offset(-4, 0), base + const Offset(4, 0), p);
    c.drawPath(
        Path()
          ..moveTo(base.dx - 3, base.dy - 20)
          ..lineTo(base.dx + 3, base.dy - 20)
          ..lineTo(base.dx + 1.5, base.dy - 8)
          ..lineTo(base.dx - 1.5, base.dy - 8)
          ..close(),
        Paint()..color = const Color(0xFFFFE082).withValues(alpha: 0.85));
  }

  void _firework(Canvas c, Offset o, double r, Color col) {
    final p = Paint()
      ..color = col
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      c.drawLine(o + Offset(math.cos(a), math.sin(a)) * r * 0.35, o + Offset(math.cos(a), math.sin(a)) * r, p);
      c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * (r + 2.5), 1.2, p);
    }
  }

  void _rose(Canvas c, Offset base) {
    c.drawLine(base, base + const Offset(3, -22), Paint()
      ..color = const Color(0xFF2E7D32)
      ..strokeWidth = 1.6);
    _leaf(c, base + const Offset(1, -10), 0.9, const Color(0xFF43A047), 3.5);
    c.drawCircle(base + const Offset(3, -25), 5.5, Paint()..color = const Color(0xFFC2185B));
    c.drawArc(Rect.fromCircle(center: base + const Offset(3, -25), radius: 3), 0, math.pi * 1.5, false, Paint()
      ..color = const Color(0xFF880E4F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  void _bunny(Canvas c, Offset base) {
    final w = Paint()..color = const Color(0xFFF5F5F5);
    c.drawOval(Rect.fromCenter(center: base + const Offset(0, -8), width: 16, height: 14), w);
    c.drawOval(Rect.fromCenter(center: base + const Offset(5, -17), width: 10, height: 9), w);
    c.drawOval(Rect.fromCenter(center: base + const Offset(3, -25), width: 4, height: 11), w);
    c.drawOval(Rect.fromCenter(center: base + const Offset(7.5, -25), width: 4, height: 11), w);
    c.drawOval(Rect.fromCenter(center: base + const Offset(7.5, -25), width: 2, height: 7), Paint()..color = const Color(0xFFF8BBD0));
    c.drawCircle(base + const Offset(7, -18), 1, Paint()..color = const Color(0xFF212121));
    c.drawCircle(base + const Offset(-8, -6), 3, w);
  }

  void _chick(Canvas c, Offset base) {
    final y = Paint()..color = const Color(0xFFFFEB3B);
    c.drawCircle(base + const Offset(0, -6), 6, y);
    c.drawCircle(base + const Offset(3, -13), 4.5, y);
    c.drawCircle(base + const Offset(4.5, -14), 0.9, Paint()..color = const Color(0xFF212121));
    c.drawPath(
        Path()
          ..moveTo(base.dx + 7, base.dy - 13)
          ..lineTo(base.dx + 10, base.dy - 12)
          ..lineTo(base.dx + 7, base.dy - 11)
          ..close(),
        Paint()..color = const Color(0xFFFF9800));
  }

  void _hat(Canvas c, Offset base, Color col) {
    c.drawPath(
        Path()
          ..moveTo(base.dx - 7, base.dy)
          ..lineTo(base.dx, base.dy - 20)
          ..lineTo(base.dx + 7, base.dy)
          ..close(),
        Paint()..color = col);
    c.drawCircle(Offset(base.dx, base.dy - 20), 2.5, Paint()..color = const Color(0xFFFFEB3B));
    for (var i = 1; i < 3; i++) {
      c.drawCircle(Offset(base.dx + (i.isEven ? 2 : -2), base.dy - i * 6), 1.3, Paint()..color = Colors.white);
    }
  }

  void _rosette(Canvas c, Offset o, List<Color> cols) {
    for (var i = 0; i < cols.length; i++) {
      c.drawCircle(o, 11.0 - i * 3.5, Paint()..color = cols[i]);
    }
    c.drawPath(
        Path()
          ..moveTo(o.dx - 5, o.dy + 6)
          ..lineTo(o.dx - 8, o.dy + 22)
          ..lineTo(o.dx - 2, o.dy + 17)
          ..lineTo(o.dx, o.dy + 7)
          ..close(),
        Paint()..color = cols.first);
    c.drawPath(
        Path()
          ..moveTo(o.dx + 5, o.dy + 6)
          ..lineTo(o.dx + 8, o.dy + 22)
          ..lineTo(o.dx + 2, o.dy + 17)
          ..lineTo(o.dx, o.dy + 7)
          ..close(),
        Paint()..color = cols.last);
  }

  void _leafGarland(Canvas c, Size s, math.Random r, List<Color> cols) {
    final path = Path()
      ..moveTo(8, 8)
      ..quadraticBezierTo(s.width / 2, 40, s.width - 8, 8);
    c.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF6D4C41)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
    final m = path.computeMetrics().first;
    for (double t = 6; t < m.length; t += 9) {
      final pos = m.getTangentForOffset(t)!.position;
      _leaf(c, pos + Offset(0, r.nextBool() ? 4 : -2), r.nextDouble() * math.pi, cols[r.nextInt(cols.length)], 4 + r.nextDouble() * 2);
    }
  }

  @override
  void paint(Canvas c, Size s) {
    final r = math.Random(seed + season.hashCode);
    final right = s.width - 30.0;
    final b = boardTop;
    switch (season) {
      case 'compleanno':
        _bunting(c, s, const [Color(0xFFE91E63), Color(0xFFFFC107), Color(0xFF29B6F6), Color(0xFF66BB6A), Color(0xFFAB47BC)]);
        _confetti(c, s, r, const [Color(0xFFFFC107), Color(0xFFE91E63), Color(0xFF29B6F6), Color(0xFF66BB6A)], 45);
        _cake(c, Offset(right - 6, b), candles: 3);
        final age = birthdayAge();
        if (age != null) {
          final tp = TextPainter(
            text: TextSpan(text: '$age', style: const TextStyle(color: Color(0xFFC2185B), fontSize: 12, fontWeight: FontWeight.w800)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(c, Offset(right - 6 - tp.width / 2, b - 15));
        }
        _gift(c, Offset(right - 32, b), 16, const Color(0xFF42A5F5), const Color(0xFFFFEB3B));
        _gift(c, Offset(34, b), 18, const Color(0xFFAB47BC), const Color(0xFFFFFFFF));
        _hat(c, Offset(52, b), const Color(0xFFE91E63));
        for (final (dx, dy, col) in const [(-2.0, 56.0, Color(0xFFE53935)), (10.0, 66.0, Color(0xFF42A5F5)), (-12.0, 70.0, Color(0xFFFFC107)), (4.0, 80.0, Color(0xFF66BB6A))]) {
          _balloon(c, Offset(right + dx, dy), col);
        }
      case 'anniversario':
        _bunting(c, s, const [Color(0xFFE2B84B), Color(0xFF7A1E2E)]);
        for (var i = 0; i < 9; i++) {
          _star(c, Offset(20 + r.nextDouble() * (s.width - 40), 30 + r.nextDouble() * b * 0.25), 3 + r.nextDouble() * 3, const Color(0xFFE2B84B));
        }
        final o = Offset(right - 4, 48);
        _rosette(c, o, const [Color(0xFF7A1E2E), Color(0xFFE2B84B), Color(0xFFF6E3A8)]);
        final tp = TextPainter(
          text: TextSpan(text: '${lorekeeperYears()}', style: const TextStyle(color: Color(0xFF7A1E2E), fontSize: 11, fontWeight: FontWeight.w800)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
        _candle(c, Offset(36, b), 16);
        _candle(c, Offset(46, b), 22);
        _confetti(c, s, r, const [Color(0xFFE2B84B), Color(0xFF7A1E2E)], 24);
      case 'natale':
        _leafGarland(c, s, r, const [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF388E3C)]);
        _garland(c, s, Colors.transparent, const [Color(0xFFE53935), Color(0xFFFFC107), Color(0xFF43A047), Color(0xFF1E88E5)]);
        for (var i = 0; i < 14; i++) {
          _flake(c, Offset(14 + r.nextDouble() * (s.width - 28), 36 + r.nextDouble() * b * 0.3), 2 + r.nextDouble() * 2.5);
        }
        final snow = Paint()..color = Colors.white.withValues(alpha: 0.92);
        final path = Path()..moveTo(10, b + 2);
        for (double x = 10; x <= s.width - 10; x += 14) {
          path.quadraticBezierTo(x + 7, b - 4 - r.nextDouble() * 3, x + 14, b + 2);
        }
        path
          ..lineTo(s.width - 10, b + 5)
          ..lineTo(10, b + 5)
          ..close();
        c.drawPath(path, snow);
        _hangingBall(c, Offset(right + 14, 16), 40, const Color(0xFFC62828));
        _hangingBall(c, Offset(right + 4, 16), 58, const Color(0xFFE2B84B));
        _hangingBall(c, const Offset(16, 16), 48, Color(0xFF1E88E5));
        _tree(c, Offset(right - 6, b - 2), 46);
        _gift(c, Offset(right - 34, b - 1), 14, const Color(0xFFC62828), const Color(0xFFE2B84B));
        _gift(c, Offset(34, b - 1), 16, const Color(0xFF2E7D32), const Color(0xFFE53935));
        _candyCane(c, Offset(52, b - 1));
      case 'capodanno':
        final cols = [const Color(0xFFFFC107), const Color(0xFFE91E63), const Color(0xFF29B6F6), const Color(0xFF66BB6A), const Color(0xFFAB47BC)];
        for (var i = 0; i < 8; i++) {
          final x = 18 + i * (s.width - 36) / 7;
          final p = Path()..moveTo(x, 4);
          for (double y = 4; y < 60 + (i % 3) * 14; y += 10) {
            p.quadraticBezierTo((y ~/ 10).isEven ? x + 8 : x - 8, y + 5, x, y + 10);
          }
          c.drawPath(
              p,
              Paint()
                ..color = cols[i % cols.length]
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.2);
        }
        _firework(c, Offset(s.width * 0.3, 34), 16, const Color(0xFFFFD54F));
        _firework(c, Offset(s.width * 0.62, 26), 12, const Color(0xFFE91E63));
        _confetti(c, s, r, cols, 70);
        _bottle(c, Offset(right - 6, b));
        _glass(c, Offset(right - 22, b));
        _glass(c, Offset(right - 32, b));
        for (var i = 0; i < 5; i++) {
          _star(c, Offset(28.0 + i * 10, b - 4 - (i % 2) * 6), 3.5, cols[i]);
        }
      case 'epifania':
        for (var i = 0; i < 10; i++) {
          _star(c, Offset(20 + r.nextDouble() * (s.width - 40), 10 + r.nextDouble() * 40), 2.5 + r.nextDouble() * 2.5, const Color(0xFFFFE082));
        }
        final sx = right + 6;
        c.drawLine(Offset(sx, 12), Offset(sx, 30), Paint()..color = const Color(0xFF8D6E63));
        final sock = Path()
          ..moveTo(sx - 7, 30)
          ..lineTo(sx + 7, 30)
          ..lineTo(sx + 7, 52)
          ..quadraticBezierTo(sx + 7, 62, sx - 4, 62)
          ..lineTo(sx - 12, 62)
          ..quadraticBezierTo(sx - 18, 56, sx - 7, 52)
          ..close();
        c.drawPath(sock, Paint()..color = const Color(0xFFC62828));
        c.drawRect(Rect.fromLTWH(sx - 8, 29, 16, 6), Paint()..color = Colors.white);
        _candyCane(c, Offset(sx - 3, 32));
        // secondo calzino a sinistra
        final lx = 22.0;
        c.drawLine(Offset(lx, 12), Offset(lx, 26), Paint()..color = const Color(0xFF8D6E63));
        c.drawPath(
            Path()
              ..moveTo(lx - 6, 26)
              ..lineTo(lx + 6, 26)
              ..lineTo(lx + 6, 44)
              ..quadraticBezierTo(lx + 6, 52, lx + 14, 52)
              ..lineTo(lx + 14, 44)
              ..lineTo(lx - 6, 44)
              ..close(),
            Paint()..color = const Color(0xFF2E7D32));
        c.drawRect(Rect.fromLTWH(lx - 7, 25, 14, 5), Paint()..color = Colors.white);
        // scopa, caramelle e carbone sul ripiano
        c.drawLine(Offset(right - 54, b - 2), Offset(right - 14, b - 40), Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 2.5);
        c.drawPath(
            Path()
              ..moveTo(right - 60, b - 1)
              ..lineTo(right - 48, b - 18)
              ..lineTo(right - 38, b - 1)
              ..close(),
            Paint()..color = const Color(0xFFC8A15A));
        const candies = [Color(0xFFE91E63), Color(0xFF29B6F6), Color(0xFFFFC107), Color(0xFF66BB6A)];
        for (var i = 0; i < 4; i++) {
          final o = Offset(30.0 + i * 9, b - 4);
          c.drawOval(Rect.fromCenter(center: o, width: 7, height: 5), Paint()..color = candies[i]);
          c.drawPath(Path()..moveTo(o.dx - 3.5, o.dy)..lineTo(o.dx - 6, o.dy - 2.5)..lineTo(o.dx - 6, o.dy + 2.5)..close(), Paint()..color = candies[i]);
          c.drawPath(Path()..moveTo(o.dx + 3.5, o.dy)..lineTo(o.dx + 6, o.dy - 2.5)..lineTo(o.dx + 6, o.dy + 2.5)..close(), Paint()..color = candies[i]);
        }
        for (var i = 0; i < 3; i++) {
          c.drawOval(Rect.fromCenter(center: Offset(70.0 + i * 7, b - 3), width: 7, height: 5), Paint()..color = const Color(0xFF212121));
        }
      case 'sanvalentino':
        _garland(c, s, const Color(0xFFB0905A), const [Color(0xFFE53950), Color(0xFFF48FB1), Color(0xFFC2185B)], hearts: true, sag: 20);
        for (var i = 0; i < 10; i++) {
          _heart(c, Offset(20 + r.nextDouble() * (s.width - 40), 40 + r.nextDouble() * b * 0.3), 3 + r.nextDouble() * 3,
              [const Color(0xFFE53950), const Color(0xFFF48FB1), const Color(0xFFFFCDD2)][i % 3].withValues(alpha: 0.85));
        }
        _heart(c, Offset(right - 4, b - 12), 10, const Color(0xFFE53950));
        _rose(c, Offset(right - 26, b));
        _rose(c, Offset(right - 20, b));
        // busta con cuore
        final env = Rect.fromLTWH(26, b - 14, 24, 14);
        c.drawRect(env, Paint()..color = const Color(0xFFFFF3E0));
        c.drawPath(Path()..moveTo(env.left, env.top)..lineTo(env.center.dx, env.center.dy + 1)..lineTo(env.right, env.top), Paint()
          ..color = const Color(0xFFD7CCC8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
        _heart(c, Offset(env.center.dx, env.center.dy + 1), 3.5, const Color(0xFFC2185B));
      case 'carnevale':
        final cols = [const Color(0xFFFFC107), const Color(0xFFE91E63), const Color(0xFF29B6F6), const Color(0xFF66BB6A), const Color(0xFFAB47BC)];
        _bunting(c, s, cols);
        for (var i = 0; i < 6; i++) {
          final x = 24 + i * (s.width - 48) / 5;
          final p = Path()..moveTo(x, 18);
          for (double y = 18; y < 58; y += 8) {
            p.quadraticBezierTo((y ~/ 8).isEven ? x + 6 : x - 6, y + 4, x, y + 8);
          }
          c.drawPath(p, Paint()
            ..color = cols[(i + 2) % cols.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8);
        }
        _confetti(c, s, r, cols, 90);
        void mask(Offset o, Color col) {
          c.drawPath(
              Path()
                ..moveTo(o.dx - 14, o.dy)
                ..quadraticBezierTo(o.dx, o.dy - 9, o.dx + 14, o.dy)
                ..quadraticBezierTo(o.dx, o.dy + 14, o.dx - 14, o.dy),
              Paint()..color = col);
          c.drawOval(Rect.fromCenter(center: o + const Offset(-6, 0), width: 7, height: 4), Paint()..color = Colors.black);
          c.drawOval(Rect.fromCenter(center: o + const Offset(6, 0), width: 7, height: 4), Paint()..color = Colors.black);
          c.drawLine(o + const Offset(14, 0), o + const Offset(20, -14), Paint()
            ..color = const Color(0xFFE2B84B)
            ..strokeWidth = 1.5);
        }
        mask(Offset(right - 10, b - 14), const Color(0xFF7B1FA2));
        mask(Offset(40, b - 12), const Color(0xFFE2B84B));
        _balloon(c, Offset(right + 6, 58), const Color(0xFF29B6F6));
        _balloon(c, Offset(right - 6, 66), const Color(0xFFFFC107));
      case 'pasqua':
        _garland(c, s, const Color(0xFF8BC34A), const [Color(0xFFFFF59D), Color(0xFFF8BBD0), Color(0xFFB3E5FC), Color(0xFFE1BEE7)], sag: 16);
        for (var i = 0; i < 4; i++) {
          _butterfly(c, Offset(30 + r.nextDouble() * (s.width - 60), 40 + r.nextDouble() * 30), [const Color(0xFFF8BBD0), const Color(0xFFB3E5FC), const Color(0xFFFFF59D)][i % 3]);
        }
        // cestino di uova
        final basket = Rect.fromLTWH(right - 34, b - 12, 34, 12);
        const eggs = [Color(0xFFF48FB1), Color(0xFF81D4FA), Color(0xFFFFE082), Color(0xFFA5D6A7), Color(0xFFCE93D8)];
        for (var i = 0; i < 5; i++) {
          final er = Rect.fromCenter(center: Offset(basket.left + 5 + i * 6, basket.top - 3 - (i % 2) * 3), width: 9, height: 12);
          c.drawOval(er, Paint()..color = eggs[i]);
          c.drawLine(Offset(er.left + 1, er.center.dy), Offset(er.right - 1, er.center.dy), Paint()
            ..color = Colors.white
            ..strokeWidth = 1.2);
        }
        c.drawRRect(RRect.fromRectAndRadius(basket, const Radius.circular(3)), Paint()..color = const Color(0xFFA1887F));
        for (double x = basket.left + 4; x < basket.right; x += 5) {
          c.drawLine(Offset(x, basket.top), Offset(x, basket.bottom), Paint()
            ..color = const Color(0xFF8D6E63)
            ..strokeWidth = 1);
        }
        c.drawArc(Rect.fromLTWH(basket.left + 2, basket.top - 22, basket.width - 4, 30), math.pi, math.pi, false, Paint()
          ..color = const Color(0xFF8D6E63)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
        _bunny(c, Offset(40, b));
        _chick(c, Offset(64, b));
        _pot(c, Offset(right - 50, b), const Color(0xFFFFF59D));
      case 'repubblica':
        const tri = [Color(0xFF009246), Color(0xFFF1F2F1), Color(0xFFCE2B37)];
        _bunting(c, s, tri);
        final path2 = Path()
          ..moveTo(8, 34)
          ..quadraticBezierTo(s.width / 2, 58, s.width - 8, 34);
        c.drawPath(path2, Paint()
          ..color = const Color(0xFF8D6E63)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
        final m2 = path2.computeMetrics().first;
        for (var i = 0; i < 10; i++) {
          final t = m2.getTangentForOffset(m2.length * (i + 0.5) / 10)!.position;
          c.drawPath(Path()..moveTo(t.dx - 6, t.dy)..lineTo(t.dx + 6, t.dy)..lineTo(t.dx, t.dy + 11)..close(), Paint()..color = tri[(i + 1) % 3]);
        }
        _rosette(c, Offset(right + 2, 76), tri);
        _confetti(c, s, r, tri, 30);
        // bandierina sul ripiano
        c.drawLine(Offset(40, b), Offset(40, b - 30), Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 1.6);
        for (var i = 0; i < 3; i++) {
          c.drawRect(Rect.fromLTWH(41 + i * 7.0, b - 30, 7, 14), Paint()..color = tri[i]);
        }
      case 'halloween':
        _web(c, const Offset(12, 8), 62, false);
        _web(c, Offset(s.width - 12, 8), 50, true);
        _spider(c, Offset(s.width * 0.42, 4), 46);
        _bunting(c, s, const [Color(0xFFEF6C00), Color(0xFF212121), Color(0xFF7B1FA2)]);
        for (var i = 0; i < 5; i++) {
          _bat(c, Offset(s.width * (0.25 + i * 0.13), 34 + r.nextDouble() * 26), 0.7 + r.nextDouble() * 0.5);
        }
        _ghost(c, Offset(s.width * 0.7, 60));
        _pumpkin(c, Offset(right - 8, b - 11), 30);
        _pumpkin(c, Offset(right - 32, b - 8), 20);
        _candle(c, Offset(36, b), 14);
        _candle(c, Offset(46, b), 20);
        c.drawOval(Rect.fromCenter(center: Offset(60, b - 4), width: 10, height: 8), Paint()..color = const Color(0xFFF5F5F5));
      case 'primavera':
        _leafGarland(c, s, r, const [Color(0xFF8BC34A), Color(0xFF7CB342), Color(0xFFAED581)]);
        for (var i = 0; i < 9; i++) {
          final x = 18 + i * (s.width - 36) / 8;
          _flower(c, Offset(x, 20 + (i % 3) * 7.0), [const Color(0xFFF8BBD0), const Color(0xFFFFFFFF), const Color(0xFFE1BEE7), const Color(0xFFFFF59D)][i % 4]);
        }
        for (var i = 0; i < 4; i++) {
          _butterfly(c, Offset(30 + r.nextDouble() * (s.width - 60), 46 + r.nextDouble() * 34), [const Color(0xFFFFB74D), const Color(0xFF64B5F6), const Color(0xFFF06292)][i % 3]);
        }
        _pot(c, Offset(right - 6, b), const Color(0xFFF48FB1));
        _pot(c, Offset(right - 28, b), const Color(0xFFFFF59D));
        _pot(c, Offset(40, b), const Color(0xFFCE93D8));
      case 'estate':
        final sun = Offset(right - 2, 34);
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          c.drawLine(sun + Offset(math.cos(a), math.sin(a)) * 14, sun + Offset(math.cos(a), math.sin(a)) * 21, Paint()
            ..color = const Color(0xFFFFB300)
            ..strokeWidth = 2);
        }
        c.drawCircle(sun, 11, Paint()..color = const Color(0xFFFFCA28));
        // gabbiani
        for (var i = 0; i < 3; i++) {
          final g = Offset(s.width * (0.3 + i * 0.12), 22 + (i % 2) * 10.0);
          c.drawPath(Path()..moveTo(g.dx - 7, g.dy)..quadraticBezierTo(g.dx - 3, g.dy - 5, g.dx, g.dy)..quadraticBezierTo(g.dx + 3, g.dy - 5, g.dx + 7, g.dy), Paint()
            ..color = const Color(0xFF546E7A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
        }
        // sabbia sul ripiano
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(10, b - 4, s.width - 20, 6), const Radius.circular(3)), Paint()..color = const Color(0xFFF3D9A4).withValues(alpha: 0.9));
        final u = Offset(34, b - 38);
        c.drawLine(u, Offset(u.dx + 4, b), Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 2);
        for (var i = 0; i < 4; i++) {
          c.drawArc(Rect.fromCenter(center: u, width: 46, height: 30), math.pi + i * math.pi / 4, math.pi / 4, true, Paint()..color = i.isEven ? const Color(0xFFE53935) : Colors.white);
        }
        _beachBall(c, Offset(right - 14, b - 9), 9);
        _shell(c, Offset(62, b - 2), const Color(0xFFFFCCBC));
        _shell(c, Offset(right - 34, b - 2), const Color(0xFFF8BBD0));
        _star(c, Offset(74, b - 5), 5, const Color(0xFFFF8A65));
      case 'autunno':
        const cols = [Color(0xFFD84315), Color(0xFFF9A825), Color(0xFF8D6E63), Color(0xFFEF6C00), Color(0xFFBF360C)];
        _leafGarland(c, s, r, cols);
        for (var i = 0; i < 22; i++) {
          _leaf(c, Offset(14 + r.nextDouble() * (s.width - 28), 30 + r.nextDouble() * b * 0.38), r.nextDouble() * math.pi, cols[i % cols.length], 4.5 + r.nextDouble() * 3.5);
        }
        for (var i = 0; i < 9; i++) {
          _leaf(c, Offset(16 + i * 7.0, b - 3), math.pi / 2 + r.nextDouble(), cols[(i + 1) % cols.length], 5);
        }
        for (var i = 0; i < 6; i++) {
          _leaf(c, Offset(right - 30 + i * 6.0, b - 3), math.pi / 2 + r.nextDouble(), cols[(i + 2) % cols.length], 5);
        }
        _pumpkin(c, Offset(right - 6, b - 9), 22);
        _mushroom(c, Offset(right - 30, b));
        _acorn(c, Offset(70, b - 5));
        _acorn(c, Offset(78, b - 4));
      case 'inverno':
        _icicles(c, s, r);
        for (var i = 0; i < 30; i++) {
          _flake(c, Offset(14 + r.nextDouble() * (s.width - 28), 20 + r.nextDouble() * b * 0.5), 2 + r.nextDouble() * 4);
        }
        final snow = Paint()..color = Colors.white.withValues(alpha: 0.92);
        final path = Path()..moveTo(10, b + 2);
        for (double x = 10; x <= s.width - 10; x += 12) {
          path.quadraticBezierTo(x + 6, b - 5 - r.nextDouble() * 4, x + 12, b + 2);
        }
        path
          ..lineTo(s.width - 10, b + 5)
          ..lineTo(10, b + 5)
          ..close();
        c.drawPath(path, snow);
        _snowman(c, Offset(right - 8, b - 1));
        _tree(c, Offset(36, b - 2), 32);
      case 'saga':
        _cake(c, Offset(46, b), candles: 1, body: const Color(0xFF8D6E63), cream: const Color(0xFFFFF8E1));
        _star(c, Offset(46, b - 46), 4, const Color(0xFFE2B84B));
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(_DecorPainter old) => old.season != season || old.boardTop != boardTop;
}
