import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/library_store.dart';
import '../services/weather.dart';
import '../theme.dart';

/// Una finestrella ad arco nella Home: fuori c'è il tempo vero della tua città
/// (o, senza città, il cielo dell'ora del giorno).
class HomeWindow extends StatefulWidget {
  const HomeWindow({super.key});
  @override
  State<HomeWindow> createState() => _HomeWindowState();
}

class _HomeWindowState extends State<HomeWindow> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Weather.I.addListener(_changed);
    Weather.I.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) Weather.I.refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Weather.I.removeListener(_changed);
    _a.dispose();
    super.dispose();
  }

  void _info() {
    final w = Weather.I.now;
    final city = LibraryStore.I.app.weatherCity;
    final msg = w == null
        ? (city == null ? 'Scegli la tua città in Impostazioni → Atmosfera per vedere il tempo vero dalla finestra.' : 'Non riesco a sapere che tempo fa a ${city.split(',').first}.')
        : '${w.label} a ${city!.split(',').first} · ${w.temp.round()}°';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final w = Weather.I.now;
    final h = DateTime.now().hour;
    final day = w?.day ?? (h >= 7 && h < 19);
    return GestureDetector(
      onTap: _info,
      child: SizedBox(
        width: 34,
        height: 46,
        child: AnimatedBuilder(
          animation: _a,
          builder: (_, __) => CustomPaint(painter: _WindowPainter(w?.sky ?? Sky.clear, day, h, _a.value, LK.dark)),
        ),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  final Sky sky;
  final bool day;
  final int hour;
  final double t;
  final bool dark;
  _WindowPainter(this.sky, this.day, this.hour, this.t, this.dark);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final arch = Path()
      ..moveTo(0, h)
      ..lineTo(0, w / 2)
      ..arcToPoint(Offset(w, w / 2), radius: Radius.circular(w / 2))
      ..lineTo(w, h)
      ..close();
    final inner = Path()
      ..moveTo(3, h - 3)
      ..lineTo(3, w / 2)
      ..arcToPoint(Offset(w - 3, w / 2), radius: Radius.circular(w / 2 - 3))
      ..lineTo(w - 3, h - 3)
      ..close();
    // cielo
    final dusk = hour == 18 || hour == 19 || hour == 6 || hour == 7;
    final grey = sky == Sky.cloudy || sky == Sky.rain || sky == Sky.storm || sky == Sky.fog || sky == Sky.snow;
    List<Color> colors;
    if (!day) {
      colors = grey ? const [Color(0xFF1E2229), Color(0xFF2E333B)] : const [Color(0xFF0E1630), Color(0xFF263A63)];
    } else if (dusk && !grey) {
      colors = const [Color(0xFF6E7FB8), Color(0xFFF0A56B)];
    } else {
      colors = grey ? const [Color(0xFF8E98A3), Color(0xFFB9C1C8)] : const [Color(0xFF5AA3E0), Color(0xFFBFE1F5)];
    }
    c.save();
    c.clipPath(inner);
    c.drawRect(Offset.zero & s, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(Offset.zero & s));
    final r = math.Random(3);
    // sole, luna, stelle
    if (!grey) {
      if (day) {
        c.drawCircle(Offset(w * 0.68, h * 0.3), 6, Paint()..color = const Color(0xFFFFE08A));
        c.drawCircle(Offset(w * 0.68, h * 0.3), 9, Paint()..color = const Color(0x44FFE08A));
      } else {
        for (var i = 0; i < 9; i++) {
          final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin((t + i * 0.13) * math.pi * 2));
          c.drawCircle(Offset(r.nextDouble() * w, r.nextDouble() * h * 0.7), 0.8, Paint()..color = Colors.white.withValues(alpha: tw));
        }
        c.drawCircle(Offset(w * 0.66, h * 0.3), 5.5, Paint()..color = const Color(0xFFF2EBD3));
        c.drawCircle(Offset(w * 0.72, h * 0.27), 4.8, Paint()..color = colors.first);
      }
    }
    // colline
    c.drawPath(
        Path()
          ..moveTo(0, h * 0.82)
          ..quadraticBezierTo(w * 0.3, h * 0.7, w * 0.6, h * 0.8)
          ..quadraticBezierTo(w * 0.8, h * 0.86, w, h * 0.76)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close(),
        Paint()..color = sky == Sky.snow ? const Color(0xFFE8EEF2) : (day ? const Color(0xFF6E8F5A) : const Color(0xFF1F2B24)));
    // nuvole
    if (grey || sky == Sky.clear && day) {
      final n = grey ? 3 : 1;
      for (var i = 0; i < n; i++) {
        final x = ((t + i / n) % 1) * (w + 30) - 15;
        final y = h * (0.22 + i * 0.12);
        final p = Paint()..color = (day ? Colors.white : const Color(0xFF4A505A)).withValues(alpha: grey ? 0.85 : 0.7);
        c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 16, height: 7), p);
        c.drawOval(Rect.fromCenter(center: Offset(x + 5, y - 3), width: 10, height: 7), p);
      }
    }
    // pioggia, neve, nebbia
    if (sky == Sky.rain || sky == Sky.storm) {
      final p = Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..strokeWidth = 0.9;
      for (var i = 0; i < 18; i++) {
        final x = r.nextDouble() * w;
        final y = ((r.nextDouble() + t * 6) % 1) * (h + 8) - 4;
        c.drawLine(Offset(x, y), Offset(x - 1.5, y + 5), p);
      }
      if (sky == Sky.storm && (t * 6 % 1) < 0.04) c.drawRect(Offset.zero & s, Paint()..color = Colors.white.withValues(alpha: 0.6));
    } else if (sky == Sky.snow) {
      for (var i = 0; i < 16; i++) {
        final x = r.nextDouble() * w + math.sin((t * 2 + i) * math.pi) * 2;
        final y = ((r.nextDouble() + t * 1.5) % 1) * h;
        c.drawCircle(Offset(x, y), 1.1, Paint()..color = Colors.white);
      }
    } else if (sky == Sky.fog) {
      for (var i = 0; i < 3; i++) {
        c.drawRect(Rect.fromLTWH(0, h * (0.45 + i * 0.15), w, 5), Paint()..color = Colors.white.withValues(alpha: 0.35));
      }
    }
    // luce calda riflessa sul vetro di sera
    if (!day) c.drawRect(Offset.zero & s, Paint()..color = const Color(0x14FFB347));
    c.restore();
    // cornice e croce
    final frame = Paint()
      ..color = dark ? const Color(0xFF8A6A4A) : const Color(0xFF6B4A2B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    c.drawPath(arch, frame);
    final bar = Paint()
      ..color = frame.color
      ..strokeWidth = 1.6;
    c.drawLine(Offset(w / 2, 3), Offset(w / 2, h - 2), bar);
    c.drawLine(Offset(2, h * 0.55), Offset(w - 2, h * 0.55), bar);
    // davanzale
    c.drawRect(Rect.fromLTWH(-3, h - 3, w + 6, 3), Paint()..color = frame.color);
  }

  @override
  bool shouldRepaint(_WindowPainter o) => true;
}
