import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lanterna della home: di sera si accende (con la fiamma che tremola), di giorno resta spenta.
class HomeLantern extends StatefulWidget {
  final double size;
  const HomeLantern({super.key, this.size = 44});
  @override
  State<HomeLantern> createState() => _HomeLanternState();
}

class _HomeLanternState extends State<HomeLantern> with TickerProviderStateMixin {
  late final AnimationController _flicker = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  late final AnimationController _light = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _manual = false; // acceso/spento a mano con un tocco

  static bool get evening {
    final h = DateTime.now().hour;
    return h >= 18 || h < 6;
  }

  @override
  void initState() {
    super.initState();
    // la sera si accende con un piccolo "fiammifero"
    if (evening) Future.delayed(const Duration(milliseconds: 600), () => mounted ? _light.forward() : null);
  }

  @override
  void dispose() {
    _flicker.dispose();
    _light.dispose();
    super.dispose();
  }

  void _toggle() {
    _manual = true;
    _light.value > 0.5 ? _light.reverse() : _light.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Tooltip(
        message: evening ? 'Buona lettura serale' : 'Si accende la sera',
        child: AnimatedBuilder(
          animation: Listenable.merge([_flicker, _light]),
          builder: (context, _) => CustomPaint(
            size: Size(widget.size * 0.7, widget.size),
            painter: _LanternPainter(lit: Curves.easeOut.transform(_light.value), t: _flicker.value),
          ),
        ),
      ),
    );
  }
}

class _LanternPainter extends CustomPainter {
  final double lit; // 0 spenta, 1 accesa
  final double t;
  _LanternPainter({required this.lit, required this.t});

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    const brass = Color(0xFFB08A4E);
    final stroke = Paint()
      ..color = brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final flick = 0.85 + 0.15 * math.sin(t * math.pi * 2 * 3) * math.sin(t * math.pi * 2 * 1.7);
    // alone
    if (lit > 0) {
      c.drawCircle(Offset(w / 2, h * 0.55), w * 1.2 * lit, Paint()
        ..shader = RadialGradient(colors: [const Color(0xFFFFC56B).withValues(alpha: 0.45 * lit * flick), const Color(0x00FFC56B)])
            .createShader(Rect.fromCircle(center: Offset(w / 2, h * 0.55), radius: w * 1.2)));
    }
    c.drawLine(Offset(w / 2, 0), Offset(w / 2, h * 0.08), Paint()
      ..color = const Color(0xFF8A7A62)
      ..strokeWidth = 1.2);
    c.drawCircle(Offset(w / 2, h * 0.11), w * 0.08, stroke);
    final top = Path()
      ..moveTo(w * 0.12, h * 0.27)
      ..lineTo(w * 0.28, h * 0.17)
      ..lineTo(w * 0.72, h * 0.17)
      ..lineTo(w * 0.88, h * 0.27)
      ..close();
    c.drawPath(top, Paint()..color = const Color(0xFF3A2E24));
    c.drawPath(top, stroke);
    final body = RRect.fromLTRBR(w * 0.16, h * 0.27, w * 0.84, h * 0.82, const Radius.circular(2));
    final glass = Color.lerp(const Color(0xFF2A221C), const Color(0xFFFFD58A), lit * 0.75 * flick)!;
    c.drawRRect(body, Paint()..color = glass);
    c.drawRRect(body, stroke);
    c.drawLine(Offset(w / 2, h * 0.27), Offset(w / 2, h * 0.82), stroke..strokeWidth = 1);
    // fiamma
    if (lit > 0.05) {
      final fh = h * 0.26 * lit * flick, cx = w / 2 + math.sin(t * math.pi * 2 * 2) * w * 0.02, by = h * 0.72;
      c.drawPath(
          Path()
            ..moveTo(cx, by - fh)
            ..cubicTo(cx + w * 0.16, by - fh * 0.5, cx + w * 0.12, by, cx, by)
            ..cubicTo(cx - w * 0.12, by, cx - w * 0.16, by - fh * 0.5, cx, by - fh),
          Paint()..color = const Color(0xFFF2A23A));
      c.drawOval(Rect.fromCenter(center: Offset(cx, by - fh * 0.3), width: w * 0.1, height: fh * 0.45), Paint()..color = const Color(0xFFFCE3A0));
    }
    final base = Path()
      ..moveTo(w * 0.08, h * 0.82)
      ..lineTo(w * 0.92, h * 0.82)
      ..lineTo(w * 0.8, h * 0.94)
      ..lineTo(w * 0.2, h * 0.94)
      ..close();
    c.drawPath(base, Paint()..color = const Color(0xFF3A2E24));
    c.drawPath(base, stroke..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(_LanternPainter old) => old.lit != lit || old.t != t;
}
