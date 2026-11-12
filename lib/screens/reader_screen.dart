import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../widgets/ambience_sheet.dart';
import '../services/ambience.dart';
import '../models/book.dart';
import '../services/annotations.dart';
import '../services/epub.dart';
import '../services/home_widget_sync.dart';
import '../services/hyphen.dart';
import '../services/library_store.dart';
import '../services/paginator.dart';
import '../services/wiki.dart';
import '../theme.dart';
import '../widgets/lk_icons.dart';
import '../widgets/page_turner.dart';
import '../widgets/quote_card.dart';
import '../widgets/word_sheet.dart';
import 'book_extras.dart';
import 'reader_panel.dart';
import '../widgets/adaptive.dart';
import 'world_map.dart';
import 'wiki_screens.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  final int? startChapter;
  const ReaderScreen({super.key, required this.book, this.startChapter});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final store = LibraryStore.I;
  Epub? _epub;
  String? _error;
  bool _loading = true;

  int _chapter = 0;
  List<Para> _paras = const [];
  bool _panel = true; // tablet: pannello wiki accanto al testo
  final Map<String, Uint8List> _imgBytes = {};
  final Map<String, Size> _imgSizes = {};

  // Modalità pagine
  List<PageLayout> _pages = const [];
  String _layoutKey = '';
  String _styleKey = '';
  bool _ui = false;
  int _page = 0;
  bool _spread = false; // due pagine affiancate
  double _pendingFrac = 0;
  bool _pendingToEnd = false;
  final _turner = GlobalKey<PageTurnerState>();
  final _focus = FocusNode();
  DateTime _pageShownAt = DateTime.now();

  // Modalità scorrimento
  ScrollController _scroll = ScrollController();

  double _fraction = 0;
  final _watch = Stopwatch();
  Timer? _timeTimer;

  // Wiki: nomi riconosciuti nel testo
  Wiki? _wiki;
  RegExp? _nameRe;
  final Map<String, String> _nameIds = {};
  DateTime? _prevRead;

  // Evidenziazioni, segnalibri, ricerca, lettura ad alta voce
  BookNotes get _notes => Annotations.I.of(book.id);
  String? _flash; // testo trovato con la ricerca, evidenziato finché giri pagina
  String? _pendingFind; // testo da raggiungere dopo l'impaginazione
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  bool _ttsPaused = false;
  int _ttsRun = 0;
  String? _ttsText; // blocco che si sta leggendo
  double _ttsRate = 0.5;

  Book get book => widget.book;
  ReaderPrefs get prefs => store.reader;
  bool get paged => prefs.mode != 'Scorrimento';

  @override
  void initState() {
    super.initState();
    Ambience.I.start();
    _prevRead = book.lastReadAt;
    _applySystem();
    WikiStore.I.addListener(_onWiki);
    WikiStore.I.forBook(book).then((w) {
      _wiki = w;
      _onWiki();
    });
    _open();
    _watch.start();
    _timeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _flushTime());
  }

  // ---------- sistema: schermo, orientamento, immersiva ----------

  void _applySystem() {
    SystemChrome.setEnabledSystemUIMode(prefs.immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    switch (prefs.orientation) {
      case 'Verticale':
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        break;
      case 'Orizzontale':
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        break;
      default:
        SystemChrome.setPreferredOrientations([]);
    }
    try {
      prefs.keepAwake ? WakelockPlus.enable() : WakelockPlus.disable();
    } catch (_) {}
  }

  void _restoreSystem() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    try {
      WakelockPlus.disable();
    } catch (_) {}
  }

  // ---------- caricamento ----------

  Future<void> _open() async {
    try {
      final bytes = await File(book.filePath).readAsBytes();
      _epub = Epub.open(bytes);
      final start = widget.startChapter ?? book.lastChapter;
      final frac = widget.startChapter == null ? book.lastOffset : 0.0;
      await _loadChapter(start.clamp(0, book.chapters.isEmpty ? 0 : book.chapters.length - 1), frac: frac);
      _measureBook();
      final prev = _prevRead;
      if (prev != null && DateTime.now().difference(prev).inHours >= 48 && book.lastChapter > 0) {
        _showRecap(auto: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Non riesco ad aprire il file: $e');
    }
  }

  /// Lunghezza di ogni capitolo, per stimare il tempo che manca.
  Future<void> _measureBook() async {
    if (_epub == null) return;
    if (book.chapterChars != null && book.chapterChars!.length == book.chapters.length) return;
    final out = <int>[];
    for (final c in book.chapters) {
      out.add(_epub!.chapterParas(c).fold<int>(0, (a, p) => a + p.plain.length));
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }
    store.setChapterChars(book, out);
    if (mounted) setState(() {});
  }

  List<Para> _prepare(List<Para> raw) {
    if (!prefs.hyphenate) return raw;
    return [
      for (final p in raw)
        p.image != null || p.level > 0
            ? p
            : Para([for (final s in p.segs) TextSeg(Hyphen.apply(s.text), italic: s.italic, bold: s.bold)])
    ];
  }

  Future<void> _loadImages(List<Para> paras) async {
    for (final p in paras) {
      final path = p.image;
      if (path == null || _imgSizes.containsKey(path)) continue;
      final bytes = _epub!.readBytes(path);
      if (bytes == null) continue;
      _imgBytes[path] = bytes;
      try {
        final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
        final desc = await ui.ImageDescriptor.encoded(buf);
        _imgSizes[path] = Size(desc.width.toDouble(), desc.height.toDouble());
        desc.dispose();
        buf.dispose();
      } catch (_) {
        _imgSizes[path] = const Size(3, 4);
      }
    }
  }

  // Capitoli vicini: mentre giri l'ultima pagina si vede già l'inizio del successivo (e viceversa).
  final Map<int, List<Para>> _nbParas = {};
  final Map<String, List<PageLayout>> _nbPages = {};
  bool? _nbHyph;

  Future<void> _prefetchNeighbours() async {
    final keep = {_chapter - 1, _chapter, _chapter + 1};
    _nbParas.removeWhere((k, _) => !keep.contains(k));
    _nbPages.removeWhere((k, _) => !keep.contains(int.tryParse(k.split('|').first)));
    _nbParas[_chapter] = _paras;
    for (final i in [_chapter + 1, _chapter - 1]) {
      if (i < 0 || i >= book.chapters.length || _nbParas.containsKey(i)) continue;
      try {
        final paras = _prepare(_epub!.chapterParas(book.chapters[i]));
        await _loadImages(paras);
        if (!mounted) return;
        _nbParas[i] = paras;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  String _titleOf(int i) => book.chapters.isEmpty ? book.title : book.chapters[i].title;

  List<PageLayout>? _pagesOf(int i, Size size, PageStyle st) {
    final paras = _nbParas[i];
    if (paras == null) return null;
    final key = '$i|$_styleKey';
    return _nbPages[key] ??= Paginator.paginate(paras: paras, title: _titleOf(i), imageSizes: _imgSizes, page: size, st: st);
  }

  Future<void> _loadChapter(int index, {double frac = 0, bool toEnd = false}) async {
    if (_epub == null || book.chapters.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    if (_nbHyph != prefs.hyphenate) {
      _nbParas.clear();
      _nbPages.clear();
      _nbHyph = prefs.hyphenate;
    }
    final paras = _nbParas[index] ?? _prepare(_epub!.chapterParas(book.chapters[index]));
    await _loadImages(paras);
    readerFont(prefs.font, prefs.size, Colors.black, prefs.lineHeight);
    LK.display(24);
    try {
      await GoogleFonts.pendingFonts();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _chapter = index;
      _paras = paras;
      _pendingFrac = frac;
      _pendingToEnd = toEnd;
      _fraction = toEnd ? 1 : frac;
      _layoutKey = '';
      _loading = false;
      _scroll.dispose();
      _scroll = ScrollController();
      _scroll.addListener(_onScroll);
    });
    _pageShownAt = DateTime.now();
    store.setProgress(book, index, _fraction);
    _onWiki();
    WikiStore.I.ensure(book);
    _prefetchNeighbours();
    if (!paged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        _scroll.jumpTo((max * frac).clamp(0.0, max));
      });
    }
  }

  // ---------- pagine ----------

  int get _step => _spread ? 2 : 1;

  void _ensureLayout(Size size, PageStyle st) {
    _styleKey = '${size.width.round()}x${size.height.round()}|${prefs.font}|${prefs.size}|${prefs.lineHeight}|'
        '${st.theme.name}|${st.scaler.scale(10)}|${prefs.justify}|${prefs.hyphenate}|$_spread';
    final key = '$_chapter|$_styleKey';
    if (key == _layoutKey) return;
    final oldCount = _pages.length;
    final keepFrac = _layoutKey.isEmpty ? null : (oldCount <= 1 ? 0.0 : _page / (oldCount - 1));
    _layoutKey = key;
    _pages = Paginator.paginate(
      paras: _paras,
      title: book.chapters.isEmpty ? book.title : book.chapters[_chapter].title,
      imageSizes: _imgSizes,
      page: size,
      st: st,
    );
    final n = _pages.length;
    final frac = keepFrac ?? _pendingFrac;
    _page = _pendingToEnd && keepFrac == null ? n - 1 : (frac * (n - 1)).round().clamp(0, n - 1);
    if (_spread) _page -= _page % 2;
    _pendingToEnd = false;
    final find = _pendingFind;
    if (find != null) {
      _pendingFind = null;
      final i = _findPage(find);
      if (i >= 0) {
        _page = i - (_spread ? i % 2 : 0);
        _fraction = n <= 1 ? 1 : _page / (n - 1);
      }
    }
  }

  /// Tablet in orizzontale: il pannello della wiki accanto al testo.
  Widget _withPanel(Widget reader) {
    if (!isWide(context) || !_panel) return reader;
    return Row(children: [
      Expanded(child: reader),
      ReaderSidePanel(book: book, pageText: _visibleText, onClose: () => setState(() => _panel = false)),
    ]);
  }

  /// Testo della pagina (o delle due pagine) che stai leggendo, per il pannello del tablet.
  String get _visibleText {
    if (paged && _pages.isNotEmpty) {
      final out = StringBuffer();
      for (var i = _page; i < _page + _step && i < _pages.length; i++) {
        for (final b in _pages[i].blocks) {
          out.write(' ${_blockPlain(b)}');
        }
      }
      return out.toString();
    }
    if (_paras.isEmpty) return '';
    final c = (_fraction * _paras.length).floor().clamp(0, _paras.length - 1);
    return _paras.sublist(c, (c + 8).clamp(0, _paras.length)).map((p) => p.segs.map((s) => s.text).join()).join(' ');
  }

  String _blockPlain(PageBlock b) => b.segs.map((s) => s.text).join().replaceAll(Hyphen.soft, '');

  /// Pagina che contiene [needle] (o l'inizio), -1 se non c'è.
  int _findPage(String needle) {
    final q = needle.toLowerCase();
    final head = q.length > 30 ? q.substring(0, 30) : q;
    for (var i = 0; i < _pages.length; i++) {
      final txt = _pages[i].blocks.map(_blockPlain).join(' ').toLowerCase();
      if (txt.contains(head)) return i;
    }
    return -1;
  }

  /// Porta al capitolo e alla pagina che contengono [text].
  void _goToText(int chapter, String text, {double frac = 0}) {
    setState(() => _ui = false);
    if (chapter == _chapter && paged && _pages.isNotEmpty) {
      final i = _findPage(text);
      if (i >= 0) {
        _setPage(i - (_spread ? i % 2 : 0));
        return;
      }
    }
    _pendingFind = text;
    _loadChapter(chapter, frac: frac);
    if (!paged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {});
    }
  }

  int _pageChars(int i) {
    if (i < 0 || i >= _pages.length) return 0;
    var c = 0;
    for (final b in _pages[i].blocks) {
      for (final s in b.segs) {
        c += s.text.length;
      }
    }
    return c;
  }

  void _setPage(int i) {
    final n = _pages.length;
    // velocità di lettura: tempo passato sulla pagina appena lasciata
    final secs = DateTime.now().difference(_pageShownAt).inMilliseconds / 1000;
    var chars = 0;
    for (var k = 0; k < _step; k++) {
      chars += _pageChars(_page + k);
    }
    if (i > _page) store.recordPage(chars, secs);
    _pageShownAt = DateTime.now();
    setState(() {
      if (i != _page && _ttsText == null) _flash = null;
      _page = i.clamp(0, n - 1);
      _fraction = n <= 1 ? 1 : _page / (n - 1);
      _ui = false;
    });
    store.setProgress(book, _chapter, _fraction);
  }

  void _afterLast() {
    if (_chapter < book.chapters.length - 1) {
      store.chapterFinished();
      _loadChapter(_chapter + 1);
    }
  }

  void _beforeFirst() {
    if (_chapter > 0) _loadChapter(_chapter - 1, toEnd: true);
  }

  // ---------- scorrimento ----------

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final f = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((f - _fraction).abs() > 0.004) {
      setState(() => _fraction = f);
      store.setProgress(book, _chapter, f);
    }
  }

  void _goChapter(int delta) {
    final next = _chapter + delta;
    if (next < 0 || next >= book.chapters.length) return;
    if (delta > 0) store.chapterFinished();
    _loadChapter(next);
  }

  void _flushTime() {
    final s = _watch.elapsed.inSeconds;
    if (s > 0) {
      store.addReadingTime(s);
      _watch
        ..reset()
        ..start();
    }
  }

  @override
  void dispose() {
    Ambience.I.stop();
    _flushTime();
    _timeTimer?.cancel();
    _ttsRun++;
    _tts.stop();
    _scroll.dispose();
    _focus.dispose();
    WikiStore.I.removeListener(_onWiki);
    _restoreSystem();
    store.updateBook(book);
    HomeWidgetSync.update();
    super.dispose();
  }

  // ---------- wiki nel testo ----------

  void _onWiki() {
    final w = _wiki;
    if (w == null) return;
    final limit = WikiStore.I.limitFor(book);
    _nameIds.clear();
    for (final e in w.entries.values) {
      if (!e.visibleAt(limit)) continue;
      for (final n in [e.name, ...e.aliases]) {
        final k = n.trim();
        if (k.length >= 3) _nameIds[k.toLowerCase()] = e.id;
      }
    }
    if (_nameIds.isEmpty) {
      _nameRe = null;
    } else {
      final names = _nameIds.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      final alts = names.map((n) => n.split('').map(RegExp.escape).join('${Hyphen.soft}?')).join('|');
      _nameRe = RegExp('(?<![\\p{L}])($alts)(?![\\p{L}])', unicode: true, caseSensitive: false);
    }
    if (mounted) setState(() {});
  }

  List<(int, int, String)> _matches(String text) {
    final re = _nameRe;
    if (re == null) return const [];
    return [
      for (final m in re.allMatches(text))
        if (_nameIds[m[0]!.replaceAll(Hyphen.soft, '').toLowerCase()] != null) (m.start, m.end, _nameIds[m[0]!.replaceAll(Hyphen.soft, '').toLowerCase()]!)
    ];
  }

  /// Intervalli evidenziati nel testo del blocco (che può contenere trattini morbidi).
  List<(int, int, Color)> _marks(String text, ReaderTheme t) {
    final out = <(int, int, Color)>[];
    final hls = _notes.highlights.where((h) => h.chapter == _chapter).toList();
    if (hls.isEmpty && _flash == null && _ttsText == null) return out;
    // mappa testo senza trattini → testo originale
    final map = <int>[];
    final sb = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (text[i] == Hyphen.soft) continue;
      map.add(i);
      sb.write(text[i]);
    }
    map.add(text.length);
    final plain = sb.toString();
    void add(int a, int z, Color c) {
      if (z > a) out.add((map[a.clamp(0, map.length - 1)], map[z.clamp(0, map.length - 1)], c));
    }

    final dark = t.name == 'Notte';
    for (final h in hls) {
      final c = Color(Annotations.colors[h.color % Annotations.colors.length]).withValues(alpha: dark ? 0.38 : 0.55);
      final x = h.text;
      final i = plain.indexOf(x);
      if (i >= 0) {
        add(i, i + x.length, c);
        continue;
      }
      // frase spezzata tra due pagine: inizio o fine del blocco
      if (plain.length >= 12) {
        final head = plain.substring(0, plain.length < 24 ? plain.length : 24);
        final at = x.indexOf(head);
        if (at > 0 && plain.startsWith(x.substring(at))) add(0, x.length - at, c);
        final start = x.substring(0, x.length < 24 ? x.length : 24);
        final s2 = plain.lastIndexOf(start);
        if (s2 > 0 && x.startsWith(plain.substring(s2))) add(s2, plain.length, c);
      }
    }
    final f = _flash;
    if (f != null && f.isNotEmpty) {
      final lp = plain.toLowerCase(), lf = f.toLowerCase();
      var i = lp.indexOf(lf);
      while (i >= 0) {
        add(i, i + f.length, t.accent.withValues(alpha: 0.28));
        i = lp.indexOf(lf, i + f.length);
      }
    }
    if (_ttsText != null && plain == _ttsText) add(0, plain.length, t.accent.withValues(alpha: 0.12));
    return out;
  }

  InlineSpan _richSpan(List<TextSeg> segs, ReaderTheme t) {
    final text = segs.map((s) => s.text).join();
    final ms = _matches(text);
    final marks = _marks(text, t);
    if (ms.isEmpty && marks.isEmpty) return PageStyle.span(segs);
    final hl = TextStyle(
      color: Color.lerp(t.ink, t.accent, 0.65),
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: t.accent.withValues(alpha: 0.6),
    );
    // confini di tutti gli intervalli
    final cuts = <int>{0, text.length};
    for (final m in ms) {
      cuts..add(m.$1)..add(m.$2);
    }
    for (final m in marks) {
      cuts..add(m.$1)..add(m.$2);
    }
    var pos = 0;
    for (final s in segs) {
      cuts.add(pos);
      pos += s.text.length;
    }
    final sorted = cuts.where((c) => c >= 0 && c <= text.length).toList()..sort();
    final out = <InlineSpan>[];
    var segStart = 0, si = 0;
    for (var k = 0; k + 1 < sorted.length; k++) {
      final a = sorted[k], z = sorted[k + 1];
      if (z <= a) continue;
      while (si < segs.length - 1 && a >= segStart + segs[si].text.length) {
        segStart += segs[si].text.length;
        si++;
      }
      final sg = segs[si];
      var style = TextStyle(fontStyle: sg.italic ? FontStyle.italic : null, fontWeight: sg.bold ? FontWeight.w700 : null);
      if (ms.any((m) => m.$1 <= a && m.$2 >= z)) style = style.merge(hl);
      for (final m in marks) {
        if (m.$1 <= a && m.$2 >= z) style = style.copyWith(backgroundColor: m.$3);
      }
      out.add(TextSpan(text: text.substring(a, z), style: style));
    }
    return TextSpan(children: out);
  }

  void _tapText(List<TextSeg> segs, TapUpDetails d, double width, PageStyle st) {
    final text = segs.map((s) => s.text).join();
    final ms = _matches(text);
    if (ms.isNotEmpty && _wiki != null) {
      final tp = TextPainter(
        text: TextSpan(style: st.base, children: [PageStyle.span(segs)]),
        textAlign: _align,
        textDirection: TextDirection.ltr,
        textScaler: st.scaler,
      )..layout(maxWidth: width);
      final i = tp.getPositionForOffset(d.localPosition).offset;
      tp.dispose();
      for (final m in ms) {
        if (i >= m.$1 && i <= m.$2) {
          final e = _wiki!.entries[m.$3];
          if (e != null) {
            showEntryPeek(context, book, e);
            return;
          }
        }
      }
    }
    if (paged) {
      _turner.currentState?.tapAt(d.globalPosition);
    } else {
      setState(() => _ui = !_ui);
    }
  }

  Future<void> _showRecap({bool auto = false}) async {
    setState(() => _ui = false);
    final future = WikiStore.I.recap(book);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nei capitoli precedenti…', style: LK.display(22)),
            const SizedBox(height: 12),
            FutureBuilder<String?>(
              future: future,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Padding(padding: const EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: LK.accent)));
                }
                final t = snap.data;
                return Text(
                  t ?? 'Il riassunto sarà disponibile quando la wiki avrà letto i capitoli precedenti (serve la chiave di Gemini).',
                  style: LK.body(16, height: 1.55, color: t == null ? LK.muted : LK.ink),
                );
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('RIPRENDI LA LETTURA', style: LK.label(11, color: LK.accent, spacing: 1.2)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- tasti del volume ----------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!prefs.volumeKeys || !paged) return KeyEventResult.ignored;
    final down = e.logicalKey == LogicalKeyboardKey.audioVolumeDown;
    final up = e.logicalKey == LogicalKeyboardKey.audioVolumeUp;
    if (!down && !up) return KeyEventResult.ignored;
    if (e is KeyDownEvent) _turner.currentState?.turn(down ? 1 : -1);
    return KeyEventResult.handled;
  }

  // ---------- tempo stimato ----------

  String _fmtTime(double seconds) {
    final m = (seconds / 60).round();
    if (m < 1) return 'meno di 1 min';
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }

  /// (capitolo, libro) in secondi, oppure null se la velocità non è ancora nota.
  (double, double)? get _remaining {
    final cps = store.charsPerSecond;
    if (cps <= 0) return null;
    double chapterChars;
    if (paged && _pages.isNotEmpty) {
      chapterChars = 0;
      for (var i = _page; i < _pages.length; i++) {
        chapterChars += _pageChars(i);
      }
    } else {
      final total = (book.chapterChars != null && _chapter < book.chapterChars!.length) ? book.chapterChars![_chapter] : 0;
      chapterChars = total * (1 - _fraction);
    }
    var rest = 0;
    final cc = book.chapterChars;
    if (cc != null) {
      for (var i = _chapter + 1; i < cc.length; i++) {
        rest += cc[i];
      }
    }
    return (chapterChars / cps, (chapterChars + rest) / cps);
  }

  // ---------- parola premuta ----------

  void _lookup(List<TextSeg> segs, Offset local, double width, PageStyle st, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(style: st.base, children: [PageStyle.span(segs)]),
      textAlign: align,
      textDirection: TextDirection.ltr,
      textScaler: st.scaler,
    )..layout(maxWidth: width);
    final pos = tp.getPositionForOffset(local);
    final range = tp.getWordBoundary(pos);
    tp.dispose();
    final text = segs.map((s) => s.text).join();
    if (range.start < 0 || range.end > text.length || range.end <= range.start) return;
    final word = text.substring(range.start, range.end).replaceAll(Hyphen.soft, '').replaceAll(RegExp(r'[^\p{L}\p{N}\-]', unicode: true), '');
    if (word.isEmpty) return;
    final plain = text.replaceAll(Hyphen.soft, '');
    var a = plain.lastIndexOf(RegExp(r'[.!?…]'), (range.start - 1).clamp(0, plain.length));
    a = a < 0 ? 0 : a + 1;
    var b = plain.indexOf(RegExp(r'[.!?…]'), range.end.clamp(0, plain.length));
    b = b < 0 ? plain.length : b + 1;
    final sentence = plain.substring(a.clamp(0, plain.length), b.clamp(0, plain.length)).trim();
    HapticFeedback.selectionClick();
    _textActions(word, sentence.isEmpty ? plain : sentence, plain);
  }

  Highlight? _highlightFor(String sentence) {
    for (final h in _notes.highlights) {
      if (h.chapter == _chapter && (h.text.contains(sentence) || sentence.contains(h.text))) return h;
    }
    return null;
  }

  /// Menu della frase tenuta premuta: evidenzia, nota, significato, copia, leggi da qui.
  void _textActions(String word, String sentence, String paragraph) {
    final existing = _highlightFor(sentence);
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: LK.gold, width: 3))),
              child: Text('«$sentence»', maxLines: 4, overflow: TextOverflow.ellipsis, style: LK.body(14.5, height: 1.5, style: FontStyle.italic)),
            ),
            const SizedBox(height: 14),
            Text(existing == null ? 'EVIDENZIA' : 'COLORE', style: LK.label(10, spacing: 1.4)),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < Annotations.colors.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (existing != null) {
                        existing.color = i;
                      } else {
                        _notes.highlights.add(Highlight(id: Annotations.newId(), chapter: _chapter, frac: _fraction, text: sentence, color: i));
                      }
                      Annotations.I.save(book.id);
                      setState(() {});
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color(Annotations.colors[i]),
                        shape: BoxShape.circle,
                        border: Border.all(color: existing?.color == i ? LK.ink : Colors.transparent, width: 2.5),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _action(Icons.edit_note, existing?.note.isNotEmpty == true ? 'Modifica nota' : 'Aggiungi nota', () async {
                Navigator.pop(ctx);
                final h = existing ?? Highlight(id: Annotations.newId(), chapter: _chapter, frac: _fraction, text: sentence);
                final note = await _askNote(h.note);
                if (note == null) return;
                h.note = note;
                if (existing == null) _notes.highlights.add(h);
                await Annotations.I.save(book.id);
                setState(() {});
              }),
              _action(existing?.favorite == true ? Icons.star : Icons.star_border, existing?.favorite == true ? 'Tra le preferite' : 'Citazione preferita', () async {
                Navigator.pop(ctx);
                final h = existing ?? Highlight(id: Annotations.newId(), chapter: _chapter, frac: _fraction, text: sentence);
                h.favorite = !h.favorite;
                if (existing == null) _notes.highlights.add(h);
                await Annotations.I.save(book.id);
                setState(() {});
              }),
              _action(Icons.translate, 'Significato di «$word»', () {
                Navigator.pop(ctx);
                showWordSheet(context, word: word, sentence: sentence, bookTitle: book.title);
              }),
              _action(Icons.ios_share, 'Condividi come immagine', () {
                Navigator.pop(ctx);
                showQuoteShare(context, book: book, text: sentence, chapter: book.chapters.isEmpty ? null : book.chapters[_chapter].title);
              }),
              _action(Icons.copy, 'Copia', () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: sentence));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Frase copiata')));
              }),
              _action(Icons.record_voice_over_outlined, 'Leggi da qui', () {
                Navigator.pop(ctx);
                _startTts(fromText: paragraph);
              }),
              if (existing != null)
                _action(Icons.delete_outline, 'Rimuovi evidenziazione', () {
                  Navigator.pop(ctx);
                  _notes.highlights.remove(existing);
                  Annotations.I.save(book.id);
                  setState(() {});
                }),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 18, color: LK.accent),
        label: Text(label, style: LK.body(13)),
        backgroundColor: LK.card,
        side: BorderSide(color: LK.border),
        onPressed: onTap,
      );

  Future<String?> _askNote(String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LK.paper,
        title: Text('Nota', style: LK.display(20)),
        content: TextField(controller: c, autofocus: true, maxLines: 5, minLines: 3, decoration: const InputDecoration(hintText: 'Cosa ne pensi?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Salva')),
        ],
      ),
    );
  }

  // ---------- segnalibri ----------

  Bookmark? get _bookmarkHere {
    for (final bm in _notes.bookmarks) {
      if (bm.chapter != _chapter) continue;
      if (paged && _pages.length > 1) {
        final p = (bm.frac * (_pages.length - 1)).round();
        if (p == _page || (_spread && p == _page + 1)) return bm;
      } else if ((bm.frac - _fraction).abs() < 0.03) {
        return bm;
      }
    }
    return null;
  }

  String get _excerptHere {
    if (paged && _page < _pages.length) {
      final t = _pages[_page].blocks.where((b) => b.segs.isNotEmpty && b.level == 0).map(_blockPlain).join(' ').trim();
      return t.length > 140 ? '${t.substring(0, 140)}…' : t;
    }
    final t = _paras.where((p) => p.level == 0 && p.image == null).map((p) => p.plain).join(' ');
    final i = (t.length * _fraction).round().clamp(0, t.length);
    final x = t.substring(i, (i + 140).clamp(0, t.length));
    return '$x…';
  }

  void _toggleBookmark() {
    final bm = _bookmarkHere;
    if (bm != null) {
      _notes.bookmarks.remove(bm);
    } else {
      _notes.bookmarks.add(Bookmark(id: Annotations.newId(), chapter: _chapter, frac: _fraction, excerpt: _excerptHere));
      HapticFeedback.lightImpact();
    }
    Annotations.I.save(book.id);
    setState(() {});
  }

  // ---------- ricerca nel libro ----------

  void _searchSheet() {
    setState(() => _ui = false);
    final q = TextEditingController(text: _flash ?? '');
    var results = <(int, String, String)>[]; // capitolo, anteprima, testo trovato
    var busy = false;
    var run = 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> search(String text) async {
          final query = text.trim();
          final my = ++run;
          if (query.length < 2 || _epub == null) {
            setSheet(() => results = []);
            return;
          }
          setSheet(() => busy = true);
          final out = <(int, String, String)>[];
          final lq = query.toLowerCase();
          for (var c = 0; c < book.chapters.length && out.length < 200; c++) {
            final paras = _epub!.chapterParas(book.chapters[c]);
            for (final p in paras) {
              final t = p.plain;
              final lt = t.toLowerCase();
              var i = lt.indexOf(lq);
              while (i >= 0 && out.length < 200) {
                final a = (i - 50).clamp(0, t.length), z = (i + query.length + 70).clamp(0, t.length);
                out.add((c, '${a > 0 ? '…' : ''}${t.substring(a, z)}${z < t.length ? '…' : ''}', t.substring(i, i + query.length)));
                i = lt.indexOf(lq, i + query.length);
              }
            }
            if (c % 5 == 4) {
              await Future<void>.delayed(Duration.zero);
              if (my != run) return;
            }
          }
          if (my != run) return;
          setSheet(() {
            results = out;
            busy = false;
          });
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: q,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: search,
                  onChanged: (v) => v.trim().length >= 3 ? search(v) : null,
                  decoration: InputDecoration(
                    hintText: 'Cerca nel libro…',
                    prefixIcon: Icon(Icons.search, color: LK.muted),
                    filled: true,
                    fillColor: LK.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
                  ),
                ),
              ),
              if (busy) LinearProgressIndicator(color: LK.accent, backgroundColor: LK.line),
              if (!busy && q.text.trim().length >= 2)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(results.isEmpty ? 'Nessun risultato' : '${results.length}${results.length >= 200 ? '+' : ''} risultati', style: LK.label(10, spacing: 1)),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: LK.line),
                  itemBuilder: (ctx, i) {
                    final r = results[i];
                    final ql = q.text.trim().toLowerCase();
                    final at = r.$2.toLowerCase().indexOf(ql);
                    return ListTile(
                      title: Text(book.chapters[r.$1].title, style: LK.label(10, color: LK.accent, spacing: 0.6)),
                      subtitle: at < 0
                          ? Text(r.$2, style: LK.body(14))
                          : Text.rich(TextSpan(style: LK.body(14, color: LK.ink), children: [
                              TextSpan(text: r.$2.substring(0, at)),
                              TextSpan(text: r.$2.substring(at, at + ql.length), style: TextStyle(backgroundColor: LK.accent.withValues(alpha: 0.22), fontWeight: FontWeight.w600)),
                              TextSpan(text: r.$2.substring(at + ql.length)),
                            ])),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _flash = r.$3);
                        final snippet = r.$2.replaceAll('…', '');
                        _goToText(r.$1, snippet.length > 40 ? snippet.substring(snippet.toLowerCase().indexOf(ql).clamp(0, snippet.length)) : snippet);
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // ---------- lettura ad alta voce ----------

  /// Testi da leggere, dalla pagina attuale (o dal paragrafo [fromText]) in poi.
  List<(int, String)> _ttsQueue({String? fromText}) {
    final out = <(int, String)>[];
    if (paged) {
      final from = fromText == null ? -1 : _findPage(fromText.replaceAll(Hyphen.soft, ''));
      var started = fromText == null;
      for (var i = (from >= 0 ? from : _page); i < _pages.length; i++) {
        for (final b in _pages[i].blocks) {
          if (b.chapterTitle != null) {
            out.add((i, b.chapterTitle!));
            continue;
          }
          if (b.segs.isEmpty) continue;
          final t = _blockPlain(b);
          if (!started) {
            if (fromText!.replaceAll(Hyphen.soft, '').contains(t) || t.contains(fromText.replaceAll(Hyphen.soft, ''))) started = true;
            if (!started) continue;
          }
          out.add((i, t));
        }
      }
    } else {
      final t = _paras.where((p) => p.image == null).map((p) => p.plain.replaceAll(Hyphen.soft, '')).toList();
      var i = fromText == null ? (t.length * _fraction).floor() : t.indexWhere((x) => x.contains(fromText.replaceAll(Hyphen.soft, '')));
      for (i = i.clamp(0, t.length); i < t.length; i++) {
        out.add((-1, t[i]));
      }
    }
    return out;
  }

  Future<void> _startTts({String? fromText}) async {
    final run = ++_ttsRun;
    await _tts.stop();
    try {
      await _tts.setLanguage('it-IT');
      await _tts.setSpeechRate(_ttsRate);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
    try {
      WakelockPlus.enable();
    } catch (_) {}
    setState(() {
      _speaking = true;
      _ttsPaused = false;
      _ui = false;
    });
    var queue = _ttsQueue(fromText: fromText);
    while (run == _ttsRun) {
      for (final (page, text) in queue) {
        if (run != _ttsRun) return;
        if (paged && page >= 0 && page != _page && !(_spread && page == _page + 1)) _setPage(page - (_spread ? page % 2 : 0));
        setState(() => _ttsText = text);
        // frasi lunghe divise: il motore ha un limite di caratteri
        for (final part in _chunks(text)) {
          if (run != _ttsRun) return;
          await _tts.speak(part);
        }
      }
      if (run != _ttsRun) return;
      // capitolo finito: passo al successivo e continuo
      if (_chapter >= book.chapters.length - 1) break;
      store.chapterFinished();
      await _loadChapter(_chapter + 1);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      queue = _ttsQueue();
      if (queue.isEmpty) break;
    }
    if (run == _ttsRun) _stopTts();
  }

  List<String> _chunks(String t) {
    if (t.length <= 3500) return [t];
    final out = <String>[];
    var rest = t;
    while (rest.length > 3500) {
      var cut = rest.lastIndexOf(RegExp(r'[.!?…]\s'), 3500);
      if (cut < 500) cut = 3500;
      out.add(rest.substring(0, cut + 1));
      rest = rest.substring(cut + 1);
    }
    out.add(rest);
    return out;
  }

  void _stopTts() {
    _ttsRun++;
    _tts.stop();
    _applySystem();
    if (mounted) {
      setState(() {
        _speaking = false;
        _ttsPaused = false;
        _ttsText = null;
      });
    }
  }

  void _pauseTts() {
    if (_ttsPaused) {
      final text = _ttsText;
      setState(() => _ttsPaused = false);
      _startTts(fromText: text);
    } else {
      _ttsRun++;
      _tts.stop();
      setState(() => _ttsPaused = true);
    }
  }

  Widget _ttsBar(ReaderTheme t, EdgeInsets pad) => Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, pad.bottom + 34),
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(30), border: Border.all(color: t.line), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))]),
        child: Row(children: [
          Icon(Icons.graphic_eq, color: t.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_ttsPaused ? 'In pausa' : 'Lettura ad alta voce', style: LK.label(10.5, color: t.ink, spacing: 0.4))),
          PopupMenuButton<double>(
            tooltip: 'Velocità',
            color: LK.card,
            initialValue: _ttsRate,
            onSelected: (v) {
              _ttsRate = v;
              _tts.setSpeechRate(v);
              setState(() {});
            },
            itemBuilder: (_) => [
              for (final (v, l) in const [(0.35, 'Lenta'), (0.5, 'Normale'), (0.6, 'Veloce'), (0.75, 'Molto veloce')])
                PopupMenuItem(value: v, child: Text(l, style: LK.body(14))),
            ],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${(_ttsRate * 2).toStringAsFixed(1)}×', style: LK.label(11, color: t.muted, spacing: 0))),
          ),
          IconButton(onPressed: _pauseTts, icon: Icon(_ttsPaused ? Icons.play_arrow : Icons.pause, color: t.ink)),
          IconButton(onPressed: _stopTts, icon: Icon(Icons.close, color: t.muted)),
        ]),
      );

  // ---------- impostazioni ----------

  void _settings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void apply(VoidCallback f, {bool reload = false, bool system = false}) {
          final wasPaged = paged;
          f();
          store.saveReaderPrefs();
          setSheet(() {});
          setState(() {});
          if (system) _applySystem();
          if (reload || wasPaged != paged) _loadChapter(_chapter, frac: _fraction);
        }

        Widget choice(String label, bool on, VoidCallback onTap, {TextStyle? style, Color? dot}) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onTap,
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: LK.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: on ? LK.accent : LK.border, width: on ? 2 : 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (dot != null) ...[
                        Container(width: 16, height: 16, decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: LK.border))),
                        const SizedBox(width: 8),
                      ],
                      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style ?? LK.body(13))),
                    ]),
                  ),
                ),
              ),
            );

        Widget row(List<String> opts, String cur, void Function(String) set, {bool reload = false, bool system = false}) => Row(children: [
              for (final o in opts) choice(o, cur == o, () => apply(() => set(o), reload: reload, system: system)),
            ]);

        Widget label(String t) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 8, top: 10), child: Text(t, style: LK.label(10)));
        Widget section(String t) => Padding(
              padding: const EdgeInsets.only(left: 4, top: 18, bottom: 2),
              child: Text(t, style: LK.display(17, color: LK.accent)),
            );
        Widget toggle(String t, String? sub, bool v, void Function(bool) set, {bool reload = false, bool system = false}) => SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              activeTrackColor: LK.accent,
              title: Text(t, style: LK.body(15)),
              subtitle: sub == null ? null : Text(sub, style: LK.body(12, color: LK.muted)),
              value: v,
              onChanged: (x) => apply(() => set(x), reload: reload, system: system),
            );

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
            children: [
              Padding(padding: const EdgeInsets.only(left: 4), child: Text('Impostazioni di lettura', style: LK.display(21))),
              section('Testo'),
              label('MODALITÀ'),
              row(const ['Pagine', 'Scorrimento'], prefs.mode, (v) => prefs.mode = v),
              label('TEMA${LK.dark ? ' · in modalità notte si usa Notte' : ''}'),
              Row(children: [
                for (final t in ReaderTheme.all) choice(t.name, prefs.theme == t.name, () => apply(() => prefs.theme = t.name), dot: t.bg),
              ]),
              label('DIMENSIONE · ${prefs.size.round()}'),
              Slider(min: 14, max: 26, divisions: 12, value: prefs.size, onChanged: (v) => apply(() => prefs.size = v)),
              label('INTERLINEA · ${prefs.lineHeight.toStringAsFixed(1)}'),
              Slider(min: 1.3, max: 2.2, divisions: 9, value: prefs.lineHeight, onChanged: (v) => apply(() => prefs.lineHeight = v)),
              label('CARATTERE'),
              Row(children: [
                for (final f in const ['Lora', 'Playfair', 'Sans'])
                  choice(f, prefs.font == f, () => apply(() => prefs.font = f), style: readerFont(f, 15, LK.ink, 1.2)),
              ]),
              label('ALLINEAMENTO'),
              row(const ['Giustificato', 'A sinistra'], prefs.justify ? 'Giustificato' : 'A sinistra', (v) => prefs.justify = v == 'Giustificato'),
              toggle('Sillabazione', 'Va a capo dividendo le parole lunghe, per evitare spazi larghi', prefs.hyphenate, (v) => prefs.hyphenate = v, reload: true),
              section('Pagina'),
              label('MARGINI'),
              row(const ['Stretti', 'Normali', 'Larghi'], prefs.margins, (v) => prefs.margins = v),
              label('CAMBIO PAGINA'),
              row(const ['Arricciatura', 'Scorrimento', 'Nessuna'], prefs.animation, (v) => prefs.animation = v),
              toggle('Tocca i bordi per girare pagina', null, prefs.tapEdges, (v) => prefs.tapEdges = v),
              toggle('Inverti i lati', 'Tocco a sinistra per andare avanti', prefs.invertTaps, (v) => prefs.invertTaps = v),
              toggle('Tasti del volume', 'Volume giù: avanti · volume su: indietro', prefs.volumeKeys, (v) => prefs.volumeKeys = v),
              section('Schermo'),
              label('LUMINOSITÀ · ${(prefs.brightness * 100).round()}%'),
              Slider(min: 0.3, max: 1, value: prefs.brightness, onChanged: (v) => apply(() => prefs.brightness = v)),
              label('LUCE CALDA · ${(prefs.warmth * 100).round()}%'),
              Slider(min: 0, max: 1, value: prefs.warmth, onChanged: (v) => apply(() => prefs.warmth = v)),
              toggle('Lettura immersiva', 'Nasconde barra di stato e tasti di sistema', prefs.immersive, (v) => prefs.immersive = v, system: true),
              toggle('Schermo sempre acceso', null, prefs.keepAwake, (v) => prefs.keepAwake = v, system: true),
              label('ORIENTAMENTO'),
              row(const ['Automatico', 'Verticale', 'Orizzontale'], prefs.orientation, (v) => prefs.orientation = v, system: true),
              toggle('Due pagine in orizzontale', 'Come un libro aperto', prefs.twoPages, (v) => prefs.twoPages = v),
            ],
          ),
        );
      }),
    );
  }

  // ---------- disegno ----------

  (String, double) get _texture {
    switch (_theme.name) {
      case 'Pergamena':
        return ('assets/textures/parchment.png', 0.85);
      case 'Notte':
        return ('assets/textures/paper.png', 0.12);
      default:
        return ('assets/textures/paper.png', 0.55);
    }
  }

  ReaderTheme get _theme => ReaderTheme.byName(LK.dark ? 'Notte' : prefs.theme);
  TextAlign get _align => prefs.justify ? TextAlign.justify : TextAlign.left;

  void _chaptersSheet({int tab = 0}) {
    setState(() => _ui = false);
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final bms = [..._notes.bookmarks]..sort((a, b) => a.chapter != b.chapter ? a.chapter.compareTo(b.chapter) : a.frac.compareTo(b.frac));
        final hls = [..._notes.highlights]..sort((a, b) => a.chapter != b.chapter ? a.chapter.compareTo(b.chapter) : a.frac.compareTo(b.frac));
        String chTitle(int c) => c < book.chapters.length ? book.chapters[c].title : '';
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: DefaultTabController(
            length: 3,
            initialIndex: tab,
            child: Column(children: [
              TabBar(
                labelColor: LK.accent,
                unselectedLabelColor: LK.muted,
                indicatorColor: LK.accent,
                labelStyle: LK.label(11, spacing: 1),
                tabs: [
                  const Tab(text: 'CAPITOLI'),
                  Tab(text: 'SEGNALIBRI${bms.isEmpty ? '' : ' ${bms.length}'}'),
                  Tab(text: 'NOTE${hls.isEmpty ? '' : ' ${hls.length}'}'),
                ],
              ),
              Expanded(
                child: TabBarView(children: [
                  ListView.builder(
                    itemCount: book.chapters.length,
                    itemBuilder: (ctx, i) => ListTile(
                      leading: Text('${i + 1}', style: LK.display(15, color: LK.accent)),
                      title: Text(book.chapters[i].title, style: LK.body(15, color: i == _chapter ? LK.accent : LK.ink)),
                      trailing: i == _chapter ? Icon(Icons.bookmark, color: LK.accent, size: 18) : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _loadChapter(i);
                      },
                    ),
                  ),
                  bms.isEmpty
                      ? _emptyTab('Nessun segnalibro. Tocca il nastro in alto mentre leggi per segnare una pagina.')
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: bms.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: LK.line),
                          itemBuilder: (ctx, i) {
                            final bm = bms[i];
                            return ListTile(
                              leading: Icon(Icons.bookmark, color: LK.accent),
                              title: Text(chTitle(bm.chapter), style: LK.label(10, color: LK.accent, spacing: 0.6)),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(bm.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.body(14)),
                                if (bm.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(bm.note, style: LK.body(13, color: LK.muted, style: FontStyle.italic))),
                              ]),
                              trailing: PopupMenuButton<String>(
                                color: LK.card,
                                onSelected: (v) async {
                                  if (v == 'note') {
                                    final n = await _askNote(bm.note);
                                    if (n != null) bm.note = n;
                                  } else {
                                    _notes.bookmarks.remove(bm);
                                  }
                                  await Annotations.I.save(book.id);
                                  setSheet(() {});
                                  setState(() {});
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'note', child: Text(bm.note.isEmpty ? 'Aggiungi nota' : 'Modifica nota', style: LK.body(14))),
                                  PopupMenuItem(value: 'del', child: Text('Elimina', style: LK.body(14))),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                if (bm.excerpt.length > 20) {
                                  _goToText(bm.chapter, bm.excerpt.replaceAll('…', ''), frac: bm.frac);
                                } else {
                                  _loadChapter(bm.chapter, frac: bm.frac);
                                }
                              },
                            );
                          },
                        ),
                  hls.isEmpty
                      ? _emptyTab('Nessuna evidenziazione. Tieni premuta una frase mentre leggi per evidenziarla o scriverci una nota.')
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: hls.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: LK.line),
                          itemBuilder: (ctx, i) {
                            final h = hls[i];
                            return ListTile(
                              leading: Container(width: 6, height: 40, decoration: BoxDecoration(color: Color(Annotations.colors[h.color % 4]), borderRadius: BorderRadius.circular(3))),
                              title: Row(children: [
                                Expanded(child: Text(chTitle(h.chapter), style: LK.label(10, color: LK.accent, spacing: 0.6))),
                                if (h.favorite) Icon(Icons.star, size: 14, color: LK.gold),
                              ]),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('«${h.text}»', maxLines: 3, overflow: TextOverflow.ellipsis, style: LK.body(14, style: FontStyle.italic)),
                                if (h.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(h.note, style: LK.body(13, color: LK.muted))),
                              ]),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline, color: LK.muted, size: 20),
                                onPressed: () async {
                                  _notes.highlights.remove(h);
                                  await Annotations.I.save(book.id);
                                  setSheet(() {});
                                  setState(() {});
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _goToText(h.chapter, h.text, frac: h.frac);
                              },
                            );
                          },
                        ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _emptyTab(String t) => Center(
        child: Padding(padding: const EdgeInsets.all(30), child: Text(t, textAlign: TextAlign.center, style: LK.body(14, color: LK.muted, style: FontStyle.italic))),
      );

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    final st = PageStyle(readerFont(prefs.font, prefs.size, t.ink, prefs.lineHeight), t, MediaQuery.textScalerOf(context), align: _align);
    final n = _pages.length;
    final pad = MediaQuery.of(context).padding;
    final left = paged ? (n - _page - _step) : 0;
    final rem = _remaining;
    final pagesTxt = left <= 0 ? 'Ultima pagina del capitolo' : (left == 1 ? '1 pagina rimasta' : '$left pagine rimaste');
    final status = paged
        ? (rem == null ? '$pagesTxt nel capitolo' : '$pagesTxt · ${_fmtTime(rem.$1)} nel capitolo')
        : (rem == null ? '${(_fraction * 100).round()}% del capitolo' : '${_fmtTime(rem.$1)} nel capitolo');
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: t.bg,
        body: _withPanel(Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.bg,
                image: DecorationImage(image: AssetImage(_texture.$1), repeat: ImageRepeat.repeat, opacity: _texture.$2, scale: 2),
              ),
            ),
          ),
          SafeArea(
            child: Column(children: [
              Expanded(
                child: _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: LK.body(14, color: t.ink))))
                    : _loading && _paras.isEmpty
                        ? Center(child: CircularProgressIndicator(color: t.accent))
                        : paged
                            ? _pagedView(st)
                            : GestureDetector(onTap: () => setState(() => _ui = !_ui), child: _scrollView(st)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(prefs.marginPx, 2, prefs.marginPx, 8),
                child: Row(children: [
                  Expanded(child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.label(10, color: t.muted, spacing: 0.2))),
                  Text('${(book.progress * 100).round()}%', style: LK.label(10, color: t.muted, spacing: 0.2)),
                ]),
              ),
            ]),
          ),
          // Nastro del segnalibro sulla pagina
          if (_bookmarkHere != null)
            Positioned(
              right: prefs.marginPx * 0.6,
              top: pad.top,
              child: IgnorePointer(child: CustomPaint(size: const Size(16, 34), painter: _Ribbon(t.accent))),
            ),
          if (_speaking && !_ui) Positioned(left: 0, right: 0, bottom: 0, child: _ttsBar(t, pad)),
          // Luminosità e luce calda
          IgnorePointer(
            child: Container(color: Colors.black.withValues(alpha: (1 - prefs.brightness) * 0.85)),
          ),
          IgnorePointer(
            child: Container(color: const Color(0xFFFF8A2A).withValues(alpha: prefs.warmth * 0.22)),
          ),
          // Barra superiore
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            top: _ui ? 0 : -(pad.top + 80),
            child: Container(
              padding: EdgeInsets.fromLTRB(4, pad.top + 4, 4, 4),
              decoration: BoxDecoration(color: t.bg, boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12)]),
              child: Row(children: [
                IconButton(icon: LKIcon(LKGlyph.back, color: t.ink), onPressed: () => Navigator.pop(context)),
                Expanded(child: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(16, color: t.ink))),
                if (isWide(context))
                  IconButton(
                    tooltip: 'Pannello della wiki',
                    icon: Icon(_panel ? Icons.view_sidebar : Icons.view_sidebar_outlined, color: _panel ? t.accent : t.ink),
                    onPressed: () => setState(() => _panel = !_panel),
                  ),
                IconButton(tooltip: 'Cerca nel libro', icon: LKIcon(LKGlyph.search, color: t.ink), onPressed: _searchSheet),
                IconButton(
                  tooltip: 'Segnalibro',
                  icon: Icon(_bookmarkHere != null ? Icons.bookmark : Icons.bookmark_border, color: _bookmarkHere != null ? t.accent : t.ink),
                  onPressed: _toggleBookmark,
                ),
                IconButton(tooltip: 'Capitoli, segnalibri e note', icon: LKIcon(LKGlyph.chapters, color: t.ink), onPressed: _chaptersSheet),
                TextButton(onPressed: _settings, child: Text('Aa', style: LK.display(18, color: t.ink))),
                PopupMenuButton<String>(
                  color: LK.card,
                  icon: Icon(Icons.more_vert, color: t.ink),
                  onSelected: (v) {
                    setState(() => _ui = false);
                    if (v == 'recap') _showRecap();
                    if (v == 'tts') _startTts();
                    if (v == 'ask') Navigator.of(context).push(MaterialPageRoute(builder: (_) => AskBookScreen(book: book)));
                    if (v == 'time') Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimelineScreen(book: book)));
                    if (v == 'map') Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorldMapScreen(book: book)));
                    if (v == 'sound') showAmbienceSheet(context);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'tts', child: Text('Leggi ad alta voce', style: LK.body(14))),
                    PopupMenuItem(value: 'recap', child: Text('Riassunto dei capitoli precedenti', style: LK.body(14))),
                    PopupMenuItem(value: 'ask', child: Text('Chiedi al libro', style: LK.body(14))),
                    PopupMenuItem(value: 'time', child: Text('Cronologia degli eventi', style: LK.body(14))),
                    PopupMenuItem(value: 'map', child: Text('Mappa del mondo', style: LK.body(14))),
                    PopupMenuItem(value: 'sound', child: Text('Suoni d\'ambiente', style: LK.body(14))),
                  ],
                ),
              ]),
            ),
          ),
          // Barra inferiore
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: _ui ? 0 : -(pad.bottom + 170),
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, pad.bottom + 10),
              decoration: BoxDecoration(color: t.bg, boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12)]),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  book.chapters.isEmpty ? '' : book.chapters[_chapter].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LK.body(13, color: t.ink, style: FontStyle.italic),
                ),
                if (rem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Fine del libro tra circa ${_fmtTime(rem.$2)}', style: LK.label(10, color: t.muted, spacing: 0.2)),
                  ),
                if (paged && n > 1)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(activeTrackColor: t.accent, thumbColor: t.accent, inactiveTrackColor: t.line),
                    child: Slider(
                      min: 0,
                      max: (n - 1).toDouble(),
                      divisions: n - 1,
                      value: _page.toDouble().clamp(0, (n - 1).toDouble()),
                      label: 'Pagina ${_page + 1}',
                      onChanged: (v) => setState(() => _page = v.round() - (_spread ? v.round() % 2 : 0)),
                      onChangeEnd: (v) {
                        _setPage(v.round() - (_spread ? v.round() % 2 : 0));
                        setState(() => _ui = true);
                      },
                    ),
                  ),
                Row(children: [
                  TextButton.icon(
                    onPressed: _chapter > 0 ? () => _goChapter(-1) : null,
                    icon: Icon(Icons.chevron_left, size: 16, color: t.muted),
                    label: Text('Cap. prec.', style: LK.label(11, color: t.muted, spacing: 0)),
                  ),
                  Expanded(
                    child: Text(
                      paged && n > 0 ? 'Pagina ${_page + 1} di $n' : '${(_fraction * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: LK.label(11, color: t.muted, spacing: 0),
                    ),
                  ),
                  TextButton(
                    onPressed: _chapter < book.chapters.length - 1 ? () => _goChapter(1) : null,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Cap. succ.', style: LK.label(11, color: t.muted, spacing: 0)),
                      Icon(Icons.chevron_right, size: 16, color: t.muted),
                    ]),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
        ),
      ),
    );
  }

  EdgeInsets get _pad => EdgeInsets.fromLTRB(prefs.marginPx, 22, prefs.marginPx, 8);
  static const _gutter = 28.0;

  Widget _pagedView(PageStyle st) {
    return LayoutBuilder(builder: (context, c) {
      _spread = prefs.twoPages && (c.maxWidth > c.maxHeight * 1.1 || c.maxWidth >= 720);
      final colW = _spread ? (c.maxWidth - _gutter) / 2 : c.maxWidth;
      final size = Size(colW - _pad.horizontal, c.maxHeight - _pad.vertical);
      _ensureLayout(size, st);
      final n = _pages.length;
      final isLast = _chapter >= book.chapters.length - 1;
      final spreads = _spread ? (n + 1) ~/ 2 : n;
      Widget pageOf(PageLayout? p) => Padding(padding: _pad, child: ClipRect(child: p == null ? const SizedBox.shrink() : _page2(p, st, size)));
      Widget single(int i) => pageOf(_pages[i]);
      Widget spreadOf(PageLayout? a, PageLayout? b) => Row(children: [
            SizedBox(width: colW, child: pageOf(a)),
            Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: (_gutter - 1) / 2, vertical: 30), color: st.theme.line),
            SizedBox(width: colW, child: pageOf(b)),
          ]);
      // Pagina "oltre il bordo": l'inizio del capitolo dopo o la fine di quello prima, senza cornici.
      Widget neighbour(bool next) {
        final idx = next ? _chapter + 1 : _chapter - 1;
        if (idx < 0 || idx >= book.chapters.length) return const SizedBox.shrink();
        final ps = _pagesOf(idx, size, st);
        if (ps == null || ps.isEmpty) return _spread ? spreadOf(null, null) : pageOf(null);
        if (!_spread) return pageOf(next ? ps.first : ps.last);
        if (next) return spreadOf(ps.first, ps.length > 1 ? ps[1] : null);
        final a = (ps.length - 1) - (ps.length - 1) % 2;
        return spreadOf(ps[a], a + 1 < ps.length ? ps[a + 1] : null);
      }
      return PageTurner(
        key: _turner,
        count: spreads,
        index: (_spread ? _page ~/ 2 : _page).clamp(0, spreads - 1),
        background: st.theme.bg,
        texture: _texture.$1,
        textureOpacity: _texture.$2,
        animation: prefs.animation,
        tapEdges: prefs.tapEdges,
        invertTaps: prefs.invertTaps,
        onChanged: (i) => _setPage(i * _step),
        onBeforeFirst: _beforeFirst,
        onAfterLast: _afterLast,
        canGoBefore: _chapter > 0,
        canGoAfter: !isLast,
        onCenterTap: () => setState(() => _ui = !_ui),
        builder: (i) {
          if (i < 0) return neighbour(false);
          if (i >= spreads) return neighbour(true);
          if (!_spread) return single(i);
          final a = i * 2, b = i * 2 + 1;
          return spreadOf(_pages[a], b < n ? _pages[b] : null);
        },
      );
    });
  }

  Widget _page2(PageLayout page, PageStyle st, Size size) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final b in page.blocks) _block(b, st, size.width),
      ]),
    );
  }

  Widget _block(PageBlock b, PageStyle st, double width) {
    final t = st.theme;
    if (b.chapterTitle != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: PageStyle.titleBottom),
        child: Column(children: [
          SizedBox(height: PageStyle.titleTop, child: Center(child: Text('✦', style: TextStyle(color: t.accent, fontSize: 16)))),
          Text(b.chapterTitle!, textAlign: TextAlign.center, style: st.title),
        ]),
      );
    }
    if (b.image != null) {
      final bytes = _imgBytes[b.image!];
      return Padding(
        padding: EdgeInsets.only(bottom: st.gap),
        child: SizedBox(
          height: b.imageHeight,
          child: bytes == null ? const SizedBox.shrink() : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      );
    }
    if (b.ornament) {
      return SizedBox(height: PageStyle.ornamentHeight, child: Center(child: _Fleuron(color: t.accent)));
    }
    if (b.dropCap != null) {
      final capH = st.scaler.scale(st.capBox);
      return Padding(
        padding: EdgeInsets.only(bottom: b.cut ? 0 : st.gap),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: b.capWidth,
            height: capH,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: capH * 1.4,
              child: Text(b.dropCap!, style: st.cap),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTapUp: (d) => _tapText(b.segs, d, width - b.capWidth, st),
              onLongPressStart: (d) => _lookup(b.segs, d.localPosition, width - b.capWidth, st, _align),
              child: Text.rich(_richSpan(b.segs, t), textAlign: _align, style: st.base),
            ),
          ),
        ]),
      );
    }
    if (b.level > 0) {
      return Padding(
        padding: PageStyle.headingPad,
        child: Text(b.segs.map((s) => s.text).join(), textAlign: TextAlign.center, style: st.heading(b.level)),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: b.cut ? 0 : st.gap),
      child: GestureDetector(
        onTapUp: (d) => _tapText(b.segs, d, width, st),
        onLongPressStart: (d) => _lookup(b.segs, d.localPosition, width, st, _align),
        child: Text.rich(_richSpan(b.segs, t), textAlign: _align, style: st.base),
      ),
    );
  }

  Widget _scrollView(PageStyle st) {
    final t = st.theme;
    return SingleChildScrollView(
      key: ValueKey('scroll$_chapter'),
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(prefs.marginPx, 18, prefs.marginPx, 40),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _block(PageBlock(chapterTitle: book.chapters.isEmpty ? book.title : book.chapters[_chapter].title), st, w),
          for (final p in skipTitleRepeats(_paras, book.chapters.isEmpty ? book.title : book.chapters[_chapter].title))
            if (p.image != null)
              _block(PageBlock(image: p.image, imageHeight: w * (_imgSizes[p.image!]?.aspectRatio == null ? 4 / 3 : 1 / _imgSizes[p.image!]!.aspectRatio)), st, w)
            else if (p.level == 0 && PageStyle.isOrnament(p.plain))
              _block(const PageBlock(ornament: true), st, w)
            else
              _block(PageBlock(segs: p.segs, level: p.level), st, w),
          const SizedBox(height: 24),
          if (_chapter < book.chapters.length - 1)
            Center(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: t.accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
                onPressed: () => _goChapter(1),
                child: Text('CAPITOLO SUCCESSIVO', style: LK.label(12, color: LK.onAccent, spacing: 1.4)),
              ),
            )
          else
            Center(child: Text('Fine', style: LK.display(22, color: t.accent, style: FontStyle.italic))),
        ]);
      }),
    );
  }
}


class _Ribbon extends CustomPainter {
  final Color color;
  _Ribbon(this.color);
  @override
  void paint(Canvas c, Size s) {
    c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width, s.height)
          ..lineTo(s.width / 2, s.height - 6)
          ..lineTo(0, s.height)
          ..close(),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Ribbon old) => old.color != color;
}

/// Fregio al posto degli asterischi tra una scena e l'altra.
class _Fleuron extends StatelessWidget {
  final Color color;
  const _Fleuron({required this.color});

  @override
  Widget build(BuildContext context) {
    Widget diamond(double size, {bool filled = false}) => Transform.rotate(
          angle: 0.785398,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: filled ? color : null, border: Border.all(color: color, width: 1)),
          ),
        );
    Widget line() => Container(
          width: 46,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.7)]),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      line(),
      const SizedBox(width: 8),
      diamond(5),
      const SizedBox(width: 7),
      diamond(8, filled: true),
      const SizedBox(width: 7),
      diamond(5),
      const SizedBox(width: 8),
      Transform.flip(flipX: true, child: line()),
    ]);
  }
}
