import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'epub.dart';

/// Un blocco dentro una pagina.
class PageBlock {
  final List<TextSeg> segs;
  final int level;
  final bool cut; // paragrafo spezzato: niente spazio sotto
  final String? image;
  final double imageHeight;
  final String? chapterTitle;
  final String? dropCap; // capolettera: la lettera grande a sinistra
  final double capWidth;
  final bool ornament; // separatore di scena disegnato
  const PageBlock({
    this.segs = const [],
    this.level = 0,
    this.cut = false,
    this.image,
    this.imageHeight = 0,
    this.chapterTitle,
    this.dropCap,
    this.capWidth = 0,
    this.ornament = false,
  });
}

class PageLayout {
  final List<PageBlock> blocks = [];
}

/// Stili condivisi tra misura e disegno: devono coincidere al pixel.
class PageStyle {
  final TextStyle base;
  final ReaderTheme theme;
  final TextScaler scaler;
  final TextAlign align;
  PageStyle(TextStyle base, this.theme, this.scaler, {this.align = TextAlign.justify}) : base = _fix(base);

  /// Il tema dell'app aggiunge spaziatura tra le lettere: qui la azzero perché
  /// misura e disegno devono essere identici.
  static TextStyle _fix(TextStyle s) => s.copyWith(letterSpacing: s.letterSpacing ?? 0, wordSpacing: s.wordSpacing ?? 0);

  double get gap => (base.fontSize ?? 18) * 0.75;
  TextStyle heading(int level) => _fix(LK.display(level <= 2 ? 21 : 18, color: theme.ink));
  TextStyle get title => LK.display(24, color: theme.ink).copyWith(
        height: 1.25,
        letterSpacing: 0.6,
        fontFeatures: const [FontFeature.enable('smcp'), FontFeature.oldstyleFigures()],
      );
  static const capLines = 3;
  double get lineHeight => (base.fontSize ?? 18) * (base.height ?? 1.4);
  double get capBox => lineHeight * capLines * 0.94; // prima della scala del testo di sistema
  TextStyle get cap => _fix(LK.display(capBox * 1.3, color: theme.accent).copyWith(height: 1 / 1.3));
  static const ornamentHeight = 52.0;
  static final _ornament = RegExp(r'^[\s\*•·◆◇◊~#=_+\-–—⁂❖✦✧○●□■◦°※†‡§]+$');
  static bool isOrnament(String s) => s.trim().isNotEmpty && s.trim().length <= 24 && _ornament.hasMatch(s);
  static const titleTop = 36.0; // simbolo + spazio sopra il titolo
  static const titleBottom = 26.0;
  static const headingPad = EdgeInsets.only(top: 10, bottom: 14);

  static TextSpan span(List<TextSeg> segs) => TextSpan(children: [
        for (final s in segs)
          TextSpan(
            text: s.text,
            style: TextStyle(fontStyle: s.italic ? FontStyle.italic : null, fontWeight: s.bold ? FontWeight.w700 : null),
          ),
      ]);
}

String _norm(String s) => s.toLowerCase().replaceAll('\u00AD', '').replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

/// Toglie dall'inizio del capitolo le intestazioni che ripetono il titolo
/// (es. "1" e "La luce in fondo al tunnel" sotto "1. La luce in fondo al tunnel").
List<Para> skipTitleRepeats(List<Para> paras, String title) {
  final t = _norm(title);
  final words = t.split(' ').toSet();
  var i = 0;
  while (i < paras.length && i < 4) {
    final p = paras[i];
    if (p.image != null) {
      i++;
      continue;
    }
    final n = _norm(p.plain);
    final short = p.plain.length <= 80;
    final repeat = n.isNotEmpty && short && (t.contains(n) || n.contains(t) || n.split(' ').every(words.contains));
    if ((p.level > 0 || short) && repeat) {
      i++;
      continue;
    }
    break;
  }
  if (i == 0) return paras;
  // le immagini in testa restano
  return [...paras.sublist(0, i).where((p) => p.image != null), ...paras.sublist(i)];
}

