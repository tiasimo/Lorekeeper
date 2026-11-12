import 'dart:async';
import 'dart:io';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../services/ambience.dart';
import '../../services/home_widget_sync.dart';
import '../../services/library_store.dart';
import '../../services/manga_downloads.dart';
import '../../services/manga_prefs.dart';
import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../widgets/manga_image.dart';
import '../../widgets/manga_page.dart';
import 'manga_reader_sheet.dart';

/// Un elemento sfogliabile: una pagina intera o metà di una pagina larga.
class _Item {
  final int page;
  final int half; // 0 intera, 1 sinistra, 2 destra
  final int? page2; // seconda pagina affiancata (in orizzontale)
  const _Item(this.page, [this.half = 0, this.page2]);
}

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
  MangaPrefs _p = MangaPrefs();
  int _seriesMode = 0, _seriesRot = 0;

  late MChapter _ch;
  List<PageUrl> _pages = [];
  List<_Item> _items = [];
  final Set<int> _splitDone = {};
  bool _loading = true;
  String? _error;
  int _pos = 0; // indice in _items (o pagina, in verticale lungo)
  bool _ui = false;
  PageController? _pc;
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  final _zoom = TransformationController();
  int _run = 0;
  bool _flash = false;
  bool _double = false; // due pagine affiancate
  // capitolo successivo caricato in anticipo (lettura continua)
  String? _preUrl;
  List<PageUrl>? _prePages;
  bool _autoNextDone = false;
  Timer? _clock;

  int get _mode => _seriesMode == 0 ? _p.defaultMode : _seriesMode;
  int get _rotation => _seriesRot == 0 ? _p.defaultRotation : _seriesRot;
  bool get _webtoon => _mode >= 4;
  bool get _rtl => _mode == 2;
  int get _page => _items.isEmpty ? 0 : _items[_pos.clamp(0, _items.length - 1)].page;

  Color get _bg => switch (_p.background) {
        1 => const Color(0xFF202125),
        2 => Colors.white,
        3 => LK.dark ? Colors.black : Colors.white,
        _ => Colors.black,
      };

  List<MChapter> get _ordered => m.ordered;
  int get _index => _ordered.indexWhere((c) => c.url == _ch.url);
  MChapter? get _next => _index >= 0 && _index + 1 < _ordered.length ? _ordered[_index + 1] : null;
  MChapter? get _prev => _index > 0 ? _ordered[_index - 1] : null;

  @override
  void initState() {
    super.initState();
    _ch = widget.chapter;
    Ambience.I.start();
    _scroll.addListener(_onScroll);
    // tempo di lettura dei manga per le statistiche
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_loading && _error == null) LibraryStore.I.addMangaTime(30);
    });
    () async {
      _p = await MangaPrefs.load();
      final (sm, sr) = await MangaPrefs.series(m.key);
      _seriesMode = sm;
      _seriesRot = sr;
      _applySystem();
      if (mounted) setState(() {});
      _open(_ch, page: widget.startPage);
    }();
  }

  @override
  void dispose() {
    Ambience.I.stop();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WakelockPlus.disable();
    _clock?.cancel();
    HomeWidgetSync.update();
    _pc?.dispose();
    _scroll.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _applySystem() {
    SystemChrome.setEnabledSystemUIMode(_p.fullscreen && !_ui ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    _p.keepScreenOn ? WakelockPlus.enable() : WakelockPlus.disable();
    final o = switch (_rotation) {
      2 => [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
      3 => [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      4 => [DeviceOrientation.portraitUp],
      5 => [DeviceOrientation.landscapeLeft],
      6 => [DeviceOrientation.portraitDown],
      _ => DeviceOrientation.values,
    };
    SystemChrome.setPreferredOrientations(o);
  }

  void _toggleUi([bool? v]) {
    setState(() => _ui = v ?? !_ui);
    _applySystem();
  }

  // ---------------- capitoli e pagine ----------------

  /// Carica in anticipo l'elenco delle pagine del capitolo successivo e le prime immagini.
  void _preloadNext() {
    final n = _next;
    if (!_p.continuous || n == null || _preUrl == n.url) return;
    _preUrl = n.url;
    _prePages = null;
    () async {
      try {
        final pages = MangaDownloads.I.localPages(m, n) ?? await widget.source.methods.getPageList(n.toEpisode());
        if (_preUrl != n.url) return;
        _prePages = pages;
        for (final pg in pages.take(3)) {
          MangaImages.get(pg.url, headers: pg.headers, sourceId: m.sourceId, managerId: m.managerId).catchError((_) => null);
        }
      } catch (_) {
        if (_preUrl == n.url) _preUrl = null;
      }
    }();
  }

  Future<void> _open(MChapter c, {int page = 0, bool fromEnd = false}) async {
    final my = ++_run;
    _autoNextDone = false;
    final ready = c.url == _preUrl ? _prePages : null;
    if (ready != null) {
      // già pronto: niente attesa, si continua a leggere
      _preUrl = null;
      _prePages = null;
      _ch = c;
      _pages = ready;
      _splitDone.clear();
      _keys.clear();
      _items = _buildItems();
      final start = fromEnd ? (_items.isEmpty ? 0 : _items.length - 1) : page.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
      _pc?.dispose();
      _pc = PageController(initialPage: start);
      setState(() {
        _pos = start;
        _loading = false;
        _error = null;
      });
      if (_webtoon) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(0);
        });
      }
      _prefetch(start);
      store.setProgress(m, c, start);
      return;
    }
    setState(() {
      _ch = c;
      _loading = true;
      _error = null;
      _pages = [];
      _items = [];
      _splitDone.clear();
      _keys.clear();
    });
    try {
      final pages = MangaDownloads.I.localPages(m, c) ?? await widget.source.methods.getPageList(c.toEpisode());
      if (my != _run || !mounted) return;
      _pages = pages;
      _items = _buildItems();
      final start = fromEnd ? (_items.isEmpty ? 0 : _items.length - 1) : page.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
      _pc?.dispose();
      _pc = PageController(initialPage: start);
      setState(() {
        _pos = start;
        _loading = false;
      });
      if (_webtoon) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (start > 0) {
            _jumpVertical(start);
          } else if (_scroll.hasClients) {
            _scroll.jumpTo(0);
          }
        });
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

  /// Una pagina larga si divide in due (in ordine di lettura).
  void _onInfo(int page, PageInfo info) {
    if (_webtoon || _double || !_p.splitWide || !info.wide || _splitDone.contains(page)) return;
    _splitDone.add(page);
    final i = _items.indexWhere((x) => x.page == page && x.half == 0);
    if (i < 0) return;
    final first = _rtl ? 2 : 1, second = _rtl ? 1 : 2;
    setState(() {
      _items.replaceRange(i, i + 1, [_Item(page, first), _Item(page, second)]);
      if (i < _pos) {
        _pos++;
        _pc?.jumpToPage(_pos);
      }
    });
  }

  void _onPos(int i) {
    final wasLast = i >= _items.length;
    if (_zoom.value != Matrix4.identity()) _zoom.value = Matrix4.identity();
    setState(() => _pos = i);
    if (wasLast) {
      store.markRead(m, _ch);
      if ((_p.continuous || !_p.alwaysTransition) && _next != null) _open(_next!);
      return;
    }
    if (i >= _items.length - 4) _preloadNext();
    _prefetch(_page);
    store.setProgress(m, _ch, i);
    if (i >= _items.length - 1) store.markRead(m, _ch);
    if (_p.flashOnPage) {
      setState(() => _flash = true);
      Timer(const Duration(milliseconds: 90), () {
        if (mounted) setState(() => _flash = false);
      });
    }
  }

  void _onScroll() {
    if (!_webtoon || _pages.isEmpty || !_scroll.hasClients) return;
    final h = MediaQuery.of(context).size.height;
    var cur = _pos;
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
    if (cur != _pos) {
      setState(() => _pos = cur);
      _prefetch(cur);
      store.setProgress(m, _ch, cur);
    }
    if (cur >= _items.length - 4) _preloadNext();
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 20) {
      store.markRead(m, _ch);
      // in verticale: arrivato in fondo si passa da soli al successivo
      final n = _next;
      if (_p.continuous && n != null && !_autoNextDone) {
        _autoNextDone = true;
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted && _ch.url != n.url && _scroll.hasClients && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 60) {
            _open(n);
          } else {
            _autoNextDone = false;
          }
        });
      }
    }
  }

  void _jumpVertical(int i) {
    final ctx = _keys[i]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx);
    } else if (_scroll.hasClients) {
      _scroll.jumpTo((_scroll.position.maxScrollExtent * i / _pages.length).clamp(0, _scroll.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c2 = _keys[i]?.currentContext;
        if (c2 != null) Scrollable.ensureVisible(c2);
      });
    }
  }

  void _goTo(int i) {
    if (_items.isEmpty) return;
    i = i.clamp(0, _items.length - 1);
    if (_webtoon) {
      _jumpVertical(i);
      setState(() => _pos = i);
    } else {
      _pc?.jumpToPage(i);
    }
  }

  void _step(int dir) {
    if (_ui) _toggleUi(false);
    if (_webtoon) {
      if (!_scroll.hasClients) return;
      final h = MediaQuery.of(context).size.height * 0.75;
      final t = (_scroll.offset + dir * h).clamp(0.0, _scroll.position.maxScrollExtent);
      _p.animatePages ? _scroll.animateTo(t, duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : _scroll.jumpTo(t);
      return;
    }
    final t = _pos + dir;
    if (t > _items.length) {
      final n = _next;
      if (n != null) _open(n);
      return;
    }
    if (t < 0) {
      final pr = _prev;
      if (pr != null) _open(pr, fromEnd: true);
      return;
    }
    _p.animatePages ? _pc?.animateToPage(t, duration: const Duration(milliseconds: 220), curve: Curves.easeOut) : _pc?.jumpToPage(t);
  }

  // ---------------- zone di tocco ----------------

  /// -1 indietro, 1 avanti, 0 comandi.
  int _region(Offset pos, Size size) {
    var x = pos.dx / size.width, y = pos.dy / size.height;
    final zones = _webtoon ? _p.webtoonTapZones : _p.pagedTapZones;
    final inv = _webtoon ? _p.webtoonInvert : _p.pagedInvert;
    if (inv == 1 || inv == 3) x = 1 - x;
    if (inv == 2 || inv == 3) y = 1 - y;
    // nei manga da destra a sinistra "avanti" sta a sinistra
    if (_rtl && zones != 4) x = 1 - x;
    final third = x < 1 / 3 ? 0 : (x < 2 / 3 ? 1 : 2);
    final row = y < 1 / 3 ? 0 : (y < 2 / 3 ? 1 : 2);
    switch (zones) {
      case 5: // disattivato
        return 0;
      case 2: // Kindle
        if (row == 0) return 0;
        return third == 0 ? -1 : 1;
      case 3: // bordo
        if (third == 1 && row == 2) return -1;
        if (third != 1) return 1;
        return 0;
      case 4: // destra e sinistra
        if (third == 1) return 0;
        final left = third == 0;
        return (_rtl ? !left : left) ? -1 : 1;
      default: // L
        if (row == 1 && third == 1) return 0;
        if (row == 0 || (row == 1 && third == 0)) return -1;
        return 1;
    }
  }

  void _tap(TapUpDetails d) {
    final r = _region(d.localPosition, context.size ?? MediaQuery.of(context).size);
    if (r == 0) {
      _toggleUi();
    } else {
      _step(r);
    }
  }

  void _doubleTap(TapDownDetails d) {
    final enabled = _webtoon ? _p.webtoonDoubleTap : _p.doubleTapZoom;
    if (!enabled) return;
    if (_zoom.value != Matrix4.identity()) {
      _zoom.value = Matrix4.identity();
    } else {
      final pt = d.localPosition;
      _zoom.value = Matrix4.identity()
        ..translate(-pt.dx, -pt.dy)
        ..scale(2.0);
    }
  }

  // ---------------- azioni sulla pagina ----------------

  Future<void> _pageActions(int page) async {
    if (!_p.longPressActions || page >= _pages.length) return;
    HapticFeedback.mediumImpact();
    final pg = _pages[page];
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1F1B18),
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.ios_share, color: Color(0xFFE2B84B)),
            title: Text('Condividi la pagina', style: LK.body(15, color: const Color(0xFFEFE4D2))),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined, color: Color(0xFFE2B84B)),
            title: Text('Usa come copertina', style: LK.body(15, color: const Color(0xFFEFE4D2))),
            onTap: () => Navigator.pop(ctx, 'cover'),
          ),
        ]),
      ),
    );
    if (v == null) return;
    try {
      final bytes = await MangaImages.get(pg.url, headers: pg.headers, sourceId: m.sourceId, managerId: m.managerId);
      if (bytes == null) return;
      if (v == 'share') {
        final dir = await getTemporaryDirectory();
        final f = File(p.join(dir.path, '${m.title.replaceAll(RegExp(r'[^\w]+'), '_')}_${page + 1}.jpg'));
        await f.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(f.path)], text: '${m.title} · ${_ch.name} · pagina ${page + 1}');
      } else {
        final d = Directory(p.join(LibraryStore.I.dataDir, 'manga_covers'));
        await d.create(recursive: true);
        final f = File(p.join(d.path, '${m.key.hashCode.toUnsigned(32)}_${DateTime.now().millisecondsSinceEpoch}.jpg'));
        await f.writeAsBytes(bytes);
        m.cover = f.path;
        store.save();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copertina aggiornata')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Non riuscito: $e')));
    }
  }

  // ---------------- impostazioni ----------------

  void _settings() {
    showMangaReaderSheet(
      context,
      prefs: _p,
      seriesMode: _seriesMode,
      seriesRotation: _seriesRot,
      effectiveMode: _mode,
      onSeries: ({mode, rotation}) {
        MangaPrefs.setSeries(m.key, mode: mode, rotation: rotation);
        final oldWebtoon = _webtoon;
        final page = _page;
        setState(() {
          if (mode != null) _seriesMode = mode;
          if (rotation != null) _seriesRot = rotation;
        });
        if (mode != null) _reflow(page, oldWebtoon);
        _applySystem();
      },
      onChanged: () {
        setState(() {});
        _applySystem();
      },
    );
  }

  /// Dopo un cambio di modalità riparto dalla stessa pagina.
  /// Elementi sfogliabili: pagine singole o coppie affiancate (la copertina resta da sola).
  List<_Item> _buildItems() {
    if (!_double) return [for (var i = 0; i < _pages.length; i++) _Item(i)];
    final out = <_Item>[];
    if (_pages.isNotEmpty) out.add(const _Item(0));
    for (var i = 1; i < _pages.length; i += 2) {
      final wide = (PageInfos.peek(_pages[i].url)?.wide ?? false) || (i + 1 < _pages.length && (PageInfos.peek(_pages[i + 1].url)?.wide ?? false));
      if (wide || i + 1 >= _pages.length) {
        out.add(_Item(i));
        if (i + 1 < _pages.length) out.add(_Item(i + 1));
      } else {
        out.add(_Item(i, 0, i + 1));
      }
    }
    return out;
  }

  void _reflow(int page, bool wasWebtoon) {
    _items = _buildItems();
    page = _items.indexWhere((it) => it.page == page || it.page2 == page).clamp(0, 1 << 30);
    _splitDone.clear();
    _pos = page.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
    _pc?.dispose();
    _pc = PageController(initialPage: _pos);
    setState(() {});
    if (_webtoon) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpVertical(_pos));
  }

  void _quickMode() async {
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1F1B18),
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i < mangaModes.length; i++)
            ListTile(
              title: Text(mangaModes[i], style: LK.body(15, color: i == _mode ? const Color(0xFFE2B84B) : const Color(0xFFEFE4D2))),
              trailing: i == _mode ? const Icon(Icons.check, color: Color(0xFFE2B84B)) : null,
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    );
    if (v == null) return;
    final old = _webtoon, page = _page;
    await MangaPrefs.setSeries(m.key, mode: v);
    setState(() => _seriesMode = v);
    _reflow(page, old);
  }

  void _quickRotation() async {
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1F1B18),
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 1; i < mangaRotations.length; i++)
              ListTile(
                title: Text(mangaRotations[i], style: LK.body(15, color: i == _rotation ? const Color(0xFFE2B84B) : const Color(0xFFEFE4D2))),
                trailing: i == _rotation ? const Icon(Icons.check, color: Color(0xFFE2B84B)) : null,
                onTap: () => Navigator.pop(ctx, i),
              ),
          ]),
        ),
      ),
    );
    if (v == null) return;
    await MangaPrefs.setSeries(m.key, rotation: v);
    setState(() => _seriesRot = v);
    _applySystem();
  }

  // ---------------- disegno ----------------

  Widget _transition() {
    final n = _next;
    final fg = _bg.computeLuminance() > 0.5 ? const Color(0xFF2A2420) : const Color(0xFFEFE4D2);
    final mutedC = _bg.computeLuminance() > 0.5 ? const Color(0xFF6B5F57) : const Color(0xFFB8AC9C);
    return Container(
      color: _bg,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 28),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('FINITO', style: LK.label(10, color: mutedC, spacing: 1.6)),
        const SizedBox(height: 4),
        Text(_ch.name, textAlign: TextAlign.center, style: LK.display(17, color: fg)),
        const SizedBox(height: 22),
        if (n != null) ...[
          Text('SUCCESSIVO', style: LK.label(10, color: mutedC, spacing: 1.6)),
          const SizedBox(height: 4),
          Text(n.name, textAlign: TextAlign.center, style: LK.display(17, color: fg)),
          const SizedBox(height: 16),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.bordeaux), onPressed: () => _open(n), child: const Text('Continua')),
        ] else
          Text('Non ci sono altri capitoli.', style: LK.body(14, color: mutedC, style: FontStyle.italic)),
      ]),
    );
  }

  Widget _pageWidget(_Item it, {required bool webtoon}) {
    if (it.page2 != null) {
      final a = _pageWidget(_Item(it.page), webtoon: false), b = _pageWidget(_Item(it.page2!), webtoon: false);
      final first = _rtl ? b : a, second = _rtl ? a : b;
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(child: Align(alignment: Alignment.centerRight, child: first)),
        Flexible(child: Align(alignment: Alignment.centerLeft, child: second)),
      ]);
    }
    final pg = _pages[it.page];
    return MangaPage(
      url: pg.url,
      headers: pg.headers,
      sourceId: m.sourceId,
      managerId: m.managerId,
      crop: webtoon ? _p.webtoonCrop : _p.cropBorders,
      half: it.half,
      rotateWide: !webtoon && _p.rotateWide && !_p.splitWide,
      fitWidth: webtoon,
      number: it.page + 1,
      background: _bg,
      placeholderHeight: MediaQuery.of(context).size.height * 0.8,
      onInfo: (info) => _onInfo(it.page, info),
    );
  }

  Widget _body() {
    final fg = _bg.computeLuminance() > 0.5 ? const Color(0xFF2A2420) : const Color(0xFFEFE4D2);
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE2B84B)));
    if (_error != null || _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error == null ? 'Il capitolo non ha pagine.' : 'Non riesco ad aprire il capitolo:\n$_error', textAlign: TextAlign.center, style: LK.body(14, color: fg)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: () => _open(_ch, page: _page), child: const Text('Riprova')),
          ]),
        ),
      );
    }
    final gestures = (Widget child) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _tap,
          onDoubleTapDown: (_webtoon ? _p.webtoonDoubleTap : _p.doubleTapZoom) ? _doubleTap : null,
          onDoubleTap: (_webtoon ? _p.webtoonDoubleTap : _p.doubleTapZoom) ? () {} : null,
          onLongPress: _p.longPressActions ? () => _pageActions(_page) : null,
          child: child,
        );
    if (_webtoon) {
      final w = MediaQuery.of(context).size.width;
      final side = w * _p.sidePadding / 100;
      final gap = _mode == 5;
      return gestures(InteractiveViewer(
        transformationController: _zoom,
        minScale: _p.disableZoomOut ? 1 : 0.5,
        maxScale: 3,
        panEnabled: false,
        scaleEnabled: true,
        child: ListView.builder(
          controller: _scroll,
          cacheExtent: 2500,
          padding: EdgeInsets.symmetric(horizontal: side),
          itemCount: _items.length + 1,
          itemBuilder: (context, i) {
            if (i == _items.length) return _transition();
            final key = _keys[i] ??= GlobalKey();
            return Padding(
              key: key,
              padding: EdgeInsets.only(bottom: gap ? 14 : 0),
              child: _pageWidget(_items[i], webtoon: true),
            );
          },
        ),
      ));
    }
    return gestures(PageView.builder(
      controller: _pc,
      reverse: _rtl,
      scrollDirection: _mode == 3 ? Axis.vertical : Axis.horizontal,
      itemCount: _items.length + 1,
      onPageChanged: _onPos,
      itemBuilder: (context, i) {
        if (i == _items.length) return _transition();
        final page = Center(child: _pageWidget(_items[i], webtoon: false));
        if (i != _pos) return page;
        return InteractiveViewer(transformationController: _zoom, minScale: 1, maxScale: 4, child: page);
      },
    ));
  }

  Widget _filters(Widget child) {
    var c = child;
    if (_p.grayscale) {
      c = ColorFiltered(
        colorFilter: const ColorFilter.matrix([0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0]),
        child: c,
      );
    }
    if (_p.invert) {
      c = ColorFiltered(colorFilter: const ColorFilter.matrix([-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0]), child: c);
    }
    if (_p.colorFilter) {
      final mode = switch (_p.blend) {
        1 => BlendMode.multiply,
        2 => BlendMode.screen,
        3 => BlendMode.overlay,
        4 => BlendMode.lighten,
        5 => BlendMode.darken,
        _ => BlendMode.srcATop,
      };
      c = ColorFiltered(colorFilter: ColorFilter.mode(Color.fromARGB(_p.filterA, _p.filterR, _p.filterG, _p.filterB), mode), child: c);
    }
    return c;
  }

  // telecomando della TV (e tastiera): frecce per le pagine, OK per i comandi
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_ui) return KeyEventResult.ignored;
    final k = e.logicalKey;
    int? dir;
    if (k == LogicalKeyboardKey.arrowRight) dir = _rtl ? -1 : 1;
    if (k == LogicalKeyboardKey.arrowLeft) dir = _rtl ? 1 : -1;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown) dir = 1;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp) dir = -1;
    final ok = k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter;
    if (dir == null && !ok) return KeyEventResult.ignored;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      if (ok) {
        _toggleUi(true);
      } else {
        _step(dir!);
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(autofocus: true, onKeyEvent: _onKey, child: _buildReader(context));

  Widget _buildReader(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    const ink = Color(0xFFEFE4D2);
    // in orizzontale, con le modalità per pagina, due pagine affiancate
    final size = MediaQuery.of(context).size;
    final wantDouble = _p.doublePage && size.width > size.height && (_mode == 1 || _mode == 2);
    if (wantDouble != _double && !_loading && _pages.isNotEmpty) {
      final page = _page;
      _double = wantDouble;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reflow(page, _webtoon);
      });
    } else {
      _double = wantDouble;
    }
    final count = _items.length;
    final vertNav = _p.verticalNavigatorIn.contains(_mode);
    final bookmarked = m.bookmarks.contains(_ch.url);
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(top: _p.drawInCutout ? 0 : MediaQuery.of(context).viewPadding.top),
            child: _filters(_body()),
          ),
        ),
        if (_p.customBrightness && _p.brightness < 0)
          Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black.withValues(alpha: -_p.brightness / 100)))),
        if (_flash) Positioned.fill(child: IgnorePointer(child: Container(color: _bg.computeLuminance() > 0.5 ? Colors.black : Colors.white))),
        // numero di pagina
        if (_p.showPageNumber && !_ui && count > 0 && _pos < count)
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
        // barra in alto
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          top: _ui ? 0 : -150,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(4, pad.top + 4, 4, 8),
            color: const Color(0xEB1C1714),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: ink), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(16, color: ink)),
                  Text(_ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(12.5, color: const Color(0xFFB8AC9C))),
                ]),
              ),
              IconButton(
                tooltip: 'Segna il capitolo',
                icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border, color: bookmarked ? const Color(0xFFE2B84B) : ink),
                onPressed: () => setState(() {
                  bookmarked ? m.bookmarks.remove(_ch.url) : m.bookmarks.add(_ch.url);
                  store.save();
                }),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: ink),
                color: const Color(0xFF2A2420),
                onSelected: (v) {
                  if (v == 'reload') _open(_ch, page: _page);
                  if (v == 'share' && _page < _pages.length) _pageActions(_page);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'reload', child: Text('Ricarica il capitolo', style: LK.body(14, color: ink))),
                  PopupMenuItem(value: 'share', child: Text('Azioni sulla pagina', style: LK.body(14, color: ink))),
                ],
              ),
            ]),
          ),
        ),
        // navigatore verticale a destra
        if (vertNav && count > 1)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            right: _ui ? 6 : -70,
            top: pad.top + 90,
            bottom: pad.bottom + 150,
            child: Container(
              width: 46,
              decoration: BoxDecoration(color: const Color(0xEB1C1714), borderRadius: BorderRadius.circular(23)),
              child: Column(children: [
                IconButton(icon: Icon(Icons.skip_previous, color: _prev == null ? const Color(0x55EFE4D2) : ink, size: 20), onPressed: _prev == null ? null : () => _open(_prev!)),
                Text('${_page + 1}', style: LK.label(10, color: ink, spacing: 0)),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Slider(
                      value: _pos.clamp(0, count - 1).toDouble(),
                      max: (count - 1).toDouble(),
                      divisions: count - 1,
                      activeColor: const Color(0xFFE2B84B),
                      inactiveColor: const Color(0x44EFE4D2),
                      onChanged: (v) => _goTo(v.round()),
                    ),
                  ),
                ),
                Text('${_pages.length}', style: LK.label(10, color: ink, spacing: 0)),
                IconButton(icon: Icon(Icons.skip_next, color: _next == null ? const Color(0x55EFE4D2) : ink, size: 20), onPressed: _next == null ? null : () => _open(_next!)),
              ]),
            ),
          ),
        // barra in basso
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          bottom: _ui ? 0 : -200,
          left: 0,
          right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!vertNav)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: const Color(0xEB1C1714), borderRadius: BorderRadius.circular(28)),
                child: Row(children: [
                  IconButton(
                    tooltip: 'Capitolo precedente',
                    icon: Icon(Icons.skip_previous, color: _prev == null ? const Color(0x55EFE4D2) : ink),
                    onPressed: _prev == null ? null : () => _open(_prev!),
                  ),
                  Text('${count == 0 ? 0 : _page + 1}', style: LK.label(11, color: ink, spacing: 0)),
                  Expanded(
                    child: Directionality(
                      textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                      child: Slider(
                        value: count == 0 ? 0 : _pos.clamp(0, count - 1).toDouble(),
                        max: count <= 1 ? 1 : (count - 1).toDouble(),
                        divisions: count <= 1 ? null : count - 1,
                        activeColor: const Color(0xFFE2B84B),
                        inactiveColor: const Color(0x44EFE4D2),
                        onChanged: count <= 1 ? null : (v) => _goTo(v.round()),
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
            Container(
              padding: EdgeInsets.fromLTRB(8, 6, 8, pad.bottom + 8),
              color: const Color(0xEB1C1714),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                IconButton(tooltip: 'Modalità di lettura', icon: const Icon(Icons.chrome_reader_mode_outlined, color: ink), onPressed: _quickMode),
                IconButton(tooltip: 'Rotazione', icon: const Icon(Icons.screen_rotation_outlined, color: ink), onPressed: _quickRotation),
                IconButton(
                  tooltip: 'Ritaglia bordi',
                  icon: Icon(Icons.crop, color: (_webtoon ? _p.webtoonCrop : _p.cropBorders) ? const Color(0xFFE2B84B) : ink),
                  onPressed: () {
                    setState(() {
                      if (_webtoon) {
                        _p.webtoonCrop = !_p.webtoonCrop;
                      } else {
                        _p.cropBorders = !_p.cropBorders;
                      }
                    });
                    _p.save();
                  },
                ),
                IconButton(tooltip: 'Impostazioni', icon: const Icon(Icons.tune, color: ink), onPressed: _settings),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
