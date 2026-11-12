import 'dart:io';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../screens/anime/anime_widgets.dart';
import '../screens/manga/manga_home.dart';
import '../screens/reader_screen.dart';
import '../services/anilist.dart';
import '../services/background.dart';
import '../services/drive_sync.dart';
import '../services/updater.dart';
import '../services/anime_store.dart';
import '../services/library_store.dart';
import '../services/manga_store.dart';
import '../widgets/manga_image.dart';
import '../widgets/spine.dart';
import '../widgets/update_dialog.dart';
import 'tv_anime_detail.dart';
import 'tv_manga_detail.dart';
import 'tv_search.dart';
import 'tv_settings.dart';
import 'tv_widgets.dart';

/// La Home della TV: schede in alto (Anime, Manga, Novel, Cerca…) e file di
/// custodie, copertine e dorsi che si scorrono con il telecomando.
class TvHome extends StatefulWidget {
  const TvHome({super.key});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  int _tab = 0;
  final _tabNodes = List.generate(6, (i) => FocusNode(debugLabel: 'tab$i'));
  final _content = FocusScopeNode(debugLabel: 'contenuto');

  @override
  void dispose() {
    for (final n in _tabNodes) {
      n.dispose();
    }
    _content.dispose();
    super.dispose();
  }

  /// ▼ dalle schede: va al primo elemento del contenuto (non a quello che sta "sotto").
  KeyEventResult _tabsKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    final first = _content.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
    first?.requestFocus();
    return KeyEventResult.handled;
  }

  /// ▲ dal contenuto: se sopra non c'è altro, torna alla scheda attiva.
  KeyEventResult _contentKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f.focusInDirection(TraversalDirection.up)) return KeyEventResult.handled;
    _tabNodes[_tab].requestFocus();
    return KeyEventResult.handled;
  }
  String? _info; // titolo dell'elemento a fuoco
  String? _infoSub;
  bool _ready = false;
  bool _bridge = false; // motore delle estensioni pronto (serve a Cerca ed Estensioni)

  static const _tabs = ['Anime', 'Manga', 'Novel', 'Cerca', 'Estensioni', 'Impostazioni'];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // aggiornamenti dell'app, sincronizzazione e controllo novità, come sul telefono
    Future.delayed(const Duration(seconds: 3), () async {
      final u = await Updater.checkIfDue();
      if (u != null && mounted) showUpdateDialog(context, u);
    });
    DriveSync.I.init();
    Background.setup();
    await AnimeStore.I.load();
    await MangaStore.I.load();
    await AniList.I.load();
    if (mounted) setState(() => _ready = true);
    try {
      await MangaStore.I.ensureBridge();
    } catch (_) {}
    if (mounted) setState(() => _bridge = true);
    AnimeStore.I.refreshIfDue();
    MangaStore.I.refreshIfDue();
  }

  void _focusInfo(String title, String sub) => setState(() {
        _info = title;
        _infoSub = sub;
      });

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    return Scaffold(
      backgroundColor: TV.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0.6, -1.2), radius: 1.4, colors: [Color(0xFF3A2620), TV.bg, TV.bgDeep], stops: [0, 0.6, 1]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 20, 40, 4),
            child: Focus(
              skipTraversal: true,
              canRequestFocus: false,
              onKeyEvent: _tabsKey,
              child: FocusTraversalGroup(
                child: Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: TV.accent, borderRadius: BorderRadius.circular(10)),
                child: Text('L', style: tvDisplay(22, color: Colors.white)),
              ),
              const SizedBox(width: 22),
              for (var i = 0; i < _tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TvFocus(
                    focusNode: _tabNodes[i],
                    autofocus: i == 0,
                    scale: 1.04,
                    radius: BorderRadius.circular(24),
                    onFocus: (f) {
                      if (f && _tab != i) {
                        setState(() {
                          _tab = i;
                          _info = null;
                          _infoSub = null;
                        });
                      }
                    },
                    onSelect: () => setState(() => _tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: _tab == i ? TV.ink : Colors.transparent, borderRadius: BorderRadius.circular(24)),
                      child: Text(_tabs[i].toUpperCase(), style: tvLabel(11.5, color: _tab == i ? TV.bg : TV.soft, spacing: 1.1)),
                    ),
                  ),
                ),
              const Spacer(),
              Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}', style: tvLabel(15, color: TV.ink, spacing: 0.5)),
            ]),
              ),
            ),
          ),
          Expanded(
            child: Focus(
              skipTraversal: true,
              canRequestFocus: false,
              onKeyEvent: _contentKey,
              child: FocusScope(
                node: _content,
                child: !_ready
                ? const Center(child: CircularProgressIndicator(color: TV.accent))
                : switch (_tab) {
                    0 => _anime(),
                    1 => _manga(),
                    2 => _novel(),
                    3 || 4 when !_bridge => const Center(child: CircularProgressIndicator(color: TV.accent)),
                    3 => TvSearch(onFocusInfo: (x) => _focusInfo(x.$1, x.$2)),
                    4 => _extensions(),
                    _ => const TvSettings(),
                  },
              ),
            ),
          ),
          // cosa c'è a fuoco
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 2, 40, 14),
            child: Row(children: [
              if (_info != null) ...[
                Flexible(child: Text(_info!, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvDisplay(16))),
                const SizedBox(width: 14),
                if (_infoSub != null) Flexible(child: Text(_infoSub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvBody(14, color: TV.muted))),
              ],
              const Spacer(),
              Text('◀ ▶ SCORRI   OK APRI   ▲ MENU', style: tvLabel(11, color: const Color(0xFF8E826F), spacing: 1)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---------------- estensioni ----------------
  bool _extAnime = true;

  Widget _extensions() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 12, 40, 8),
          child: Row(children: [
            TvButton(label: 'Anime', primary: _extAnime, onSelect: () => setState(() => _extAnime = true)),
            const SizedBox(width: 12),
            TvButton(label: 'Manga', primary: !_extAnime, onSelect: () => setState(() => _extAnime = false)),
            const SizedBox(width: 20),
            Expanded(child: Text('Repository e sorgenti installate su questa TV.', style: tvBody(15, color: TV.muted))),
          ]),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ExtensionsPanel(key: ValueKey(_extAnime), type: _extAnime ? ItemType.anime : ItemType.manga),
            ),
          ),
        ),
      ]);

  // ---------------- anime ----------------
  void _openAnime(SavedAnime a) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvAnimeDetail(anime: a)));

  Widget _anime() {
    return ListenableBuilder(
      listenable: AnimeStore.I,
      builder: (context, _) {
        final lib = AnimeStore.I.library;
        final cont = lib.where((a) => a.lastWatchedAt != null && !a.pending && a.shelf != 2).toList()..sort((x, y) => y.lastWatchedAt!.compareTo(x.lastWatchedAt!));
        final rows = [
          ('In corso', lib.where((a) => a.shelf == 0).toList()),
          ('Da guardare', lib.where((a) => a.shelf == 1).toList()),
          ('Visti', lib.where((a) => a.shelf == 2).toList()),
        ];
        for (final a in lib) {
          AnimeStore.I.ensureColor(a);
        }
        return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
          if (cont.isNotEmpty) _hero(
            kicker: 'CONTINUA A GUARDARE',
            title: cont.first.title,
            sub: cont.first.next == null ? '' : 'Episodio ${cont.first.numberOf(cont.first.next!)} · ${cont.first.next!.name}',
            cover: cont.first.cover,
            sourceId: cont.first.sourceId,
            managerId: cont.first.managerId,
            primary: 'Riprendi',
            onPrimary: () => _openAnime(cont.first),
          ),
          if (lib.isEmpty) _empty('La videoteca è vuota: cerca un anime in «Cerca» oppure sincronizza con Google Drive o AniList dal telefono.'),
          for (final (name, list) in rows)
            if (list.isNotEmpty)
              _row(
                name,
                '${list.length} SERIE',
                128,
                [
                  for (final a in list)
                    TvFocus(
                      scale: 1.12,
                      radius: BorderRadius.circular(7),
                      onFocus: (f) {
                        if (f) _focusInfo(a.title, [if (a.newEpisodes > 0) '${a.newEpisodes} episodi nuovi', if (a.alStatus != null) 'AniList: ${alStatuses[a.alStatus] ?? a.alStatus}', if (a.alScore > 0) '★ ${a.alScore}'].join(' · '));
                      },
                      onSelect: () => _openAnime(a),
                      child: BluRayCase(anime: a, width: 100, badge: a.newEpisodes > 0 ? a.newEpisodes : (a.shelf == 0 && a.total > 0 ? a.unwatched : null)),
                    ),
                ],
              ),
        ]);
      },
    );
  }

  // ---------------- manga ----------------
  void _openManga(SavedManga m) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvMangaDetail(manga: m)));

  Widget _manga() {
    return ListenableBuilder(
      listenable: MangaStore.I,
      builder: (context, _) {
        final lib = MangaStore.I.library;
        final cont = lib.where((m) => m.lastReadAt != null && m.shelf == 0).toList()..sort((x, y) => y.lastReadAt!.compareTo(x.lastReadAt!));
        final rows = [
          ('In corso', lib.where((m) => m.shelf == 0).toList()),
          ('Da leggere', lib.where((m) => m.shelf == 1).toList()),
          ('Completati', lib.where((m) => m.shelf == 2).toList()),
        ];
        return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
          if (cont.isNotEmpty)
            _hero(
              kicker: 'CONTINUA A LEGGERE',
              title: cont.first.title,
              sub: cont.first.unread > 0 ? '${cont.first.unread} capitoli da leggere' : 'Sei in pari',
              cover: cont.first.cover,
              sourceId: cont.first.sourceId,
              managerId: cont.first.managerId,
              primary: 'Apri',
              onPrimary: () => _openManga(cont.first),
            ),
          if (lib.isEmpty) _empty('Nessun manga in libreria: aggiungili dal telefono e sincronizza con Google Drive.'),
          for (final (name, list) in rows)
            if (list.isNotEmpty)
              _row(
                name,
                '${list.length} MANGA',
                150,
                [
                  for (final m in list)
                    TvFocus(
                      scale: 1.1,
                      radius: BorderRadius.circular(8),
                      onFocus: (f) {
                        if (f) _focusInfo(m.title, m.unread > 0 ? '${m.unread} capitoli da leggere' : m.sourceName);
                      },
                      onSelect: () => _openManga(m),
                      child: Stack(clipBehavior: Clip.none, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 104,
                            height: 150,
                            child: (m.cover ?? '').isEmpty
                                ? Container(color: const Color(0xFF3A2E28), alignment: Alignment.center, padding: const EdgeInsets.all(8), child: Text(m.title, textAlign: TextAlign.center, style: tvDisplay(14)))
                                : MangaImage(m.cover!, sourceId: m.sourceId, managerId: m.managerId),
                          ),
                        ),
                        if (m.unread > 0 && m.shelf == 0)
                          Positioned(
                            top: -8,
                            right: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: TV.accent, borderRadius: BorderRadius.circular(10), border: Border.all(color: TV.bg, width: 2)),
                              child: Text('${m.unread}', style: tvLabel(11, color: Colors.white, spacing: 0.2)),
                            ),
                          ),
                      ]),
                    ),
                ],
              ),
        ]);
      },
    );
  }

  // ---------------- novel ----------------
  void _openBook(Book b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: b)));

  Widget _novel() {
    return ListenableBuilder(
      listenable: LibraryStore.I,
      builder: (context, _) {
        final store = LibraryStore.I;
        final last = store.lastRead;
        final groups = store.shelfGroups();
        return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
          if (last != null)
            _hero(
              kicker: 'CONTINUA A LEGGERE',
              title: last.title,
              sub: last.chapters.isEmpty ? '' : 'Capitolo ${last.lastChapter + 1} · ${(last.progress * 100).round()}%',
              cover: last.coverPath,
              primary: 'Riprendi',
              onPrimary: () => _openBook(last),
              secondary: 'Ascolta',
              onSecondary: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: last, listen: true))),
            ),
          if (store.books.isEmpty) _empty('Nessun libro: importali dal telefono e sincronizza con Google Drive.'),
          for (final g in groups)
            if (g.$3.any((e) => e.startsWith('b:')))
              _row(
                g.$2 ?? 'Altri libri',
                '${g.$3.where((e) => e.startsWith('b:')).length} VOLUMI',
                170,
                [
                  for (final e in g.$3.where((e) => e.startsWith('b:')))
                    if (store.byId(e.substring(2)) case final b?)
                      TvFocus(
                        scale: 1.1,
                        radius: BorderRadius.circular(3),
                        onFocus: (f) {
                          if (f) _focusInfo(b.title, '${b.author}${b.progress > 0 ? ' · ${(b.progress * 100).round()}%' : ''}');
                        },
                        onSelect: () => _openBook(b),
                        child: SpineView.of(b, baseHeight: 160),
                      ),
                ],
                gap: 8,
                align: CrossAxisAlignment.end,
              ),
        ]);
      },
    );
  }

  // ---------------- pezzi comuni ----------------
  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
        child: Text(text, style: tvBody(18, color: TV.muted)),
      );

  Widget _hero({
    required String kicker,
    required String title,
    required String sub,
    String? cover,
    String? sourceId,
    String? managerId,
    required String primary,
    required VoidCallback onPrimary,
    String? secondary,
    VoidCallback? onSecondary,
  }) {
    return SizedBox(
      height: 196,
      child: Stack(children: [
        if ((cover ?? '').isNotEmpty)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 560,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [Colors.transparent, Colors.black], stops: [0, 0.6]).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.transparent], stops: [0.45, 1]).createShader(r),
                blendMode: BlendMode.dstIn,
                child: Opacity(
                  opacity: 0.55,
                  child: cover!.startsWith('/') || !cover.startsWith('http')
                      ? Image.file(File(cover), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
                      : MangaImage(cover, sourceId: sourceId, managerId: managerId),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kicker, style: tvLabel(10.5, color: TV.gold, spacing: 2.2)),
            const SizedBox(height: 4),
            SizedBox(width: 620, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvDisplay(32))),
            const SizedBox(height: 2),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvBody(14)),
            const SizedBox(height: 14),
            Row(children: [
              TvButton(label: primary, icon: Icons.play_arrow, primary: true, onSelect: onPrimary),
              if (secondary != null) ...[
                const SizedBox(width: 14),
                TvButton(label: secondary, icon: Icons.headphones, onSelect: onSecondary!),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _row(String name, String count, double height, List<Widget> items, {double gap = 18, CrossAxisAlignment align = CrossAxisAlignment.end}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(40, 10, 40, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(name, style: tvDisplay(18, color: TV.peach, style: FontStyle.italic)),
          const SizedBox(width: 12),
          Text(count, style: tvLabel(11, spacing: 1.4)),
        ]),
      ),
      SizedBox(
        height: height + 28,
        child: FocusTraversalGroup(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(40, 14, 40, 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (_, i) => Align(alignment: align == CrossAxisAlignment.end ? Alignment.bottomCenter : Alignment.center, child: items[i]),
          ),
        ),
      ),
      Container(
        height: 9,
        margin: const EdgeInsets.symmetric(horizontal: 34),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5E4433), Color(0xFF3E2C21)]),
          boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 18, offset: Offset(0, 8))],
        ),
      ),
    ]);
  }
}
