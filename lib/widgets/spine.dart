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

  const SpineView({
    super.key,
    required this.title,
    required this.color,
    required this.textColor,
    required this.style,
    this.heightScale = 1,
    this.widthScale = 1,
    this.baseHeight = 200,
  });

  factory SpineView.of(Book b, {double baseHeight = 200}) => SpineView(
        title: b.title,
        color: Color(b.spineColor),
        textColor: Color(b.spineTextColor),
        style: b.spineStyle,
        heightScale: b.spineHeight,
        widthScale: b.spineWidth,
        baseHeight: baseHeight,
      );

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
        top = [diamond, SizedBox(height: 4), diamond];
        bottom = [diamond, SizedBox(height: 4), diamond];
        break;
      default:
        break;
    }

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
                        child: Text(
                          title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(
                            color: textColor,
                            fontSize: math.max(9, w * 0.3),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ...bottom,
              ],
            ),
          ),
        ],
      ),
    );
  }
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

/// Asse di legno dello scaffale.
class ShelfBoard extends StatelessWidget {
  const ShelfBoard({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFF8A6A52),
          borderRadius: BorderRadius.circular(2),
          boxShadow: const [
            BoxShadow(color: Color(0xFF6B503D), offset: Offset(0, 5)),
            BoxShadow(color: Color(0x30000000), blurRadius: 14, offset: Offset(0, 10)),
          ],
        ),
      );
}
