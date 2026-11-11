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

  @override
  void paint(Canvas c, Size s) {
    final r = math.Random(seed + season.hashCode);
    final right = s.width - 30.0;
    switch (season) {
      case 'compleanno':
        _bunting(c, s, const [Color(0xFFE91E63), Color(0xFFFFC107), Color(0xFF29B6F6), Color(0xFF66BB6A), Color(0xFFAB47BC)]);
        _cake(c, Offset(right - 6, boardTop), candles: 3);
        final age = birthdayAge();
        if (age != null) {
          final tp = TextPainter(
            text: TextSpan(text: '$age', style: const TextStyle(color: Color(0xFFC2185B), fontSize: 12, fontWeight: FontWeight.w800)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(c, Offset(right - 6 - tp.width / 2, boardTop - 15));
        }
        _balloon(c, Offset(right - 2, 52), const Color(0xFFE53935));
        _balloon(c, Offset(right + 10, 64), const Color(0xFF42A5F5));
        _confetti(c, s, r, const [Color(0xFFFFC107), Color(0xFFE91E63), Color(0xFF29B6F6)], 24);
      case 'anniversario':
        // coccarda con gli anni di Lorekeeper
        final o = Offset(right - 4, 40);
        c.drawPath(
            Path()
              ..moveTo(o.dx - 7, o.dy)
              ..lineTo(o.dx - 12, o.dy + 30)
              ..lineTo(o.dx - 4, o.dy + 24)
              ..lineTo(o.dx, o.dy + 32)
              ..lineTo(o.dx + 4, o.dy + 24)
              ..lineTo(o.dx + 12, o.dy + 30)
              ..lineTo(o.dx + 7, o.dy)
              ..close(),
            Paint()..color = const Color(0xFF7A1E2E));
        c.drawCircle(o, 15, Paint()..color = const Color(0xFFE2B84B));
        c.drawCircle(o, 11, Paint()..color = const Color(0xFFF6E3A8));
        final tp = TextPainter(
          text: TextSpan(text: '${lorekeeperYears()}', style: const TextStyle(color: Color(0xFF7A1E2E), fontSize: 13, fontWeight: FontWeight.w800)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
        _confetti(c, s, r, const [Color(0xFFE2B84B), Color(0xFF7A1E2E)], 18);
      case 'epifania':
        // calza appesa e scopa della befana
        final sx = right + 6;
        c.drawLine(Offset(sx, 14), Offset(sx, 30), Paint()..color = const Color(0xFF8D6E63));
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
        c.drawLine(Offset(right - 50, boardTop - 2), Offset(right - 14, boardTop - 34), Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 2.5);
        c.drawPath(
            Path()
              ..moveTo(right - 54, boardTop - 2)
              ..lineTo(right - 44, boardTop - 16)
              ..lineTo(right - 36, boardTop - 2)
              ..close(),
            Paint()..color = const Color(0xFFC8A15A));
      case 'repubblica':
        _bunting(c, s, const [Color(0xFF009246), Color(0xFFF1F2F1), Color(0xFFCE2B37)]);
      case 'primavera':
        for (var i = 0; i < 7; i++) {
          final x = 18 + i * (s.width - 36) / 6;
          c.drawLine(Offset(x, 4), Offset(x, 14 + (i % 3) * 8), Paint()
            ..color = const Color(0xFF7CB342)
            ..strokeWidth = 1.2);
          _flower(c, Offset(x, 18 + (i % 3) * 8), [const Color(0xFFF8BBD0), const Color(0xFFFFFFFF), const Color(0xFFE1BEE7)][i % 3]);
        }
        _flower(c, Offset(right - 6, boardTop - 8), const Color(0xFFF48FB1));
        _flower(c, Offset(right + 6, boardTop - 12), const Color(0xFFFFF59D));
      case 'estate':
        // sole e ombrellone sul ripiano
        final sun = Offset(right - 2, 34);
        for (var i = 0; i < 10; i++) {
          final a = i * math.pi / 5;
          c.drawLine(sun + Offset(math.cos(a), math.sin(a)) * 13, sun + Offset(math.cos(a), math.sin(a)) * 19, Paint()
            ..color = const Color(0xFFFFB300)
            ..strokeWidth = 2);
        }
        c.drawCircle(sun, 10, Paint()..color = const Color(0xFFFFCA28));
        final u = Offset(30, boardTop - 34);
        c.drawLine(u, Offset(u.dx + 4, boardTop), Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 2);
        for (var i = 0; i < 4; i++) {
          c.drawArc(Rect.fromCenter(center: u, width: 40, height: 26), math.pi + i * math.pi / 4, math.pi / 4, true,
              Paint()..color = i.isEven ? const Color(0xFFE53935) : Colors.white);
        }
      case 'autunno':
        const cols = [Color(0xFFD84315), Color(0xFFF9A825), Color(0xFF8D6E63), Color(0xFFEF6C00)];
        for (var i = 0; i < 12; i++) {
          _leaf(c, Offset(14 + r.nextDouble() * (s.width - 28), 8 + r.nextDouble() * boardTop * 0.3), r.nextDouble() * math.pi, cols[i % 4], 5 + r.nextDouble() * 3);
        }
        for (var i = 0; i < 5; i++) {
          _leaf(c, Offset(20 + i * 9.0, boardTop - 3), math.pi / 2 + r.nextDouble(), cols[(i + 1) % 4], 5);
        }
      case 'inverno':
        for (var i = 0; i < 16; i++) {
          _flake(c, Offset(14 + r.nextDouble() * (s.width - 28), 8 + r.nextDouble() * boardTop * 0.45), 3 + r.nextDouble() * 3);
        }
        final snow = Paint()..color = Colors.white.withValues(alpha: 0.8);
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(10, boardTop - 3, s.width - 20, 5), const Radius.circular(3)), snow);
      case 'saga':
        _cake(c, Offset(46, boardTop), candles: 1, body: const Color(0xFF8D6E63), cream: const Color(0xFFFFF8E1));
      case 'natale':
        _garland(c, s, const Color(0xFF2F5A34), const [Color(0xFFE53935), Color(0xFFFFC107), Color(0xFF43A047), Color(0xFF1E88E5)]);
        // neve sul ripiano
        final snow = Paint()..color = Colors.white.withValues(alpha: 0.92);
        final path = Path()..moveTo(10, boardTop + 2);
        for (double x = 10; x <= s.width - 10; x += 14) {
          path.quadraticBezierTo(x + 7, boardTop - 4 - r.nextDouble() * 3, x + 14, boardTop + 2);
        }
        path
          ..lineTo(s.width - 10, boardTop + 5)
          ..lineTo(10, boardTop + 5)
          ..close();
        c.drawPath(path, snow);
        // pallina appesa al fianco destro
        c.drawLine(Offset(right + 14, 18), Offset(right + 14, 58), Paint()..color = const Color(0xFFB0905A));
        c.drawCircle(Offset(right + 14, 66), 9, Paint()..color = const Color(0xFFC62828));
        c.drawCircle(Offset(right + 11, 63), 2.5, Paint()..color = Colors.white.withValues(alpha: 0.7));
      case 'capodanno':
        final cols = [const Color(0xFFFFC107), const Color(0xFFE91E63), const Color(0xFF29B6F6), const Color(0xFF66BB6A)];
        for (var i = 0; i < 6; i++) {
          final x = 20 + i * (s.width - 40) / 5;
          final p = Path()..moveTo(x, 4);
          for (double y = 4; y < 70; y += 10) {
            p.quadraticBezierTo((y ~/ 10).isEven ? x + 8 : x - 8, y + 5, x, y + 10);
          }
          c.drawPath(
              p,
              Paint()
                ..color = cols[i % cols.length]
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.2);
        }
        _confetti(c, s, r, cols, 40);
      case 'sanvalentino':
        _garland(c, s, const Color(0xFFB0905A), const [Color(0xFFE53950), Color(0xFFF48FB1), Color(0xFFC2185B)], hearts: true, sag: 20);
        _heart(c, Offset(right - 6, boardTop - 10), 9, const Color(0xFFE53950));
      case 'carnevale':
        _confetti(c, s, r, const [Color(0xFFFFC107), Color(0xFFE91E63), Color(0xFF29B6F6), Color(0xFF66BB6A), Color(0xFFAB47BC)], 70);
        // maschera sul ripiano
        final mask = Path()
          ..moveTo(right - 26, boardTop - 16)
          ..quadraticBezierTo(right - 12, boardTop - 24, right + 2, boardTop - 16)
          ..quadraticBezierTo(right - 12, boardTop - 2, right - 26, boardTop - 16);
        c.drawPath(mask, Paint()..color = const Color(0xFF7B1FA2));
        c.drawOval(Rect.fromCenter(center: Offset(right - 18, boardTop - 16), width: 7, height: 4), Paint()..color = Colors.black);
        c.drawOval(Rect.fromCenter(center: Offset(right - 6, boardTop - 16), width: 7, height: 4), Paint()..color = Colors.black);
      case 'pasqua':
        const eggs = [Color(0xFFF48FB1), Color(0xFF81D4FA), Color(0xFFFFE082), Color(0xFFA5D6A7)];
        for (var i = 0; i < 4; i++) {
          final cx = 28.0 + i * 13;
          final rect = Rect.fromCenter(center: Offset(cx, boardTop - 10), width: 12, height: 16);
          c.drawOval(rect, Paint()..color = eggs[i]);
          c.drawLine(Offset(rect.left + 1, rect.center.dy), Offset(rect.right - 1, rect.center.dy), Paint()
            ..color = Colors.white
            ..strokeWidth = 1.6);
        }
        // fiori appesi
        _garland(c, s, const Color(0xFF8BC34A), const [Color(0xFFFFF59D), Color(0xFFF8BBD0), Color(0xFFB3E5FC)], sag: 14);
      case 'halloween':
        // ragnatela nell'angolo
        final web = Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9;
        const o = Offset(12, 8);
        for (var i = 0; i <= 4; i++) {
          final a = i * math.pi / 8;
          c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * 60, web);
        }
        for (var k = 1; k <= 4; k++) {
          final p = Path();
          for (var i = 0; i <= 4; i++) {
            final a = i * math.pi / 8;
            final pt = o + Offset(math.cos(a), math.sin(a)) * (k * 14.0);
            i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
          }
          c.drawPath(p, web);
        }
        // zucca sul ripiano
        final pc = Offset(right - 10, boardTop - 12);
        final orange = Paint()..color = const Color(0xFFEF6C00);
        c.drawOval(Rect.fromCenter(center: pc, width: 30, height: 22), orange);
        c.drawOval(Rect.fromCenter(center: pc, width: 14, height: 22), Paint()..color = const Color(0xFFF57C00));
        c.drawRect(Rect.fromCenter(center: pc + const Offset(0, -13), width: 4, height: 6), Paint()..color = const Color(0xFF4E342E));
        final face = Paint()..color = const Color(0xFF3E2723);
        c.drawPath(
            Path()
              ..moveTo(pc.dx - 8, pc.dy - 3)
              ..lineTo(pc.dx - 4, pc.dy - 7)
              ..lineTo(pc.dx - 2, pc.dy - 3)
              ..close(),
            face);
        c.drawPath(
            Path()
              ..moveTo(pc.dx + 8, pc.dy - 3)
              ..lineTo(pc.dx + 4, pc.dy - 7)
              ..lineTo(pc.dx + 2, pc.dy - 3)
              ..close(),
            face);
        c.drawArc(Rect.fromCenter(center: pc + const Offset(0, 2), width: 14, height: 8), 0.2, math.pi - 0.4, false, face..strokeWidth = 2..style = PaintingStyle.stroke);
        // pipistrelli
        final bat = Paint()..color = const Color(0xFF2B2B2B);
        for (var i = 0; i < 3; i++) {
          final b = Offset(s.width * (0.35 + i * 0.18), 14 + r.nextDouble() * 22);
          c.drawPath(
              Path()
                ..moveTo(b.dx, b.dy)
                ..quadraticBezierTo(b.dx - 6, b.dy - 6, b.dx - 12, b.dy - 1)
                ..quadraticBezierTo(b.dx - 7, b.dy + 1, b.dx, b.dy + 3)
                ..quadraticBezierTo(b.dx + 7, b.dy + 1, b.dx + 12, b.dy - 1)
                ..quadraticBezierTo(b.dx + 6, b.dy - 6, b.dx, b.dy),
              bat);
        }
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(_DecorPainter old) => old.season != season || old.boardTop != boardTop;
}
