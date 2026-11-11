import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Sfondi dipinti dietro gli scaffali.
const shelfBackdrops = ['Carta', 'Intonaco', 'Mattoni', 'Carta da parati', 'Boiserie', 'Pietra', 'Biblioteca', 'Cielo notturno', 'Pergamena'];

class ShelfBackdrop extends StatelessWidget {
  final String kind;
  const ShelfBackdrop(this.kind, {super.key});

  @override
  Widget build(BuildContext context) {
    if (kind == 'Carta' || !shelfBackdrops.contains(kind)) return const SizedBox.expand();
    return SizedBox.expand(child: CustomPaint(painter: _BackdropPainter(kind, LK.dark, LK.paper)));
  }
}

class _BackdropPainter extends CustomPainter {
  final String kind;
  final bool dark;
  final Color paper;
  _BackdropPainter(this.kind, this.dark, this.paper);

  /// In modalità scura i colori si abbassano verso la carta del tema.
  Color _c(Color c) => dark ? Color.lerp(c, paper, 0.72)! : Color.lerp(c, const Color(0xFFFAF7F2), 0.35)!;

  @override
  void paint(Canvas c, Size s) {
    final r = math.Random(kind.hashCode);
    final rect = Offset.zero & s;
    final p = Paint();
    switch (kind) {
      case 'Intonaco':
        c.drawRect(rect, p..color = _c(const Color(0xFFE9DCC6)));
        for (var i = 0; i < 900; i++) {
          p.color = (r.nextBool() ? Colors.white : const Color(0xFF8A6A3E)).withValues(alpha: 0.05 + r.nextDouble() * 0.05);
          c.drawCircle(Offset(r.nextDouble() * s.width, r.nextDouble() * s.height), 1 + r.nextDouble() * 5, p);
        }
      case 'Mattoni':
        c.drawRect(rect, p..color = _c(const Color(0xFFCDB8A0)));
        const bw = 64.0, bh = 26.0;
        for (double y = 0, row = 0; y < s.height; y += bh, row++) {
          final off = row % 2 == 0 ? 0.0 : bw / 2;
          for (double x = -off; x < s.width; x += bw) {
            final tone = 0.85 + r.nextDouble() * 0.3;
            p.color = _c(Color.lerp(const Color(0xFFA0583E), const Color(0xFFC07A56), r.nextDouble())!).withValues(alpha: tone.clamp(0, 1));
            c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 2, y + 2, bw - 4, bh - 4), const Radius.circular(2)), p);
          }
        }
      case 'Carta da parati':
        c.drawRect(rect, p..color = _c(const Color(0xFFE6D8BC)));
        final stripe = Paint()..color = _c(const Color(0xFFD7C39C)).withValues(alpha: 0.7);
        for (double x = 0; x < s.width; x += 46) {
          c.drawRect(Rect.fromLTWH(x, 0, 14, s.height), stripe);
        }
        final orn = Paint()
          ..color = _c(const Color(0xFFB59A64)).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (double y = 20; y < s.height; y += 70) {
          for (double x = 30; x < s.width; x += 46) {
            final cy = y + ((x / 46).round().isOdd ? 35 : 0);
            c.drawPath(
                Path()
                  ..moveTo(x, cy - 10)
                  ..quadraticBezierTo(x + 8, cy, x, cy + 10)
                  ..quadraticBezierTo(x - 8, cy, x, cy - 10),
                orn);
          }
        }
      case 'Boiserie':
        c.drawRect(rect, p..color = _c(const Color(0xFF8A6A48)));
        final frame = Paint()
          ..color = _c(const Color(0xFF5E4430))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        final light = Paint()
          ..color = _c(const Color(0xFFB08A60)).withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        const pw = 120.0, ph = 180.0;
        for (double y = 16; y < s.height; y += ph + 20) {
          for (double x = 14; x < s.width; x += pw + 16) {
            final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, pw, ph), const Radius.circular(4));
            c.drawRRect(rr, frame);
            c.drawRRect(rr.deflate(5), light);
          }
        }
      case 'Pietra':
        c.drawRect(rect, p..color = _c(const Color(0xFFB8B2A6)));
        for (double y = 0; y < s.height; y += 40) {
          for (double x = 0; x < s.width;) {
            final w = 50 + r.nextDouble() * 60;
            p.color = _c(Color.lerp(const Color(0xFF9C968A), const Color(0xFFC9C3B6), r.nextDouble())!);
            c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 2, y + 2, w - 4, 36), const Radius.circular(6)), p);
            x += w;
          }
        }
      case 'Biblioteca':
        c.drawRect(rect, p..color = _c(const Color(0xFF3E5A48)));
        final dam = Paint()..color = _c(const Color(0xFF4E6E58)).withValues(alpha: 0.7);
        for (double y = 0; y < s.height; y += 60) {
          for (double x = 0; x < s.width; x += 60) {
            c.drawCircle(Offset(x + ((y / 60).round().isOdd ? 30 : 0), y), 10, dam);
          }
        }
      case 'Cielo notturno':
        c.drawRect(rect, p..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_c(const Color(0xFF1C2340)), _c(const Color(0xFF3B4373))]).createShader(rect));
        p.shader = null;
        for (var i = 0; i < 220; i++) {
          p.color = Colors.white.withValues(alpha: (dark ? 0.25 : 0.5) + r.nextDouble() * 0.4);
          c.drawCircle(Offset(r.nextDouble() * s.width, r.nextDouble() * s.height), 0.5 + r.nextDouble(), p);
        }
      case 'Pergamena':
        c.drawRect(rect, p..color = _c(const Color(0xFFF1E3B8)));
        p.shader = RadialGradient(colors: [Colors.transparent, _c(const Color(0xFFB8945A)).withValues(alpha: 0.35)], stops: const [0.6, 1]).createShader(rect);
        c.drawRect(rect, p);
        p.shader = null;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.kind != kind || old.dark != dark;
}
