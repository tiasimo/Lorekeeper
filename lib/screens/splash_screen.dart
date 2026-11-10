import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/library_store.dart';
import 'library_screen.dart';

/// Schermata di caricamento: la lanterna si accende e rivela il nome.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _main = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  late final AnimationController _flicker = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final AnimationController _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.wait([_main.forward(), LibraryStore.I.load()]);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _exit.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, __, ___) => const LibraryScreen(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _main.dispose();
    _flicker.dispose();
    _exit.dispose();
    super.dispose();
  }

  double _iv(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1714),
      body: AnimatedBuilder(
        animation: Listenable.merge([_main, _flicker, _exit]),
        builder: (context, _) {
          final t = _main.value;
          final f = _flicker.value * 2 * math.pi;
          final glow = Curves.easeOut.transform(_iv(t, 0.08, 0.4));
          final flameOn = Curves.easeOutBack.transform(_iv(t, 0.05, 0.22));
          final title = Curves.easeOut.transform(_iv(t, 0.35, 0.72));
          final sub = _iv(t, 0.6, 0.85);
          final flick = 1 + 0.05 * math.sin(f * 3) + 0.03 * math.sin(f * 7);
          final out = 1 - Curves.easeIn.transform(_exit.value);
          return Opacity(
            opacity: out,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: -220,
                        top: -180,
                        width: 560,
                        height: 560,
                        child: Opacity(
                          opacity: glow * (0.92 + 0.08 * math.sin(f * 2)),
                          child: Transform.scale(
                            scale: 0.2 + 0.8 * glow,
                            child: Container(
                              width: 560,
                              height: 560,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [Color(0x73F7C86E), Color(0x2EE28C3C), Color(0x001C1714)], stops: [0, 0.38, 0.7]),
                              ),
                            ),
                          ),
                        ),
                      ),
                  Transform.rotate(
                    angle: 0.035 * math.sin(f),
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 120,
                      height: 200,
                      child: Stack(children: [
                        const Positioned.fill(child: CustomPaint(painter: _LanternPainter())),
                        Positioned(
                          left: 49,
                          top: 74,
                          child: Transform.scale(
                            alignment: Alignment.bottomCenter,
                            scaleX: flameOn * (2 - flick),
                            scaleY: flameOn * flick,
                            child: const SizedBox(width: 22, height: 44, child: CustomPaint(painter: _FlamePainter())),
                          ),
                        ),
                      ]),
                    ),
                  ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Opacity(
                    opacity: title,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 6 * (1 - title) + 0.001, sigmaY: 6 * (1 - title) + 0.001),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.playfairDisplay(fontSize: 44, fontWeight: FontWeight.w700, color: const Color(0xFFF4E6C8), letterSpacing: 14 * (1 - title)),
                          children: const [
                            TextSpan(text: 'Lore'),
                            TextSpan(text: 'keeper', style: TextStyle(fontStyle: FontStyle.italic, color: Color(0xFFE8A25A))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: sub,
                    child: Text('il custode delle tue storie', style: GoogleFonts.lora(fontSize: 15, fontStyle: FontStyle.italic, color: const Color(0xFFBFAE92))),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LanternPainter extends CustomPainter {
  const _LanternPainter();
  @override
  void paint(Canvas c, Size s) {
    const brass = Color(0xFFB08A4E);
    final stroke = Paint()
      ..color = brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final dark = Paint()..color = const Color(0xFF3A2E24);
    c.drawLine(const Offset(60, 0), const Offset(60, 16), Paint()..color = const Color(0xFF8A7A62)..strokeWidth = 2);
    c.drawCircle(const Offset(60, 24), 8, stroke);
    final top = Path()
      ..moveTo(30, 52)
      ..lineTo(42, 32)
      ..lineTo(78, 32)
      ..lineTo(90, 52)
      ..close();
    c.drawPath(top, dark);
    c.drawPath(top, stroke..strokeWidth = 2);
    final body = RRect.fromLTRBR(32, 52, 88, 152, const Radius.circular(4));
    c.drawRRect(body, Paint()..color = const Color(0xFF2A221C));
    c.drawRRect(RRect.fromLTRBR(38, 58, 82, 146, const Radius.circular(2)), Paint()..color = const Color(0x2EF7D79A));
    c.drawRRect(body, stroke..strokeWidth = 2.5);
    c.drawLine(const Offset(60, 52), const Offset(60, 152), stroke..strokeWidth = 2);
    c.drawLine(const Offset(32, 102), const Offset(88, 102), stroke);
    final base = Path()
      ..moveTo(26, 152)
      ..lineTo(94, 152)
      ..lineTo(86, 170)
      ..lineTo(34, 170)
      ..close();
    c.drawPath(base, dark);
    c.drawPath(base, stroke);
    final knob = Path()
      ..moveTo(48, 170)
      ..lineTo(72, 170)
      ..lineTo(66, 182)
      ..lineTo(54, 182)
      ..close();
    c.drawPath(knob, Paint()..color = brass);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlamePainter extends CustomPainter {
  const _FlamePainter();
  @override
  void paint(Canvas c, Size s) {
    final outer = Path()
      ..moveTo(11, 0)
      ..cubicTo(20, 14, 22, 26, 11, 44)
      ..cubicTo(0, 26, 2, 14, 11, 0)
      ..close();
    final inner = Path()
      ..moveTo(11, 12)
      ..cubicTo(16, 22, 17, 30, 11, 44)
      ..cubicTo(5, 30, 6, 22, 11, 12)
      ..close();
    c.drawPath(outer, Paint()..color = const Color(0xFFF2A23A));
    c.drawPath(inner, Paint()..color = const Color(0xFFFCE3A0));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
