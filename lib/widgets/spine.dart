import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/book.dart';

class SpineView extends StatelessWidget {
  final String title;
  final Color color;
  final Color textColor;
  final String style;
  final double heightScale;
  final double widthScale;
  final double baseHeight;
  final String? volume; // numero del volume in basso
  final String? author;
  final double wear; // 0 – 1: usura dei libri più letti
  final int seed;

  const SpineView({
    super.key,
    required this.title,
    required this.color,
    required this.textColor,
    required this.style,
    this.heightScale = 1,
    this.widthScale = 1,
    this.baseHeight = 200,
    this.volume,
    this.author,
    this.wear = 0,
    this.seed = 0,
  });

  factory SpineView.of(Book b, {double baseHeight = 200}) {
    String? vol;
    if (b.seriesIndex != null) {
      final v = b.seriesIndex!;
      vol = v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    }
    final author = b.author.trim().isEmpty ? null : b.author.trim().split(RegExp(r'\s+')).last;
    return SpineView(
      title: b.title,
      color: Color(b.spineColor),
      textColor: Color(b.spineTextColor),
      style: b.spineStyle,
      heightScale: b.spineHeight,
      widthScale: b.spineWidth,
      baseHeight: baseHeight,
      volume: vol,
      author: author,
      wear: (b.progress * 0.7).clamp(0.0, 0.6),
      seed: b.id.hashCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = 42.0 * widthScale * baseHeight / 200;
    final h = baseHeight * heightScale;
    final dark = Color.lerp(color, Colors.black, 0.28)!;
    final light = Color.lerp(color, Colors.white, 0.10)!;
    final diamond = _Diamond(color: textColor, size: w * 0.2);
    final band = Container(width: w * 0.62, height: 2, color: textColor);
    final bands = Column(mainAxisSize: MainAxisSize.min, children: [band, const SizedBox(height: 3), band]);

    List<Widget> top = [], bottom = [];
    switch (style) {
      case 'Tomo':
        top = [diamond];
        bottom = [diamond];
        break;
      case 'Classico':
        top = [bands, SizedBox(height: w * 0.15), diamond];
        bottom = [diamond, SizedBox(height: w * 0.15), bands];
        break;
      case 'Grimorio':
        top = [diamond, const SizedBox(height: 4), diamond];
        bottom = [diamond, const SizedBox(height: 4), diamond];
        break;
      default:
        break;
    }
    if (volume != null && baseHeight >= 120) {
      bottom = [
        Text(volume!, style: GoogleFonts.playfairDisplay(color: textColor, fontSize: math.max(9, w * 0.3), fontWeight: FontWeight.w700)),
        SizedBox(height: w * 0.12),
        ...bottom,
      ];
    }

    final titleStyle = GoogleFonts.playfairDisplay(
      color: Colors.white,
      fontSize: math.max(9, w * 0.3),
      fontWeight: FontWeight.w600,
      letterSpacing: 1.6,
    );
    final showAuthor = author != null && baseHeight >= 150 && h > 160;

    // Effetto "oro a caldo": riflesso che attraversa le lettere.
    Widget foil(Widget child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(textColor, Colors.black, 0.18)!,
              Color.lerp(textColor, Colors.white, 0.45)!,
              textColor,
              Color.lerp(textColor, Colors.black, 0.12)!,
              Color.lerp(textColor, Colors.white, 0.3)!,
            ],
            stops: const [0, 0.3, 0.5, 0.75, 1],
          ).createShader(r),
          child: child,
        );

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3), bottom: Radius.circular(1)),
        gradient: LinearGradient(colors: [light, color, color, dark], stops: const [0, 0.15, 0.78, 1]),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(1, 2))],
      ),
      child: Stack(
        children: [
          if (style == 'Nervato')
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (_) => Container(height: 4, color: dark.withValues(alpha: 0.55))),
              ),
            ),
          if (style == 'Grimorio')
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(border: Border.all(color: textColor.withValues(alpha: 0.8), width: 1)),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: w * 0.32),
            child: Column(
              children: [
                ...top,
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: w * 0.2),
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Center(
                        child: foil(
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                              child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                            ),
                            if (showAuthor) ...[
                              Text('  ·  ', style: titleStyle.copyWith(fontSize: titleStyle.fontSize! * 0.7)),
                              Text(author!, maxLines: 1, style: titleStyle.copyWith(fontSize: titleStyle.fontSize! * 0.72, fontStyle: FontStyle.italic, letterSpacing: 0.6)),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
                ...bottom,
              ],
            ),
          ),
          if (wear > 0.02) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _WearPainter(wear, seed)))),
        ],
      ),
    );
  }
}

