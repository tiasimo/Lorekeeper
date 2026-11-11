import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/book.dart';
import '../services/epub.dart';
import '../services/hyphen.dart';
import '../services/library_store.dart';
import '../services/paginator.dart';
import '../theme.dart';
import '../widgets/page_turner.dart';
import '../widgets/word_sheet.dart';

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
  final Map<String, Uint8List> _imgBytes = {};
  final Map<String, Size> _imgSizes = {};

  // Modalità pagine
  List<PageLayout> _pages = const [];
  String _layoutKey = '';
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

  Book get book => widget.book;
  ReaderPrefs get prefs => store.reader;
  bool get paged => prefs.mode != 'Scorrimento';

  @override
  void initState() {
    super.initState();
    _applySystem();
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

  Future<void> _loadChapter(int index, {double frac = 0, bool toEnd = false}) async {
    if (_epub == null || book.chapters.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final paras = _prepare(_epub!.chapterParas(book.chapters[index]));
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
    final key = '$_chapter|${size.width.round()}x${size.height.round()}|${prefs.font}|${prefs.size}|${prefs.lineHeight}|'
        '${st.theme.name}|${st.scaler.scale(10)}|${prefs.justify}|${prefs.hyphenate}|$_spread';
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
    _flushTime();
    _timeTimer?.cancel();
    _scroll.dispose();
    _focus.dispose();
    _restoreSystem();
    store.updateBook(book);
    super.dispose();
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
    showWordSheet(context, word: word, sentence: sentence.isEmpty ? plain : sentence, bookTitle: book.title);
  }

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

  ReaderTheme get _theme => ReaderTheme.byName(LK.dark ? 'Notte' : prefs.theme);
  TextAlign get _align => prefs.justify ? TextAlign.justify : TextAlign.left;

  void _chaptersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListView.builder(
          controller: scroll,
          itemCount: book.chapters.length,
          itemBuilder: (ctx, i) => ListTile(
            leading: Text('${i + 1}', style: LK.display(15, color: LK.accent)),
            title: Text(book.chapters[i].title, style: LK.body(15, color: i == _chapter ? LK.accent : LK.ink)),
            trailing: i == _chapter ? Icon(Icons.bookmark, color: LK.accent, size: 18) : null,
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _ui = false);
              _loadChapter(i);
            },
          ),
        ),
      ),
    );
  }

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
        body: Stack(children: [
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
                IconButton(icon: Icon(Icons.arrow_back, color: t.ink), onPressed: () => Navigator.pop(context)),
                Expanded(child: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(16, color: t.ink))),
                IconButton(tooltip: 'Capitoli', icon: Icon(Icons.format_list_bulleted, color: t.ink), onPressed: _chaptersSheet),
                TextButton(onPressed: _settings, child: Text('Aa', style: LK.display(18, color: t.ink))),
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
    );
  }

  EdgeInsets get _pad => EdgeInsets.fromLTRB(prefs.marginPx, 22, prefs.marginPx, 8);
  static const _gutter = 28.0;

  Widget _pagedView(PageStyle st) {
    return LayoutBuilder(builder: (context, c) {
      _spread = prefs.twoPages && c.maxWidth > c.maxHeight * 1.1;
      final colW = _spread ? (c.maxWidth - _gutter) / 2 : c.maxWidth;
      final size = Size(colW - _pad.horizontal, c.maxHeight - _pad.vertical);
      _ensureLayout(size, st);
      final n = _pages.length;
      final isLast = _chapter >= book.chapters.length - 1;
      final spreads = _spread ? (n + 1) ~/ 2 : n;
      Widget single(int i) => Padding(padding: _pad, child: ClipRect(child: _page2(_pages[i], st, size)));
      return PageTurner(
        key: _turner,
        count: spreads,
        index: (_spread ? _page ~/ 2 : _page).clamp(0, spreads - 1),
        background: st.theme.bg,
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
          if (i < 0) return _edge(st, 'Capitolo precedente');
          if (i >= spreads) return _edge(st, isLast ? 'Fine' : 'Capitolo successivo');
          if (!_spread) return single(i);
          final a = i * 2, b = i * 2 + 1;
          return Row(children: [
            SizedBox(width: colW, child: single(a)),
            Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: (_gutter - 1) / 2, vertical: 30), color: st.theme.line),
            SizedBox(width: colW, child: b < n ? single(b) : const SizedBox.shrink()),
          ]);
        },
      );
    });
  }

  Widget _edge(PageStyle st, String text) => Center(child: Text(text, style: LK.display(22, color: st.theme.muted, style: FontStyle.italic)));

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
    if (b.level > 0) {
      return Padding(
        padding: PageStyle.headingPad,
        child: Text(b.segs.map((s) => s.text).join(), textAlign: TextAlign.center, style: st.heading(b.level)),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: b.cut ? 0 : st.gap),
      child: GestureDetector(
        onLongPressStart: (d) => _lookup(b.segs, d.localPosition, width, st, _align),
        child: Text.rich(PageStyle.span(b.segs), textAlign: _align, style: st.base),
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
          for (final p in _paras)
            if (p.image != null)
              _block(PageBlock(image: p.image, imageHeight: w * (_imgSizes[p.image!]?.aspectRatio == null ? 4 / 3 : 1 / _imgSizes[p.image!]!.aspectRatio)), st, w)
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
