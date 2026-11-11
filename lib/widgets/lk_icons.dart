import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Icone disegnate a mano, tratto sottile in stile inciso.
enum LKGlyph { library, read, add, settings, back, chapters, recap, search, graph, quill }

class LKIcon extends StatelessWidget {
  final LKGlyph glyph;
  final Color color;
  final double size;
  const LKIcon(this.glyph, {super.key, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _GlyphPainter(glyph, color)));
}

class _GlyphPainter extends CustomPainter {
  final LKGlyph g;
  final Color color;
  _GlyphPainter(this.g, this.color);

  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 24, s.height / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    switch (g) {
      case LKGlyph.library:
        // tre dorsi e un libro inclinato su una mensola
        c.drawRRect(RRect.fromLTRBR(3.5, 5, 7, 19, const Radius.circular(0.8)), p);
        c.drawRRect(RRect.fromLTRBR(8, 3.5, 11.5, 19, const Radius.circular(0.8)), p);
        c.drawLine(const Offset(9.75, 6.5), const Offset(9.75, 8), p);
        c.save();
        c.translate(16.5, 19);
        c.rotate(-0.28);
        c.drawRRect(RRect.fromLTRBR(-1.8, -14, 1.8, 0, const Radius.circular(0.8)), p);
        c.restore();
        c.drawLine(const Offset(2, 20.5), const Offset(22, 20.5), p);
        break;
      case LKGlyph.read:
        // libro aperto con segnalibro
        final l = Path()
          ..moveTo(12, 6.5)
          ..quadraticBezierTo(8, 4.5, 3, 5.5)
          ..lineTo(3, 18.5)
          ..quadraticBezierTo(8, 17.5, 12, 19.5);
        final r = Path()
          ..moveTo(12, 6.5)
          ..quadraticBezierTo(16, 4.5, 21, 5.5)
          ..lineTo(21, 18.5)
          ..quadraticBezierTo(16, 17.5, 12, 19.5);
        c.drawPath(l, p);
        c.drawPath(r, p);
        c.drawLine(const Offset(12, 6.5), const Offset(12, 19.5), p);
        c.drawPath(
          Path()
            ..moveTo(15.5, 5.6)
            ..lineTo(15.5, 11)
            ..lineTo(17, 9.8)
            ..lineTo(18.5, 11)
            ..lineTo(18.5, 5.2),
          p,
        );
        break;
      case LKGlyph.add:
        c.drawCircle(const Offset(12, 12), 8.5, p);
        c.drawLine(const Offset(12, 8), const Offset(12, 16), p);
        c.drawLine(const Offset(8, 12), const Offset(16, 12), p);
        break;
      case LKGlyph.settings:
        // tre cursori con pomelli a rombo
        for (final (y, x) in [(6.0, 15.0), (12.0, 8.0), (18.0, 13.0)]) {
          c.drawLine(Offset(3, y), Offset(21, y), p);
          final d = Path()
            ..moveTo(x, y - 2.4)
            ..lineTo(x + 2.4, y)
            ..lineTo(x, y + 2.4)
            ..lineTo(x - 2.4, y)
            ..close();
          c.drawPath(d, Paint()..color = color);
        }
        break;
      case LKGlyph.back:
        c.drawLine(const Offset(20, 12), const Offset(5, 12), p);
        c.drawPath(
          Path()
            ..moveTo(10.5, 6.5)
            ..lineTo(5, 12)
            ..lineTo(10.5, 17.5),
          p,
        );
        c.drawCircle(const Offset(20.5, 12), 1.1, fill);
        break;
      case LKGlyph.chapters:
        for (final y in [6.0, 12.0, 18.0]) {
          final d = Path()
            ..moveTo(4.5, y - 1.6)
            ..lineTo(6.1, y)
            ..lineTo(4.5, y + 1.6)
            ..lineTo(2.9, y)
            ..close();
          c.drawPath(d, fill);
          c.drawLine(Offset(9, y), Offset(21, y), p);
        }
        break;
      case LKGlyph.recap:
        // pergamena arrotolata
        c.drawPath(
          Path()
            ..moveTo(6, 4)
            ..lineTo(18, 4)
            ..quadraticBezierTo(20.5, 4, 20.5, 6.5)
            ..quadraticBezierTo(20.5, 9, 18, 9)
            ..lineTo(18, 18)
            ..quadraticBezierTo(18, 20.5, 15.5, 20.5)
            ..lineTo(5, 20.5)
            ..quadraticBezierTo(3, 20.5, 3, 18.5)
            ..quadraticBezierTo(3, 16.5, 5, 16.5)
            ..lineTo(6, 16.5)
            ..lineTo(6, 4),
          p,
        );
        c.drawLine(const Offset(9, 9), const Offset(15, 9), p);
        c.drawLine(const Offset(9, 12.5), const Offset(15, 12.5), p);
        break;
      case LKGlyph.search:
        c.drawCircle(const Offset(10.5, 10.5), 6, p);
        c.drawLine(const Offset(15, 15), const Offset(20.5, 20.5), p..strokeWidth = 2);
        break;
      case LKGlyph.graph:
        const nodes = [Offset(6, 7), Offset(18, 6), Offset(12, 13), Offset(5, 18.5), Offset(19, 18)];
        for (final (a, b) in [(0, 2), (1, 2), (2, 3), (2, 4), (0, 1)]) {
          c.drawLine(nodes[a], nodes[b], p..strokeWidth = 1.2);
        }
        for (final n in nodes) {
          c.drawCircle(n, 2.2, Paint()..color = color);
        }
        break;
      case LKGlyph.quill:
        c.drawPath(
          Path()
            ..moveTo(20, 3)
            ..quadraticBezierTo(9, 6, 6, 17)
            ..quadraticBezierTo(15, 14, 20, 3),
          p,
        );
        c.drawLine(const Offset(6, 17), const Offset(3.5, 21), p);
        c.drawLine(Offset(9 + math.sin(0.0), 13), const Offset(16, 7.5), p..strokeWidth = 1);
        break;
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.g != g || old.color != color;
}