class _WearPainter extends CustomPainter {
  final double wear;
  final int seed;
  _WearPainter(this.wear, this.seed);

  @override
  void paint(Canvas c, Size s) {
    final r = math.Random(seed);
    final p = Paint()
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    // graffi chiari
    for (var i = 0; i < (wear * 24).round(); i++) {
      final x = r.nextDouble() * s.width, y = r.nextDouble() * s.height;
      p.color = Colors.white.withValues(alpha: 0.10 + wear * 0.2 * r.nextDouble());
      c.drawLine(Offset(x, y), Offset(x + (r.nextDouble() - 0.5) * 8, y + r.nextDouble() * 10), p);
    }
    // angoli consumati
    final edge = Paint()..color = Colors.black.withValues(alpha: wear * 0.35);
    c.drawRect(Rect.fromLTWH(0, 0, s.width, 2 + wear * 3), edge);
    c.drawRect(Rect.fromLTWH(0, s.height - 2 - wear * 3, s.width, 2 + wear * 3), edge);
  }

  @override
  bool shouldRepaint(_WearPainter old) => old.wear != wear || old.seed != seed;
}

class _Diamond extends StatelessWidget {
  final Color color;
  final double size;
  const _Diamond({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 1.5,
        height: size * 1.5,
        child: Center(
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: size, height: size, decoration: BoxDecoration(border: Border.all(color: color, width: 1))),
          ),
        ),
      );
}

/// Legni per gli scaffali: ogni serie ne ha uno diverso.
class Wood {
  final String name;
  final Color base, dark, grain;
  const Wood(this.name, this.base, this.dark, this.grain);

  static const all = [
    Wood('Noce', Color(0xFF6E4B33), Color(0xFF4E3322), Color(0xFF3E2718)),
    Wood('Quercia', Color(0xFFA9825A), Color(0xFF86633F), Color(0xFF6E4F30)),
    Wood('Mogano', Color(0xFF7E3B26), Color(0xFF5A2516), Color(0xFF461A0E)),
    Wood('Ciliegio', Color(0xFF9A5A3A), Color(0xFF743F26), Color(0xFF5E3019)),
    Wood('Ebano', Color(0xFF3E3430), Color(0xFF28201C), Color(0xFF181210)),
    Wood('Acero', Color(0xFFC29A6A), Color(0xFF9C774C), Color(0xFF85623A)),
  ];

  static Wood forKey(String key) => all[key.hashCode.abs() % all.length];
}

/// Asse di legno dello scaffale, con venature.
class ShelfBoard extends StatelessWidget {
  final Wood? wood;
  const ShelfBoard({super.key, this.wood});

  @override
  Widget build(BuildContext context) {
    final w = wood ?? Wood.all.first;
    return Container(
      height: 16,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(color: w.dark, offset: const Offset(0, 5)),
          const BoxShadow(color: Color(0x30000000), blurRadius: 14, offset: Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: CustomPaint(painter: _GrainPainter(w)),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  final Wood wood;
  _GrainPainter(this.wood);

  @override
  void paint(Canvas c, Size s) {
    final rect = Offset.zero & s;
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(wood.base, Colors.white, 0.12)!, wood.base, Color.lerp(wood.base, wood.dark, 0.5)!],
        ).createShader(rect),
    );
    final r = math.Random(wood.name.hashCode);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var i = 0; i < 7; i++) {
      final y0 = 2 + r.nextDouble() * (s.height - 4);
      final amp = 0.6 + r.nextDouble() * 1.6;
      final freq = 0.008 + r.nextDouble() * 0.02;
      final phase = r.nextDouble() * 6;
      p.color = wood.grain.withValues(alpha: 0.25 + r.nextDouble() * 0.3);
      final path = Path()..moveTo(0, y0);
      for (double x = 0; x <= s.width; x += 6) {
        path.lineTo(x, y0 + math.sin(x * freq + phase) * amp);
      }
      c.drawPath(path, p);
    }
    // nodi del legno
    for (var i = 0; i < 2; i++) {
      final cx = r.nextDouble() * s.width, cy = s.height / 2 + (r.nextDouble() - 0.5) * 4;
      c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: 14, height: 5), p..color = wood.grain.withValues(alpha: 0.45));
    }
    c.drawLine(Offset(0, 0.5), Offset(s.width, 0.5), Paint()..color = Colors.white.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.wood != wood;
}
