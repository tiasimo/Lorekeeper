import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Oggetti da mettere sugli scaffali: alcuni sono immagini, altri disegnati.
const decorObjects = {
  'candela': 'Candela',
  'calamaio': 'Calamaio',
  'pianta': 'Pianta',
  'clessidra': 'Clessidra',
  'pila': 'Pila di libri',
  'globo': 'Mappamondo',
  'gufo': 'Gufo',
  'lanterna': 'Lanterna',
  'tazza': 'Tazza di tè',
  'cristallo': 'Cristallo',
  'teschio': 'Teschio',
  'gatto': 'Gatto',
};

const _images = {'candela', 'calamaio', 'pianta', 'clessidra', 'pila'};

class DecorObject extends StatelessWidget {
  final String name;
  final double height;
  const DecorObject(this.name, {super.key, this.height = 150});

  @override
  Widget build(BuildContext context) {
    if (_images.contains(name)) return Image.asset('assets/decor/$name.webp', height: height, fit: BoxFit.contain);
    final h = height * 0.62;
    return SizedBox(width: h * 0.9, height: h, child: CustomPaint(painter: _ObjPainter(name)));
  }
}

class _ObjPainter extends CustomPainter {
  final String name;
  _ObjPainter(this.name);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.18);
    c.drawOval(Rect.fromCenter(center: Offset(w / 2, h - 2), width: w * 0.8, height: 6), shadow);
    switch (name) {
      case 'globo':
        final o = Offset(w / 2, h * 0.42), r = w * 0.36;
        c.drawRect(Rect.fromCenter(center: Offset(w / 2, h - 6), width: w * 0.5, height: 6), Paint()..color = const Color(0xFF5D4037));
        c.drawLine(Offset(w / 2, h - 8), Offset(w / 2, o.dy + r), Paint()
          ..color = const Color(0xFF5D4037)
          ..strokeWidth = 3);
        c.drawCircle(o, r, Paint()..color = const Color(0xFF4A86A8));
        final land = Paint()..color = const Color(0xFF8DB36B);
        c.drawOval(Rect.fromCenter(center: o + Offset(-r * 0.3, -r * 0.2), width: r * 0.8, height: r * 0.6), land);
        c.drawOval(Rect.fromCenter(center: o + Offset(r * 0.35, r * 0.3), width: r * 0.6, height: r * 0.7), land);
        c.drawArc(Rect.fromCircle(center: o, radius: r + 4), -math.pi * 0.9, math.pi * 1.8, false, Paint()
          ..color = const Color(0xFFB08A4E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
      case 'gufo':
        final body = Paint()..color = const Color(0xFF8D6E63);
        c.drawOval(Rect.fromLTWH(w * 0.15, h * 0.25, w * 0.7, h * 0.72), body);
        c.drawPath(Path()..moveTo(w * 0.2, h * 0.32)..lineTo(w * 0.25, h * 0.12)..lineTo(w * 0.4, h * 0.27)..close(), body);
        c.drawPath(Path()..moveTo(w * 0.8, h * 0.32)..lineTo(w * 0.75, h * 0.12)..lineTo(w * 0.6, h * 0.27)..close(), body);
        c.drawOval(Rect.fromLTWH(w * 0.28, h * 0.55, w * 0.44, h * 0.38), Paint()..color = const Color(0xFFD7CCC8));
        for (final x in [0.36, 0.64]) {
          c.drawCircle(Offset(w * x, h * 0.4), w * 0.13, Paint()..color = const Color(0xFFFFF8E1));
          c.drawCircle(Offset(w * x, h * 0.4), w * 0.06, Paint()..color = const Color(0xFF212121));
        }
        c.drawPath(Path()..moveTo(w * 0.46, h * 0.48)..lineTo(w * 0.54, h * 0.48)..lineTo(w * 0.5, h * 0.56)..close(), Paint()..color = const Color(0xFFFFA000));
      case 'lanterna':
        const brass = Color(0xFFB08A4E);
        c.drawCircle(Offset(w / 2, h * 0.55), w * 0.5, Paint()
          ..shader = RadialGradient(colors: [const Color(0x66FFC56B), const Color(0x00FFC56B)]).createShader(Rect.fromCircle(center: Offset(w / 2, h * 0.55), radius: w * 0.5)));
        c.drawRRect(RRect.fromLTRBR(w * 0.22, h * 0.25, w * 0.78, h * 0.85, const Radius.circular(3)), Paint()..color = const Color(0xFFFFD58A));
        c.drawRRect(RRect.fromLTRBR(w * 0.22, h * 0.25, w * 0.78, h * 0.85, const Radius.circular(3)), Paint()
          ..color = brass
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
        c.drawPath(Path()..moveTo(w * 0.15, h * 0.25)..lineTo(w * 0.3, h * 0.12)..lineTo(w * 0.7, h * 0.12)..lineTo(w * 0.85, h * 0.25)..close(), Paint()..color = const Color(0xFF3A2E24));
        c.drawCircle(Offset(w / 2, h * 0.07), w * 0.06, Paint()
          ..color = brass
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
        c.drawOval(Rect.fromCenter(center: Offset(w / 2, h * 0.6), width: w * 0.16, height: h * 0.22), Paint()..color = const Color(0xFFF2A23A));
        c.drawRect(Rect.fromLTWH(w * 0.15, h * 0.85, w * 0.7, h * 0.1), Paint()..color = const Color(0xFF3A2E24));
      case 'tazza':
        final cup = Paint()..color = const Color(0xFFF5F0E6);
        c.drawOval(Rect.fromCenter(center: Offset(w / 2, h - 5), width: w * 0.9, height: 7), Paint()..color = const Color(0xFFE0D6C6));
        c.drawPath(
            Path()
              ..moveTo(w * 0.18, h * 0.5)
              ..lineTo(w * 0.72, h * 0.5)
              ..quadraticBezierTo(w * 0.7, h - 8, w * 0.45, h - 7)
              ..quadraticBezierTo(w * 0.2, h - 8, w * 0.18, h * 0.5)
              ..close(),
            cup);
        c.drawArc(Rect.fromLTWH(w * 0.62, h * 0.56, w * 0.26, h * 0.22), -math.pi / 2, math.pi, false, Paint()
          ..color = const Color(0xFFF5F0E6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
        c.drawOval(Rect.fromLTWH(w * 0.18, h * 0.46, w * 0.54, h * 0.08), Paint()..color = const Color(0xFF8D5524));
        final steam = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        for (final x in [0.36, 0.5]) {
          c.drawPath(Path()..moveTo(w * x, h * 0.42)..quadraticBezierTo(w * (x + 0.08), h * 0.32, w * x, h * 0.24)..quadraticBezierTo(w * (x - 0.08), h * 0.16, w * x, h * 0.08), steam);
        }
      case 'cristallo':
        c.drawCircle(Offset(w / 2, h * 0.5), w * 0.45, Paint()
          ..shader = RadialGradient(colors: [const Color(0x669C7BD6), const Color(0x009C7BD6)]).createShader(Rect.fromCircle(center: Offset(w / 2, h * 0.5), radius: w * 0.45)));
        final cols = [const Color(0xFF7E57C2), const Color(0xFF9575CD), const Color(0xFFB39DDB)];
        for (var i = 0; i < 3; i++) {
          final cx = w * (0.32 + i * 0.18), top = h * (0.25 + (i == 1 ? -0.1 : 0.1));
          c.drawPath(
              Path()
                ..moveTo(cx - w * 0.09, h - 6)
                ..lineTo(cx - w * 0.09, top + h * 0.12)
                ..lineTo(cx, top)
                ..lineTo(cx + w * 0.09, top + h * 0.12)
                ..lineTo(cx + w * 0.09, h - 6)
                ..close(),
              Paint()..color = cols[i]);
        }
      case 'teschio':
        final bone = Paint()..color = const Color(0xFFEDE6D6);
        c.drawOval(Rect.fromLTWH(w * 0.15, h * 0.2, w * 0.7, h * 0.58), bone);
        c.drawRRect(RRect.fromLTRBR(w * 0.3, h * 0.62, w * 0.7, h * 0.92, const Radius.circular(4)), bone);
        final dark = Paint()..color = const Color(0xFF3E2723);
        c.drawOval(Rect.fromCenter(center: Offset(w * 0.36, h * 0.48), width: w * 0.18, height: h * 0.16), dark);
        c.drawOval(Rect.fromCenter(center: Offset(w * 0.64, h * 0.48), width: w * 0.18, height: h * 0.16), dark);
        c.drawPath(Path()..moveTo(w * 0.5, h * 0.58)..lineTo(w * 0.45, h * 0.67)..lineTo(w * 0.55, h * 0.67)..close(), dark);
        for (var i = 0; i < 4; i++) {
          c.drawLine(Offset(w * (0.37 + i * 0.09), h * 0.78), Offset(w * (0.37 + i * 0.09), h * 0.9), dark..strokeWidth = 1.2);
        }
      case 'gatto':
        final fur = Paint()..color = const Color(0xFF37474F);
        c.drawOval(Rect.fromLTWH(w * 0.1, h * 0.45, w * 0.75, h * 0.52), fur);
        c.drawCircle(Offset(w * 0.5, h * 0.36), w * 0.24, fur);
        c.drawPath(Path()..moveTo(w * 0.3, h * 0.28)..lineTo(w * 0.32, h * 0.06)..lineTo(w * 0.46, h * 0.2)..close(), fur);
        c.drawPath(Path()..moveTo(w * 0.7, h * 0.28)..lineTo(w * 0.68, h * 0.06)..lineTo(w * 0.54, h * 0.2)..close(), fur);
        c.drawPath(
            Path()
              ..moveTo(w * 0.82, h * 0.88)
              ..quadraticBezierTo(w * 1.0, h * 0.7, w * 0.88, h * 0.45),
            Paint()
              ..color = const Color(0xFF37474F)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..strokeCap = StrokeCap.round);
        for (final x in [0.42, 0.58]) {
          c.drawOval(Rect.fromCenter(center: Offset(w * x, h * 0.35), width: w * 0.09, height: h * 0.07), Paint()..color = const Color(0xFFFFD54F));
          c.drawOval(Rect.fromCenter(center: Offset(w * x, h * 0.35), width: w * 0.02, height: h * 0.06), Paint()..color = const Color(0xFF212121));
        }
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(_ObjPainter old) => old.name != name;
}
