import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../models/book.dart';

/// Un pezzo di testo con stile.
class TextSeg {
  final String text;
  final bool italic;
  final bool bold;
  const TextSeg(this.text, {this.italic = false, this.bold = false});
}

/// Un paragrafo del capitolo. [level] > 0 indica un titolo (h1..h6).
class Para {
  final List<TextSeg> segs;
  final int level;
  const Para(this.segs, {this.level = 0});
  String get plain => segs.map((s) => s.text).join();
}

class EpubMeta {
  final String title;
  final String author;
  final String? series;
  final double? seriesIndex;
  final List<Chapter> chapters;
  final Uint8List? cover;
  final String coverExt;
  EpubMeta(this.title, this.author, this.series, this.seriesIndex, this.chapters, this.cover, this.coverExt);
}

Iterable<XmlElement> _byLocal(XmlNode root, String local) =>
    root.descendants.whereType<XmlElement>().where((e) => e.name.local.toLowerCase() == local);

XmlElement? _firstLocal(XmlNode root, String local) {
  for (final e in _byLocal(root, local)) {
    return e;
  }
  return null;
}

String _decode(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

XmlDocument? _parseXml(String text) {
  try {
    return XmlDocument.parse(text, entityMapping: XmlDefaultEntityMapping.html5());
  } catch (_) {
    try {
      return XmlDocument.parse(text);
    } catch (_) {
      return null;
    }
  }
}

class Epub {
  final Archive archive;
  final Map<String, ArchiveFile> _files = {};

  Epub._(this.archive) {
    for (final f in archive.files) {
      _files[f.name] = f;
      _files[_decode(f.name)] = f;
    }
  }

  factory Epub.open(List<int> bytes) => Epub._(ZipDecoder().decodeBytes(bytes));

  Uint8List? readBytes(String path) {
    final f = _files[path] ?? _files[_decode(path)];
    if (f == null) return null;
    final c = f.content;
    if (c is Uint8List) return c;
    return Uint8List.fromList((c as List).cast<int>());
  }

  String? readText(String path) {
    final b = readBytes(path);
    if (b == null) return null;
    return utf8.decode(b, allowMalformed: true);
  }

  static String _resolve(String baseDir, String href) {
    final clean = _decode(href.split('#').first);
    if (baseDir.isEmpty) return p.posix.normalize(clean);
    return p.posix.normalize(p.posix.join(baseDir, clean));
  }

  /// Legge metadati, capitoli e copertina.
  EpubMeta meta() {
    final container = readText('META-INF/container.xml');
    String opfPath = 'content.opf';
    if (container != null) {
      final doc = _parseXml(container);
      final rf = doc == null ? null : _firstLocal(doc, 'rootfile');
      opfPath = rf?.getAttribute('full-path') ?? opfPath;
    }
    final opfText = readText(opfPath);
    if (opfText == null) throw const FormatException('File OPF non trovato');
    final opf = _parseXml(opfText);
    if (opf == null) throw const FormatException('OPF non leggibile');
    final dir = p.posix.dirname(opfPath) == '.' ? '' : p.posix.dirname(opfPath);

    String title = _firstLocal(opf, 'title')?.innerText.trim() ?? '';
    String author = _firstLocal(opf, 'creator')?.innerText.trim() ?? '';
    String? series;
    double? seriesIndex;
    String? coverId;
    final metas = _byLocal(opf, 'meta').toList();
    for (final m in metas) {
      final name = m.getAttribute('name');
      final content = m.getAttribute('content');
      if (name == 'calibre:series' && content != null) series = content.trim();
      if (name == 'calibre:series_index' && content != null) seriesIndex = double.tryParse(content);
      if (name == 'cover' && content != null) coverId = content;
      final prop = m.getAttribute('property');
      if (prop == 'belongs-to-collection' && series == null) series = m.innerText.trim();
      if (prop == 'group-position' && seriesIndex == null) seriesIndex = double.tryParse(m.innerText.trim());
    }

    // Manifest
    final manifest = <String, (String href, String type, String props)>{};
    for (final it in _byLocal(opf, 'item')) {
      final id = it.getAttribute('id');
      final href = it.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (_resolve(dir, href), it.getAttribute('media-type') ?? '', it.getAttribute('properties') ?? '');
    }

    // Copertina
    String? coverPath;
    for (final e in manifest.values) {
      if (e.$3.contains('cover-image')) coverPath = e.$1;
    }
    if (coverPath == null && coverId != null && manifest[coverId] != null) coverPath = manifest[coverId]!.$1;
    if (coverPath == null) {
      for (final entry in manifest.entries) {
        if (entry.key.toLowerCase().contains('cover') && entry.value.$2.startsWith('image/')) {
          coverPath = entry.value.$1;
          break;
        }
      }
    }
    Uint8List? cover = coverPath == null ? null : readBytes(coverPath);
    final ext = coverPath == null ? 'jpg' : p.posix.extension(coverPath).replaceFirst('.', '').toLowerCase();

    // Titoli dall'indice (nav.xhtml o toc.ncx)
    final tocTitles = <String, String>{};
    String? navPath;
    String? ncxPath;
    for (final e in manifest.values) {
      if (e.$3.contains('nav')) navPath = e.$1;
      if (e.$2 == 'application/x-dtbncx+xml') ncxPath = e.$1;
    }
    if (navPath != null) {
      final navDoc = _parseXml(readText(navPath) ?? '');
      if (navDoc != null) {
        final navDir = p.posix.dirname(navPath) == '.' ? '' : p.posix.dirname(navPath);
        for (final a in _byLocal(navDoc, 'a')) {
          final href = a.getAttribute('href');
          final t = a.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (href == null || t.isEmpty) continue;
          tocTitles.putIfAbsent(_resolve(navDir, href), () => t);
        }
      }
    }
    if (tocTitles.isEmpty && ncxPath != null) {
      final ncx = _parseXml(readText(ncxPath) ?? '');
      if (ncx != null) {
        final ncxDir = p.posix.dirname(ncxPath) == '.' ? '' : p.posix.dirname(ncxPath);
        for (final np in _byLocal(ncx, 'navpoint')) {
          final label = _firstLocal(np, 'text')?.innerText.trim() ?? '';
          final src = _firstLocal(np, 'content')?.getAttribute('src');
          if (src == null || label.isEmpty) continue;
          tocTitles.putIfAbsent(_resolve(ncxDir, src), () => label);
        }
      }
    }

    // Spine = ordine di lettura
    final chapters = <Chapter>[];
    var n = 0;
    for (final ref in _byLocal(opf, 'itemref')) {
      final idref = ref.getAttribute('idref');
      final item = idref == null ? null : manifest[idref];
      if (item == null) continue;
      if (!(item.$2.contains('html') || item.$2.contains('xml'))) continue;
      n++;
      final t = tocTitles[item.$1];
      chapters.add(Chapter(t ?? 'Sezione $n', item.$1));
    }

    if (title.isEmpty) title = 'Senza titolo';
    return EpubMeta(title, author, series, seriesIndex, chapters, cover, ext.isEmpty ? 'jpg' : ext);
  }

  /// Converte un capitolo XHTML in paragrafi.
  List<Para> chapter(String href) {
    final text = readText(href);
    if (text == null) return const [];
    final doc = _parseXml(text);
    if (doc == null) return _fallback(text);
    final body = _firstLocal(doc, 'body') ?? doc.rootElement;
    final out = <Para>[];
    _walk(body, out);
    return out;
  }

  static const _blocks = {'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'pre', 'dt', 'dd', 'figcaption', 'td', 'th'};
  static const _skip = {'script', 'style', 'head', 'title', 'svg', 'img', 'image'};

  static bool _hasBlock(XmlElement e) {
    for (final d in e.descendants.whereType<XmlElement>()) {
      final n = d.name.local.toLowerCase();
      if (_blocks.contains(n) || n == 'div' || n == 'section') return true;
    }
    return false;
  }

  static void _walk(XmlElement el, List<Para> out) {
    for (final child in el.children) {
      if (child is XmlElement) {
        final name = child.name.local.toLowerCase();
        if (_skip.contains(name)) continue;
        if (_blocks.contains(name)) {
          _addPara(child, out, name);
        } else if (_hasBlock(child)) {
          _walk(child, out);
        } else {
          _addPara(child, out, name);
        }
      } else if (child is XmlText || child is XmlCDATA) {
        final t = (child.value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isNotEmpty) out.add(Para([TextSeg(t)]));
      }
    }
  }

  static void _addPara(XmlElement e, List<Para> out, String name) {
    final segs = <TextSeg>[];
    _inline(e, false, false, segs);
    final cleaned = _normalize(segs);
    if (cleaned.isEmpty) return;
    var level = 0;
    if (name.length == 2 && name.startsWith('h')) level = int.tryParse(name.substring(1)) ?? 0;
    out.add(Para(cleaned, level: level));
  }

  static void _inline(XmlNode node, bool italic, bool bold, List<TextSeg> segs) {
    for (final c in node.children) {
      if (c is XmlText || c is XmlCDATA) {
        final v = c.value ?? '';
        if (v.isNotEmpty) segs.add(TextSeg(v, italic: italic, bold: bold));
      } else if (c is XmlElement) {
        final n = c.name.local.toLowerCase();
        if (_skip.contains(n)) continue;
        if (n == 'br') {
          segs.add(const TextSeg('\n'));
          continue;
        }
        _inline(c, italic || n == 'i' || n == 'em' || n == 'cite', bold || n == 'b' || n == 'strong', segs);
      }
    }
  }

  static List<TextSeg> _normalize(List<TextSeg> segs) {
    final out = <TextSeg>[];
    for (final s in segs) {
      final t = s.text == '\n' ? '\n' : s.text.replaceAll(RegExp(r'\s+'), ' ');
      if (t.isEmpty) continue;
      out.add(TextSeg(t, italic: s.italic, bold: s.bold));
    }
    // togli spazi iniziali/finali
    while (out.isNotEmpty && out.first.text.trim().isEmpty) {
      out.removeAt(0);
    }
    while (out.isNotEmpty && out.last.text.trim().isEmpty) {
      out.removeLast();
    }
    if (out.isEmpty) return out;
    out[0] = TextSeg(out[0].text.trimLeft(), italic: out[0].italic, bold: out[0].bold);
    final l = out.length - 1;
    out[l] = TextSeg(out[l].text.trimRight(), italic: out[l].italic, bold: out[l].bold);
    return out;
  }

  static List<Para> _fallback(String html) {
    final parts = html.split(RegExp(r'</p>|<br\s*/?>', caseSensitive: false));
    return parts
        .map((s) => s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((s) => s.isNotEmpty)
        .map((s) => Para([TextSeg(s)]))
        .toList();
  }
}
