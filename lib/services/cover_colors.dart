import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Calcola colore del dorso e del titolo partendo dalla copertina.
class CoverColors {
  static const fallback = (0xFF7A1E2E, 0xFFC9A55A);

  static Future<(int, int)> fromBytes(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return fallback;
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 48);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return fallback;
      final px = data.buffer.asUint8List();

      // Raggruppa i colori (4 bit per canale) e conta.
      final counts = <int, int>{};
      final sums = <int, List<int>>{};
      for (var i = 0; i + 3 < px.length; i += 4) {
        if (px[i + 3] < 128) continue;
        final r = px[i], g = px[i + 1], b = px[i + 2];
        final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
        counts[key] = (counts[key] ?? 0) + 1;
        final s = sums.putIfAbsent(key, () => [0, 0, 0]);
        s[0] += r;
        s[1] += g;
        s[2] += b;
      }
      if (counts.isEmpty) return fallback;
      final buckets = counts.keys.map((k) {
        final s = sums[k]!;
        final n = counts[k]!;
        final c = Color.fromARGB(255, s[0] ~/ n, s[1] ~/ n, s[2] ~/ n);
        return (c, n);
      }).toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
      final top = buckets.take(24).toList();

      // Dorso: colore frequente, scuro e un po' saturo.
      Color spine = top.first.$1;
      double best = -1;
      for (final (c, n) in top) {
        final hsl = HSLColor.fromColor(c);
        final darkBonus = hsl.lightness < 0.5 ? 1.0 : 0.4;
        final score = n * (0.4 + hsl.saturation) * darkBonus;
        if (score > best) {
          best = score;
          spine = c;
        }
      }
      var sh = HSLColor.fromColor(spine);
      if (sh.lightness > 0.42) sh = sh.withLightness(0.32);
      if (sh.lightness < 0.12) sh = sh.withLightness(0.16);
      spine = sh.toColor();

      // Testo: il colore della copertina più leggibile sopra il dorso.
      Color text = const Color(0xFFE9D9A8);
      double bestC = 0;
      for (final (c, _) in top) {
        final contrast = _contrast(c, spine);
        final hsl = HSLColor.fromColor(c);
        final score = contrast * (0.6 + hsl.saturation * 0.6);
        if (contrast >= 3.5 && score > bestC) {
          bestC = score;
          text = c;
        }
      }
      if (bestC == 0) {
        text = spine.computeLuminance() > 0.3 ? const Color(0xFF2A2420) : const Color(0xFFF1E3B8);
      }
      return (spine.toARGB32(), text.toARGB32());
    } catch (_) {
      return fallback;
    }
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance() + 0.05;
    final lb = b.computeLuminance() + 0.05;
    return la > lb ? la / lb : lb / la;
  }
}
