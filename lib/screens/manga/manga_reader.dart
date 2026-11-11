import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../widgets/manga_image.dart';

/// Modi di lettura dei manga.
const _modes = ['Verticale', 'Destra → sinistra', 'Sinistra → destra'];

class MangaReader extends StatefulWidget {
  final SavedManga manga;
  final Source source;
  final MChapter chapter;
  final int startPage;
  const MangaReader({super.key, required this.manga, required this.source, required this.chapter, this.startPage = 0});
  @override
  State<MangaReader> createState() => _MangaReaderState();
}

class _MangaReaderState extends State<MangaReader> {
  final store = MangaStore.I;
  SavedManga get m => widget.manga;
  late MChapter _ch;
  List<PageUrl> _pages = [];
  bool _loading = true;
  String? _error;
  int _page = 0;
  bool _ui = false;
  int _mode = 1; // verticale, RTL, LTR
  PageController? _pc;
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  int _run = 0;

  List<MChapter> get _ordered => m.ordered;
  int get _index => _ordered.indexWhere((c) => c.url == _ch.url);
  MChapter? get _next => _index >= 0 && _index + 1 < _ordered.length ? _ordered[_index + 1] : null;
  MChapter? get _prev => _index > 0 ? _ordered[_index - 1] : null;

  @override
  void initState() {
    super.initState();
    _ch = widget.chapter;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    SharedPreferences.getInstance().then((p) {
      final mode = p.getInt('manga.mode.${m.key}') ?? p.getInt('manga.mode') ?? 1;
      if (mounted) setState(() => _mode = mode.clamp(0, 2));
      _open(_ch, page: widget.startPage);
    });
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _pc?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open(MChapter c, {int page = 0, bool fromEnd = false}) async {
    final my = ++_run;
    setState(() {
      _ch = c;
      _loading = true;
      _error = null;
      _pages = [];
      _keys.clear();
    });
    try {
      final pages = await widget.source.methods.getPageList(c.toEpisode());
      if (my != _run || !mounted) return;
      final start = fromEnd ? pages.length - 1 : page.clamp(0, pages.isEmpty ? 0 : pages.length - 1);
      _pc?.dispose();
      _pc = PageController(initialPage: start);
      setState(() {
        _pages = pages;
        _page = start;
        _loading = false;
      });
      if (_mode == 0 && start > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpVertical(start));
      } else if (_mode == 0 && _scroll.hasClients) {
        _scroll.jumpTo(0);
      }
      _prefetch(start);
      store.setProgress(m, c, start);
    } catch (e) {
      if (my == _run && mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _prefetch(int from) {
    for (var i = from + 1; i <= from + 3 && i < _pages.length; i++) {
      MangaImages.get(_pages[i].url, headers: _pages[i].headers, sourceId: m.sourceId, managerId: m.managerId).catchError((_) => null);
    }
  }

  void _onPage(int i) {
    setState(() => _page = i);
    _prefetch(i);
    store.setProgress(m, _ch, i);
    if (i >= _pages.length - 1) store.markRead(m, _ch);
  }

  void _onScroll() {
    if (_mode != 0 || _pages.isEmpty || !_scroll.hasClients) return;
    // pagina visibile: la prima il cui fondo supera la metà dello schermo
    final h = MediaQuery.of(context).size.height;
    var cur = _page;
    for (final e in _keys.entries) {
      final ctx = e.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= h * 0.5 && top + box.size.height > h * 0.5) {
        cur = e.key;
        break;
      }
    }
    if (cur != _page) _onPage(cur);
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 20) store.markRead(m, _ch);
  }

  void _jumpVertical(int i) {
    final ctx = _keys[i]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx);
    } else if (_scroll.hasClients) {
      // stima: pagine di altezza simile
      _scroll.jumpTo((_scroll.position.maxScrollExtent * i / _pages.length).clamp(0, _scroll.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c2 = _keys[i]?.currentContext;
        if (c2 != null) Scrollable.ensureVisible(c2);
      });
    }
  }

  void _goTo(int i) {
    if (_pages.isEmpty) return;
    i = i.clamp(0, _pages.length - 1);
    if (_mode == 0) {
      _jumpVertical(i);
      _onPage(i);
    } else {
      _pc?.jumpToPage(i);
    }
  }

  /// Tocchi ai lati per girare pagina (al centro mostra i comandi).
  void _tap(TapUpDetails d) {
    final w = MediaQuery.of(context).size.width;
    final x = d.globalPosition.dx;
    if (_mode == 0 || (x > w * 0.3 && x < w * 0.7)) {
      setState(() => _ui = !_ui);
      return;
    }
    final forward = _mode == 1 ? x < w * 0.3 : x > w * 0.7;
    _step(forward ? 1 : -1);
  }

  void _step(int dir) {
    if (_ui) setState(() => _ui = false);
    final t = _page + dir;
    if (t >= _pages.length) {
      store.markRead(m, _ch);
      final n = _next;
      if (n != null) _open(n);
      return;
    }
    if (t < 0) {
      final p = _prev;
      if (p != null) _open(p, fromEnd: true);
      return;
    }
    _pc?.animateToPage(t, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _setMode(int i) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('manga.mode.${m.key}', i);
    await p.setInt('manga.mode', i);
    final page = _page;
    _pc?.dispose();
    _pc = PageController(initialPage: page);
    setState(() => _mode = i);
    if (i == 0) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpVertical(page));
  }

  Widget _image(int i, {BoxFit fit = BoxFit.contain}) {
    final pg = _pages[i];
    return MangaImage(
      pg.url,
      headers: pg.headers,
      sourceId: m.sourceId,
      managerId: m.managerId,
      fit: fit,
      placeholder: Container(
        height: _mode == 0 ? MediaQuery.of(context).size.height * 0.8 : null,
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE2B84B))),
          const SizedBox(height: 10),
          Text('${i + 1}', style: LK.label(11, color: const Color(0xFF8A7E75), spacing: 0.4)),
        ]),
      ),
    );
  }

  Widget _chapterEnd() {
    final n = _next;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Fine di «${_ch.name}»', textAlign: TextAlign.center, style: LK.display(16, color: const Color(0xFFEFE4D2))),
        const SizedBox(height: 14),
        if (n != null)
          FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.bordeaux), onPressed: () => _open(n), child: Text('Capitolo successivo: ${n.name}', textAlign: TextAlign.center))
        else
          Text('Sei in pari con questo manga.', style: LK.body(14, color: const Color(0xFFB8AC9C), style: FontStyle.italic)),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE2B84B)));
    if (_error != null || _pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error == null ? 'Il capitolo non ha pagine.' : 'Non riesco ad aprire il capitolo:\n$_error',
                textAlign: TextAlign.center, style: LK.body(14, color: const Color(0xFFEFE4D2))),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: () => _open(_ch, page: _page), child: const Text('Riprova')),
          ]),
        ),
      );
    }
    if (_mode == 0) {
      return GestureDetector(
        onTapUp: _tap,
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 3,
          panEnabled: false,
          child: ListView.builder(
            controller: _scroll,
            cacheExtent: 2500,
            itemCount: _pages.length + 1,
            itemBuilder: (context, i) {
              if (i == _pages.length) return _chapterEnd();
              final key = _keys[i] ??= GlobalKey();
              return KeyedSubtree(key: key, child: _image(i, fit: BoxFit.fitWidth));
            },
          ),
        ),
      );
    }
    return GestureDetector(
      onTapUp: _tap,
      child: PageView.builder(
        controller: _pc,
        reverse: _mode == 1,
        itemCount: _pages.length + 1,
        onPageChanged: (i) {
          if (i == _pages.length) {
            store.markRead(m, _ch);
            setState(() => _page = i);
          } else {
            _onPage(i);
          }
        },
        itemBuilder: (context, i) {
          if (i == _pages.length) return Center(child: _chapterEnd());
          return InteractiveViewer(minScale: 1, maxScale: 4, child: Center(child: _image(i)));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    const ink = Color(0xFFEFE4D2);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: _body()),
        // numero di pagina discreto
        if (!_ui && _pages.isNotEmpty && _page < _pages.length)
          Positioned(
            bottom: pad.bottom + 6,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(10)),
                  child: Text('${_page + 1} / ${_pages.length}', style: LK.label(10, color: ink, spacing: 0.4)),
                ),
              ),
            ),
          ),
        // comandi
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          top: _ui ? 0 : -140,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(4, pad.top + 4, 8, 8),
            color: const Color(0xE61C1714),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: ink), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(15, color: ink)),
                  Text(_ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(12.5, color: const Color(0xFFB8AC9C))),
                ]),
              ),
              PopupMenuButton<int>(
                tooltip: 'Modo di lettura',
                icon: const Icon(Icons.chrome_reader_mode_outlined, color: ink),
                color: LK.card,
                initialValue: _mode,
                onSelected: _setMode,
                itemBuilder: (_) => [for (var i = 0; i < _modes.length; i++) PopupMenuItem(value: i, child: Text(_modes[i], style: LK.body(14)))],
              ),
            ]),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          bottom: _ui ? 0 : -160,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(8, 8, 8, pad.bottom + 10),
            color: const Color(0xE61C1714),
            child: Row(children: [
              IconButton(
                tooltip: 'Capitolo precedente',
                icon: Icon(Icons.skip_previous, color: _prev == null ? const Color(0x55EFE4D2) : ink),
                onPressed: _prev == null ? null : () => _open(_prev!),
              ),
              Text('${_pages.isEmpty ? 0 : (_page + 1).clamp(1, _pages.length)}', style: LK.label(11, color: ink, spacing: 0)),
              Expanded(
                child: Directionality(
                  textDirection: _mode == 1 ? TextDirection.rtl : TextDirection.ltr,
                  child: Slider(
                    value: _pages.isEmpty ? 0 : _page.clamp(0, _pages.length - 1).toDouble(),
                    min: 0,
                    max: _pages.length <= 1 ? 1 : (_pages.length - 1).toDouble(),
                    divisions: _pages.length <= 1 ? null : _pages.length - 1,
                    activeColor: const Color(0xFFE2B84B),
                    inactiveColor: const Color(0x44EFE4D2),
                    onChanged: _pages.length <= 1 ? null : (v) => _goTo(v.round()),
                  ),
                ),
              ),
              Text('${_pages.length}', style: LK.label(11, color: ink, spacing: 0)),
              IconButton(
                tooltip: 'Capitolo successivo',
                icon: Icon(Icons.skip_next, color: _next == null ? const Color(0x55EFE4D2) : ink),
                onPressed: _next == null ? null : () => _open(_next!),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
