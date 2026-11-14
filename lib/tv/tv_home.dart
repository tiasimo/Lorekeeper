import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/anilist.dart';
import '../services/anime_store.dart';
import '../services/background.dart';
import '../services/drive_sync.dart';
import '../services/manga_store.dart';
import '../services/updater.dart';
import '../widgets/update_dialog.dart';
import 'tv_now.dart';
import 'tv_search.dart';
import 'tv_settings.dart';
import 'tv_shelves.dart';
import 'tv_widgets.dart';

/// La Home della TV, solo anime e in stile "menu di un DVD": in alto le sezioni
/// (Sul lettore, Prossimamente, Collezione, Cerca, Impostazioni), sotto il contenuto.
class TvHome extends StatefulWidget {
  const TvHome({super.key});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  static const _tabs = ['Sul lettore', 'Prossimamente', 'Collezione', 'Cerca', 'Impostazioni'];

  int _tab = 0;
  final _tabNodes = List.generate(_tabs.length, (i) => FocusNode(debugLabel: 'tab$i'));
  final _content = FocusScopeNode(debugLabel: 'contenuto');
  bool _ready = false;
  bool _bridge = false; // motore delle estensioni pronto (serve a Cerca e per riprodurre)

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    for (final n in _tabNodes) {
      n.dispose();
    }
    _content.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    Future.delayed(const Duration(seconds: 3), () async {
      final u = await Updater.checkIfDue();
      if (u != null && mounted) showUpdateDialog(context, u);
    });
    DriveSync.I.init();
    // niente lavori in background sulla TV: un secondo motore raddoppierebbe la memoria
    Background.stopAll();
    await AnimeStore.I.load();
    await AniList.I.load();
    if (mounted) setState(() => _ready = true);
    _focusContent();
    try {
      await MangaStore.I.ensureBridge();
    } catch (_) {}
    if (mounted) setState(() => _bridge = true);
    // la lista AniList (stati, voti, prossimi episodi) è una sola richiesta: si aggiorna quasi subito
    Future.delayed(const Duration(seconds: 12), () async {
      if (!mounted || !AniList.I.loggedIn) return;
      try {
        AnimeStore.I.importAniList(await AniList.I.myList(type: 'ANIME'));
      } catch (_) {}
    });
    // i nuovi episodi dalle fonti si controllano dopo qualche minuto, un disco alla volta
    Future.delayed(const Duration(minutes: 3), () {
      if (mounted) AnimeStore.I.refreshIfDue();
    });
  }

  /// Porta la selezione sul primo elemento del contenuto (se c'è).
  void _focusContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final first = _content.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
      (first ?? _tabNodes[_tab]).requestFocus();
    });
  }

  void _go(int tab) {
    setState(() => _tab = tab);
    _tabNodes[tab].requestFocus();
  }

  /// ▼ dalle sezioni: va al primo elemento del contenuto (non a quello che sta "sotto").
  KeyEventResult _tabsKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    // ◀ ▶ passano alla sezione accanto, per posizione nell'elenco (non "la cosa più vicina sullo schermo")
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      if (e is KeyUpEvent) return KeyEventResult.handled;
      final cur = _tabNodes.indexWhere((n) => n.hasFocus);
      final to = ((cur < 0 ? _tab : cur) + (k == LogicalKeyboardKey.arrowRight ? 1 : -1)).clamp(0, _tabs.length - 1);
      _tabNodes[to].requestFocus();
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent || k != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    final first = _content.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
    first?.requestFocus();
    return KeyEventResult.handled;
  }

  /// ▲ dal contenuto: se sopra non c'è altro, torna alla sezione attiva.
  KeyEventResult _contentKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f.focusInDirection(TraversalDirection.up)) return KeyEventResult.handled;
    _tabNodes[_tab].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    return Scaffold(
      backgroundColor: TV.bg,
      body: TvCanvas(
        child: Stack(children: [
          // il contenuto sta sotto alla barra delle sezioni e può arrivare fino in cima (lo sfondo del disco)
          Positioned.fill(
            child: Focus(
              skipTraversal: true,
              canRequestFocus: false,
              onKeyEvent: _contentKey,
              child: FocusScope(
                node: _content,
                skipTraversal: true,
                child: !_ready
                    ? const Center(child: CircularProgressIndicator(color: TV.accent))
                    : switch (_tab) {
                        0 => TvNowPlaying(onGo: _go),
                        1 => const Padding(padding: EdgeInsets.only(top: 78), child: TvShelves(key: ValueKey(1), kind: 1)),
                        2 => const Padding(padding: EdgeInsets.only(top: 78), child: TvShelves(key: ValueKey(2), kind: 2)),
                        3 when !_bridge => const Center(child: CircularProgressIndicator(color: TV.accent)),
                        3 => const Padding(padding: EdgeInsets.only(top: 78), child: TvSearch()),
                        _ => const Padding(padding: EdgeInsets.only(top: 78), child: TvSettings()),
                      },
              ),
            ),
          ),
          Positioned(
            left: 48,
            right: 48,
            top: 24,
            child: Focus(
              skipTraversal: true,
              canRequestFocus: false,
              onKeyEvent: _tabsKey,
              child: FocusTraversalGroup(
                child: Row(children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: TV.accent, shape: BoxShape.circle),
                    child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: TV.bg, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 10),
                  Text('LOREKEEPER', style: tvDisplay(18, spacing: 3)),
                  const SizedBox(width: 22),
                  for (var i = 0; i < _tabs.length; i++)
                    TvFocus(
                      focusNode: _tabNodes[i],
                      onFocus: (f) {
                        if (f && _tab != i) setState(() => _tab = i);
                      },
                      onSelect: () {
                        if (_tab != i) setState(() => _tab = i);
                        _focusContent();
                      },
                      builder: (context, focused) => Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        color: focused ? TV.accent : Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == i && !focused ? TV.accent : Colors.transparent, width: 3))),
                          child: Text(_tabs[i].toUpperCase(), style: tvDisplay(16, color: focused ? TV.bg : (_tab == i ? Colors.white : TV.muted), weight: FontWeight.w500, spacing: 2)),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}', style: tvMono(15, color: const Color(0xFFD6D9DD))),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
