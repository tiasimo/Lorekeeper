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
  const PageBlock({this.segs = const [], this.level = 0, this.cut = false, this.image, this.imageHeight = 0, this.chapterTitle});
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
  const PageStyle(this.base, this.theme, this.scaler, {this.align = TextAlign.justify});

  double get gap => (base.fontSize ?? 18) * 0.75;
  TextStyle heading(int level) => LK.display(level <= 2 ? 21 : 18, color: theme.ink);
  TextStyle get title => LK.display(24, color: theme.ink).copyWith(height: 1.25);
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

    TextPainter measure(InlineSpan span, TextStyle style, TextAlign align) {
      return TextPainter(
        text: TextSpan(style: style, children: [span]),
        textAlign: align,
        textDirection: TextDirection.ltr,
        textScaler: st.scaler,
      )..layout(maxWidth: w);
    }

    // Titolo del capitolo in cima alla prima pagina.
    final tp = measure(TextSpan(text: title), st.title, TextAlign.center);
    used = PageStyle.titleTop + tp.height + PageStyle.titleBottom;
    tp.dispose();
    pages.last.blocks.add(PageBlock(chapterTitle: title));

    for (final p in paras) {
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

      // Paragrafo: se non entra lo spezzo a fine riga.
      var segs = p.segs;
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
