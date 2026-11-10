import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/book.dart';
import '../services/epub.dart';
import '../services/library_store.dart';
import '../services/paginator.dart';
import '../theme.dart';
import '../widgets/page_turner.dart';

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
  double _pendingFrac = 0;
  bool _pendingToEnd = false;

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
    _open();
    _watch.start();
    _timeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _flushTime());
  }

  Future<void> _open() async {
    try {
      final bytes = await File(book.filePath).readAsBytes();
      _epub = Epub.open(bytes);
      final start = widget.startChapter ?? book.lastChapter;
      final frac = widget.startChapter == null ? book.lastOffset : 0.0;
      await _loadChapter(start.clamp(0, book.chapters.isEmpty ? 0 : book.chapters.length - 1), frac: frac);
    } catch (e) {
      if (mounted) setState(() => _error = 'Non riesco ad aprire il file: $e');
    }
  }

  Future<void> _loadChapter(int index, {double frac = 0, bool toEnd = false}) async {
    if (_epub == null || book.chapters.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final paras = _epub!.chapterParas(book.chapters[index]);
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

  void _ensureLayout(Size size, PageStyle st) {
    final key = '$_chapter|${size.width.round()}x${size.height.round()}|${prefs.font}|${prefs.size}|${prefs.lineHeight}|${st.theme.name}|${st.scaler.scale(10)}';
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
    _pendingToEnd = false;
  }

  void _setPage(int i) {
    final n = _pages.length;
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
    store.updateBook(book);
    super.dispose();
  }

  // ---------- impostazioni ----------

  void _settings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void apply(VoidCallback f) {
          final wasPaged = paged;
          f();
          store.saveReaderPrefs();
          setSheet(() {});
          setState(() {});
          if (wasPaged != paged) _loadChapter(_chapter, frac: _fraction);
        }

        Widget choice(String label, bool on, VoidCallback onTap, {TextStyle? style, Color? dot}) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onTap,
                  child: Container(
                    height: 48,
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
                      Text(label, style: style ?? LK.body(14)),
                    ]),
                  ),
                ),
              ),
            );

        Widget label(String t) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4), child: Text(t, style: LK.label(10)));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(left: 4, bottom: 10), child: Text('Impostazioni di lettura', style: LK.display(20))),
              label('MODALITÀ'),
              Row(children: [
                for (final m in const ['Pagine', 'Scorrimento']) choice(m, prefs.mode == m, () => apply(() => prefs.mode = m)),
              ]),
              const SizedBox(height: 12),
              label('TEMA'),
              Row(children: [
                for (final t in ReaderTheme.all) choice(t.name, prefs.theme == t.name, () => apply(() => prefs.theme = t.name), dot: t.bg),
              ]),
              const SizedBox(height: 12),
              label('DIMENSIONE TESTO · ${prefs.size.round()}'),
              Slider(min: 14, max: 26, divisions: 12, value: prefs.size, onChanged: (v) => apply(() => prefs.size = v)),
              label('INTERLINEA · ${prefs.lineHeight.toStringAsFixed(1)}'),
              Slider(min: 1.3, max: 2.2, divisions: 9, value: prefs.lineHeight, onChanged: (v) => apply(() => prefs.lineHeight = v)),
              label('CARATTERE'),
              Row(children: [
                for (final f in const ['Lora', 'Playfair', 'Sans'])
                  choice(f, prefs.font == f, () => apply(() => prefs.font = f), style: readerFont(f, 15, LK.ink, 1.2)),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  // ---------- disegno ----------

  ReaderTheme get _theme => ReaderTheme.byName(LK.dark ? 'Notte' : prefs.theme);

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
    final st = PageStyle(readerFont(prefs.font, prefs.size, t.ink, prefs.lineHeight), t, MediaQuery.textScalerOf(context));
    final n = _pages.length;
    final pad = MediaQuery.of(context).padding;
    final left = paged ? (n - _page - 1) : 0;
    final status = paged
        ? (left <= 0 ? 'Ultima pagina del capitolo' : (left == 1 ? '1 pagina rimasta nel capitolo' : '$left pagine rimaste nel capitolo'))
        : '${(_fraction * 100).round()}% del capitolo';
    return Scaffold(
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
              padding: const EdgeInsets.fromLTRB(26, 2, 26, 8),
              child: Row(children: [
                Expanded(child: Text(status, style: LK.label(10, color: t.muted, spacing: 0.2))),
                Text('${(book.progress * 100).round()}%', style: LK.label(10, color: t.muted, spacing: 0.2)),
              ]),
            ),
          ]),
        ),
        // Barra superiore
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          left: 0,
          right: 0,
          top: _ui ? 0 : -(pad.top + 70),
          child: Container(
            padding: EdgeInsets.fromLTRB(4, pad.top + 4, 4, 4),
            decoration: BoxDecoration(color: t.bg, boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12)]),
            child: Row(children: [
              IconButton(icon: Icon(Icons.arrow_back, color: t.ink), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(16, color: t.ink)),
              ),
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
          bottom: _ui ? 0 : -(pad.bottom + 140),
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
              if (paged && n > 1)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(activeTrackColor: t.accent, thumbColor: t.accent, inactiveTrackColor: t.line),
                  child: Slider(
                    min: 0,
                    max: (n - 1).toDouble(),
                    divisions: n - 1,
                    value: _page.toDouble().clamp(0, (n - 1).toDouble()),
                    label: 'Pagina ${_page + 1}',
                    onChanged: (v) => setState(() => _page = v.round()),
                    onChangeEnd: (v) {
                      _setPage(v.round());
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
    );
  }

  static const _pad = EdgeInsets.fromLTRB(26, 22, 26, 8);

  Widget _pagedView(PageStyle st) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth - _pad.horizontal, c.maxHeight - _pad.vertical);
      _ensureLayout(size, st);
      final n = _pages.length;
      final isLast = _chapter >= book.chapters.length - 1;
      return PageTurner(
        count: n,
        index: _page.clamp(0, n - 1),
        background: st.theme.bg,
        onChanged: _setPage,
        onBeforeFirst: _beforeFirst,
        onAfterLast: _afterLast,
        canGoBefore: _chapter > 0,
        canGoAfter: !isLast,
        onCenterTap: () => setState(() => _ui = !_ui),
        builder: (i) {
          if (i < 0) return _edge(st, 'Capitolo precedente');
          if (i >= n) return _edge(st, isLast ? 'Fine' : 'Capitolo successivo');
          return Padding(padding: _pad, child: ClipRect(child: _page2(_pages[i], st, size)));
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
      child: Text.rich(PageStyle.span(b.segs), textAlign: TextAlign.justify, style: st.base),
    );
  }

  Widget _scrollView(PageStyle st) {
    final t = st.theme;
    return SingleChildScrollView(
      key: ValueKey('scroll$_chapter'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 40),
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
