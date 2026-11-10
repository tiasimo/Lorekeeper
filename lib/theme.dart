import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette ispirata allo stile "carta e mattone".
class LK {
  /// Modalità scura attiva (impostata da LorekeeperApp).
  static bool dark = false;

  static Color _c(int light, int night) => Color(dark ? night : light);

  static Color get paper => _c(0xFFFAF7F2, 0xFF1A1715);
  static Color get ink => _c(0xFF2A2420, 0xFFEDE3D3);
  static Color get muted => _c(0xFF6B5F57, 0xFFA99C8E);
  static Color get accent => _c(0xFF9A3F2B, 0xFFD9784F);
  static Color get accentDark => _c(0xFF7A2F1F, 0xFFB5583A);
  static Color get accentSoft => _c(0xFFD9B3A7, 0xFF6E3A2C);
  static const bordeaux = Color(0xFF7A1E2E);
  static const gold = Color(0xFFC9A55A);
  static Color get parchment => _c(0xFFF1E3B8, 0xFF2E2719);
  static Color get parchmentBorder => _c(0xFFDCC58A, 0xFF5A4A2E);
  static Color get parchmentInk => _c(0xFF5C4A2A, 0xFFD9C59A);
  static Color get line => _c(0xFFEDE6DC, 0xFF34302C);
  static Color get border => _c(0xFFE6DED3, 0xFF3E3832);
  static Color get card => _c(0xFFFFFFFF, 0xFF24201D);
  static Color get onAccent => _c(0xFFFFFFFF, 0xFF1A1715);
  static Color get navOff => _c(0xFFFBE9E2, 0xFF2A1A14);
  static const shelf = Color(0xFF8A6A52);
  static const shelfDark = Color(0xFF6B503D);

  static TextStyle display(double size, {Color? color, FontStyle? style, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.playfairDisplay(fontSize: size, color: color ?? ink, fontStyle: style, fontWeight: weight);

  static TextStyle body(double size, {Color? color, FontStyle? style, double? height}) =>
      GoogleFonts.lora(fontSize: size, color: color ?? ink, fontStyle: style, height: height);

  static TextStyle label(double size, {Color? color, double spacing = 1.6}) =>
      GoogleFonts.montserrat(fontSize: size, color: color ?? muted, fontWeight: FontWeight.w700, letterSpacing: spacing);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: paper, brightness: dark ? Brightness.dark : Brightness.light),
      scaffoldBackgroundColor: paper,
      dividerColor: line,
    );
    return base.copyWith(
      textTheme: GoogleFonts.loraTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink),
      sliderTheme: base.sliderTheme.copyWith(activeTrackColor: accent, thumbColor: accent, inactiveTrackColor: line),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: dark ? card : const Color(0xFF2A2420)),
      iconTheme: IconThemeData(color: ink),
      listTileTheme: ListTileThemeData(iconColor: ink, textColor: ink),
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