class Paginator {
  static List<PageLayout> paginate({
    required List<Para> paras,
    required String title,
    required Map<String, Size> imageSizes,
    required Size page,
    required PageStyle st,
  }) {
    final w = page.width;
    final h = page.height - 2;
    final pages = <PageLayout>[PageLayout()];
    var used = 0.0;

    void newPage() {
      pages.add(PageLayout());
      used = 0;
    }

    TextPainter measure(InlineSpan span, TextStyle style, TextAlign align, {double? width}) {
      return TextPainter(
        text: TextSpan(style: style, children: [span]),
        textAlign: align,
        textDirection: TextDirection.ltr,
        textScaler: st.scaler,
      )..layout(maxWidth: width ?? w);
    }

    var firstText = true;

    // Titolo del capitolo in cima alla prima pagina.
    final tp = measure(TextSpan(text: title), st.title, TextAlign.center);
    used = PageStyle.titleTop + tp.height + PageStyle.titleBottom;
    tp.dispose();
    pages.last.blocks.add(PageBlock(chapterTitle: title));

    for (final p in skipTitleRepeats(paras, title)) {
      // Illustrazione
      if (p.image != null) {
        final size = imageSizes[p.image!] ?? const Size(3, 4);
        var ih = w * size.height / size.width;
        if (ih > h) ih = h;
        if (used > 0 && used + ih > h) newPage();
        pages.last.blocks.add(PageBlock(image: p.image, imageHeight: ih));
        used += ih + st.gap;
        continue;
      }

      // Titolo interno
      if (p.level > 0) {
        final hp = measure(TextSpan(text: p.plain), st.heading(p.level), TextAlign.center);
        final hh = hp.height + PageStyle.headingPad.vertical;
        hp.dispose();
        if (used > 0 && used + hh > h) newPage();
        pages.last.blocks.add(PageBlock(segs: p.segs, level: p.level));
        used += hh;
        continue;
      }

      // Separatore di scena
      if (PageStyle.isOrnament(p.plain)) {
        if (used > 0 && used + PageStyle.ornamentHeight > h) newPage();
        pages.last.blocks.add(const PageBlock(ornament: true));
        used += PageStyle.ornamentHeight;
        continue;
      }

      // Paragrafo: se non entra lo spezzo a fine riga.
      var segs = p.segs;

      // Capolettera sul primo paragrafo del capitolo.
      final plain = p.plain;
      if (firstText && plain.length > 80 && RegExp(r'^\p{L}', unicode: true).hasMatch(plain)) {
        final capTp = measure(TextSpan(text: plain[0]), st.cap, TextAlign.left);
        final capW = capTp.width + 10;
        capTp.dispose();
        final capH = st.scaler.scale(st.capBox);
        final rest = _split(segs, 1).$2;
        final sp = measure(PageStyle.span(rest), st.base, st.align, width: w - capW);
        final lines = sp.computeLineMetrics();
        List<TextSeg> side = rest, tail = const [];
        var sideH = sp.height;
        if (lines.length > PageStyle.capLines) {
          final last = lines[PageStyle.capLines - 1];
          final pos = sp.getPositionForOffset(Offset(1, last.baseline - last.ascent / 2));
          final cutAt = sp.getLineBoundary(pos).end;
          final total = rest.fold<int>(0, (a, s) => a + s.text.length);
          if (cutAt > 0 && cutAt < total) {
            final parts = _split(rest, cutAt);
            side = parts.$1;
            tail = _trimLeft(parts.$2);
            sideH = 0;
            for (var i = 0; i < PageStyle.capLines; i++) {
              sideH += lines[i].height;
            }
          }
        }
        sp.dispose();
        final blockH = (capH > sideH ? capH : sideH) + (tail.isEmpty ? st.gap : 0);
        if (used > 0 && used + blockH > h) newPage();
        pages.last.blocks.add(PageBlock(segs: side, dropCap: plain[0], capWidth: capW, cut: tail.isNotEmpty));
        used += blockH;
        firstText = false;
        if (tail.isEmpty) continue;
        segs = tail;
      }
      firstText = false;
      var guard = 0;
      while (segs.isNotEmpty && guard++ < 200) {
        final pp = measure(PageStyle.span(segs), st.base, st.align);
        final ph = pp.height;
        if (used + ph <= h) {
          pages.last.blocks.add(PageBlock(segs: segs));
          used += ph + st.gap;
          pp.dispose();
          break;
        }
        final lines = pp.computeLineMetrics();
        var acc = 0.0;
        var fit = 0;
        for (final l in lines) {
          if (used + acc + l.height > h) break;
          acc += l.height;
          fit++;
        }
        if (fit == 0) {
          pp.dispose();
          if (used == 0) {
            // Riga più alta della pagina: la metto comunque.
            pages.last.blocks.add(PageBlock(segs: segs));
            newPage();
            break;
          }
          newPage();
          continue;
        }
        final last = lines[fit - 1];
        final pos = pp.getPositionForOffset(Offset(1, last.baseline - last.ascent / 2));
        final cutAt = pp.getLineBoundary(pos).end;
        pp.dispose();
        final total = segs.fold<int>(0, (a, s) => a + s.text.length);
        if (cutAt <= 0 || cutAt >= total) {
          pages.last.blocks.add(PageBlock(segs: segs));
          used += ph + st.gap;
          break;
        }
        final (head, tail) = _split(segs, cutAt);
        pages.last.blocks.add(PageBlock(segs: head, cut: true));
        newPage();
        segs = _trimLeft(tail);
      }
    }
    if (pages.length > 1 && pages.last.blocks.isEmpty) pages.removeLast();
    return pages;
  }

  static (List<TextSeg>, List<TextSeg>) _split(List<TextSeg> segs, int at) {
    final a = <TextSeg>[], b = <TextSeg>[];
    var pos = 0;
    for (final s in segs) {
      final end = pos + s.text.length;
      if (end <= at) {
        a.add(s);
      } else if (pos >= at) {
        b.add(s);
      } else {
        final k = at - pos;
        a.add(TextSeg(s.text.substring(0, k), italic: s.italic, bold: s.bold));
        b.add(TextSeg(s.text.substring(k), italic: s.italic, bold: s.bold));
      }
      pos = end;
    }
    return (a, b);
  }

  static List<TextSeg> _trimLeft(List<TextSeg> segs) {
    final out = [...segs];
    while (out.isNotEmpty) {
      final t = out.first.text.trimLeft();
      if (t.isEmpty) {
        out.removeAt(0);
      } else {
        out[0] = TextSeg(t, italic: out.first.italic, bold: out.first.bold);
        break;
      }
    }
    return out;
  }
}
