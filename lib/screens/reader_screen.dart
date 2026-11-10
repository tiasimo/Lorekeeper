import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/epub.dart';
import '../services/library_store.dart';
import '../theme.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  final int? startChapter;
  const ReaderScreen({super.key, required this.book, this.startChapter});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final store = LibraryStore.I;
  final _scroll = ScrollController();
  Epub? _epub;
  List<Para> _paras = const [];
  int _chapter = 0;
  double _fraction = 0;
  String? _error;
  final _watch = Stopwatch();
  Timer? _timeTimer;

  Book get book => widget.book;
  ReaderPrefs get prefs => store.reader;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _open();
    _watch.start();
    _timeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _flushTime());
  }

  Future<void> _open() async {
    try {
      final bytes = await File(book.filePath).readAsBytes();
      _epub = Epub.open(bytes);
      final start = widget.startChapter ?? book.lastChapter;
      final offset = widget.startChapter == null ? book.lastOffset : 0.0;
      _load(start.clamp(0, book.chapters.isEmpty ? 0 : book.chapters.length - 1), offset);
    } catch (e) {
      setState(() => _error = 'Non riesco ad aprire il file: $e');
    }
  }

  void _load(int index, double offset) {
    if (_epub == null || book.chapters.isEmpty) return;
    setState(() {
      _chapter = index;
      _paras = _epub!.chapter(book.chapters[index].href);
      _fraction = offset;
    });
    store.setProgress(book, index, offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo((max * offset).clamp(0.0, max));
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final f = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((f - _fraction).abs() > 0.004) {
      setState(() => _fraction = f);
      store.setProgress(book, _chapter, f);
    }
  }

  void _go(int delta) {
    final next = _chapter + delta;
    if (next < 0 || next >= book.chapters.length) return;
    if (delta > 0) store.chapterFinished();
    _load(next, 0);
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

  void _settings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void apply(VoidCallback f) {
          f();
          store.saveReaderPrefs();
          setSheet(() {});
          setState(() {});
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: on ? LK.accent : const Color(0xFFE6DED3), width: on ? 2 : 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (dot != null) ...[
                        Container(width: 16, height: 16, decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFBFB3A5)))),
                        const SizedBox(width: 8),
                      ],
                      Text(label, style: style ?? LK.body(14)),
                    ]),
                  ),
                ),
              ),
            );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(left: 4, bottom: 14), child: Text('Impostazioni di lettura', style: LK.display(20))),
              Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text('TEMA', style: LK.label(10))),
              Row(children: [
                for (final t in ReaderTheme.all) choice(t.name, prefs.theme == t.name, () => apply(() => prefs.theme = t.name), dot: t.bg),
              ]),
              const SizedBox(height: 16),
              Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text('DIMENSIONE TESTO · ${prefs.size.round()}', style: LK.label(10))),
              Slider(min: 14, max: 26, divisions: 12, value: prefs.size, onChanged: (v) => apply(() => prefs.size = v)),
              Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text('INTERLINEA · ${prefs.lineHeight.toStringAsFixed(1)}', style: LK.label(10))),
              Slider(min: 1.3, max: 2.2, divisions: 9, value: prefs.lineHeight, onChanged: (v) => apply(() => prefs.lineHeight = v)),
              Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text('CARATTERE', style: LK.label(10))),
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

  @override
  Widget build(BuildContext context) {
    final t = ReaderTheme.byName(prefs.theme);
    final base = readerFont(prefs.font, prefs.size, t.ink, prefs.lineHeight);
    final title = book.chapters.isEmpty ? book.title : book.chapters[_chapter].title;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
            child: Row(children: [
              IconButton(icon: Icon(Icons.chevron_left, color: t.ink), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Text(
                  '${book.title.toUpperCase()} · ${_chapter + 1}/${book.chapters.length}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LK.label(10, color: t.muted, spacing: 1.6),
                ),
              ),
              TextButton(onPressed: _settings, child: Text('Aa', style: LK.display(18, color: t.ink))),
            ]),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: LK.body(14, color: t.ink))))
                : _epub == null
                    ? Center(child: CircularProgressIndicator(color: t.accent))
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
                        children: [
                          Center(child: Text('✦', style: TextStyle(color: t.accent, fontSize: 16))),
                          const SizedBox(height: 8),
                          Text(title, textAlign: TextAlign.center, style: LK.display(24, color: t.ink).copyWith(height: 1.25)),
                          const SizedBox(height: 22),
                          if (_paras.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 60),
                              child: Center(child: Text('· · ·', style: LK.display(24, color: t.muted))),
                            ),
                          for (final p in _paras) _para(p, base, t),
                          const SizedBox(height: 30),
                          if (_chapter < book.chapters.length - 1)
                            Center(
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: t.accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
                                onPressed: () => _go(1),
                                child: Text('CAPITOLO SUCCESSIVO', style: LK.label(12, color: Colors.white, spacing: 1.4)),
                              ),
                            )
                          else
                            Center(child: Text('Fine', style: LK.display(22, color: t.accent, style: FontStyle.italic))),
                        ],
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: _fraction, minHeight: 3, backgroundColor: t.line, color: t.accent),
              ),
              Row(children: [
                TextButton.icon(
                  onPressed: _chapter > 0 ? () => _go(-1) : null,
                  icon: Icon(Icons.chevron_left, size: 16, color: t.muted),
                  label: Text('Prec.', style: LK.label(11, color: t.muted, spacing: 0)),
                ),
                Expanded(
                  child: Text('${(_fraction * 100).round()}% del capitolo', textAlign: TextAlign.center, style: LK.label(11, color: t.muted, spacing: 0)),
                ),
                TextButton(
                  onPressed: _chapter < book.chapters.length - 1 ? () => _go(1) : null,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Succ.', style: LK.label(11, color: t.muted, spacing: 0)),
                    Icon(Icons.chevron_right, size: 16, color: t.muted),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _para(Para p, TextStyle base, ReaderTheme t) {
    if (p.level > 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 14),
        child: Text(p.plain, textAlign: TextAlign.center, style: LK.display(p.level <= 2 ? 21 : 18, color: t.ink)),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: prefs.size * 0.75),
      child: Text.rich(
        TextSpan(children: [
          for (final s in p.segs)
            TextSpan(
              text: s.text,
              style: TextStyle(fontStyle: s.italic ? FontStyle.italic : null, fontWeight: s.bold ? FontWeight.w700 : null),
            ),
        ]),
        textAlign: TextAlign.justify,
        style: base,
      ),
    );
  }
}
