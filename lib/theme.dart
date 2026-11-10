import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette ispirata allo stile "carta e mattone".
class LK {
  static const paper = Color(0xFFFAF7F2);
  static const ink = Color(0xFF2A2420);
  static const muted = Color(0xFF6B5F57);
  static const accent = Color(0xFF9A3F2B);
  static const accentDark = Color(0xFF7A2F1F);
  static const bordeaux = Color(0xFF7A1E2E);
  static const gold = Color(0xFFC9A55A);
  static const parchment = Color(0xFFF1E3B8);
  static const parchmentBorder = Color(0xFFDCC58A);
  static const line = Color(0xFFEDE6DC);
  static const card = Colors.white;
  static const shelf = Color(0xFF8A6A52);
  static const shelfDark = Color(0xFF6B503D);

  static TextStyle display(double size, {Color color = ink, FontStyle? style, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.playfairDisplay(fontSize: size, color: color, fontStyle: style, fontWeight: weight);

  static TextStyle body(double size, {Color color = ink, FontStyle? style, double? height}) =>
      GoogleFonts.lora(fontSize: size, color: color, fontStyle: style, height: height);

  static TextStyle label(double size, {Color color = muted, double spacing = 1.6}) =>
      GoogleFonts.montserrat(fontSize: size, color: color, fontWeight: FontWeight.w700, letterSpacing: spacing);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: paper),
      scaffoldBackgroundColor: paper,
    );
    return base.copyWith(
      textTheme: GoogleFonts.loraTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink),
      sliderTheme: base.sliderTheme.copyWith(activeTrackColor: accent, thumbColor: accent, inactiveTrackColor: line),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: ink),
    );
  }
}

/// Temi di lettura.
class ReaderTheme {
  final String name;
  final Color bg, ink, muted, accent, line;
  const ReaderTheme(this.name, this.bg, this.ink, this.muted, this.accent, this.line);

  static const all = [
    ReaderTheme('Carta', Color(0xFFFAF7F2), Color(0xFF2A2420), Color(0xFF6B5F57), Color(0xFF9A3F2B), Color(0xFFEAE2D7)),
    ReaderTheme('Pergamena', Color(0xFFF3E6C4), Color(0xFF33281A), Color(0xFF5F4E33), Color(0xFF8A3524), Color(0xFFE0CC9C)),
    ReaderTheme('Notte', Color(0xFF1D1A18), Color(0xFFE8DED0), Color(0xFFA99C8E), Color(0xFFD98B6A), Color(0xFF34302C)),
  ];

  static ReaderTheme byName(String n) => all.firstWhere((t) => t.name == n, orElse: () => all.first);
}

TextStyle readerFont(String font, double size, Color color, double height) {
  switch (font) {
    case 'Playfair':
      return GoogleFonts.playfairDisplay(fontSize: size, color: color, height: height);
    case 'Sans':
      return GoogleFonts.getFont('Source Sans 3', fontSize: size, color: color, height: height);
    default:
      return GoogleFonts.lora(fontSize: size, color: color, height: height);
  }
}
