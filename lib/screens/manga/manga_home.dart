import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/common.dart';
import '../../widgets/manga_image.dart';
import '../../widgets/spine.dart';
import '../../tv/tv_keyboard.dart';
import '../../services/library_store.dart';
import '../spine_editor_screen.dart';
import 'anilist_ui.dart';
import 'manga_categories.dart';
import 'manga_detail.dart';
import 'manga_reader.dart';

/// Sezione Manga dentro la home: [view] 0 = libreria, 1 = esplora (sorgenti, novità, cronologia, AniList, estensioni).
class MangaSection extends StatefulWidget {
  final int view;
  final VoidCallback onExplore;
  const MangaSection({super.key, required this.view, required this.onExplore});
  @override
  State<MangaSection> createState() => _MangaSectionState();
}

class _MangaSectionState extends State<MangaSection> {
  final store = MangaStore.I;
  int _tab = 0;
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    store.load();
    store.ensureBridge().then((_) {
      if (mounted) setState(() => _starting = false);
      store.refreshIfDue();
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = '$e';
        });
      }
    });
  }

  static const _tabs = ['Sorgenti', 'Novità', 'Cronologia', 'AniList', 'Estensioni'];

  /// Apre un capitolo dalla cronologia o dalle novità.
  Future<void> _openChapter(MangaEvent e, {bool resume = false}) async {
    final m = store.byKey(e.mangaKey);
    if (m == null) return;
    await store.ensureBridge();
    final s = store.sourceFor(m);
    final c = m.chapters.where((c) => c.url == e.chapterUrl).firstOrNull;
    if (s == null || c == null || !mounted) {
      if (mounted) Navigator.of(context).push(bookRoute(MangaDetail(manga: m)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaReader(manga: m, source: s, chapter: c, startPage: resume && m.lastChapter == c.url ? m.lastPage : 0)));
  }

  /// L'ultimo manga aperto, se ha ancora qualcosa da leggere.
  (SavedManga, MChapter, int)? get _continue {
    final list = store.library.where((m) => !m.pending && m.lastReadAt != null && m.lastChapter != null).toList()
      ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    for (final m in list) {
      final ord = m.ordered;
      final i = ord.indexWhere((c) => c.url == m.lastChapter);
      if (i < 0) continue;
      if (!m.isRead(ord[i])) return (m, ord[i], m.lastPage);
      if (i + 1 < ord.length) return (m, ord[i + 1], 0);
    }
    return null;
  }

  Future<void> _resume((SavedManga, MChapter, int) r) async {
    await store.ensureBridge();
    final s = store.sourceFor(r.$1);
    if (!mounted) return;
    if (s == null) {
      Navigator.of(context).push(bookRoute(MangaDetail(manga: r.$1)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaReader(manga: r.$1, source: s, chapter: r.$2, startPage: r.$3)));
  }

  Widget _continueBar() => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final r = _continue;
          final sync = store.refreshing
              ? Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: LK.accent)))
              : IconButton(
                  tooltip: 'Cerca nuovi capitoli',
                  icon: Icon(Icons.sync, color: LK.accent, size: 26),
                  onPressed: () async {
                    final n = await store.refreshLibrary();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'Nessun capitolo nuovo' : '$n ${n == 1 ? 'capitolo nuovo' : 'capitoli nuovi'}')));
                    }
                  },
                );
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
            child: Row(children: [
              Expanded(
                child: r == null
                    ? Text('Nessun manga in corso', style: LK.body(13.5, color: LK.muted, style: FontStyle.italic))
                    : Material(
                        color: LK.card,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _resume(r),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: LK.line)),
                            child: Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 38,
                                  height: 54,
                                  child: (r.$1.cover ?? '').isEmpty ? Container(color: LK.line) : MangaImage(r.$1.cover!, sourceId: r.$1.sourceId, managerId: r.$1.managerId, tint: r.$1.coverSpineColor == null ? null : Color(r.$1.coverSpineColor!)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('CONTINUA A LEGGERE', style: LK.label(9, spacing: 1.6)),
                                  Text(r.$1.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(15)),
                                  Text('${r.$2.name}${r.$3 > 0 ? ' · pagina ${r.$3 + 1}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(12.5, color: LK.muted)),
                                ]),
                              ),
                              LKIcon(LKGlyph.read, color: LK.accent, size: 22),
                            ]),
                          ),
                        ),
                      ),
              ),
              sync,
            ]),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    if (widget.view == 0) {
      return Column(children: [
        _continueBar(),
        Expanded(child: _LibraryTab(onExplore: widget.onExplore)),
      ]);
    }
    return Column(children: [
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
          for (var i = 0; i < _tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: i == _tab ? LK.accent : LK.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: i == _tab ? LK.accent : LK.border),
                  ),
                  child: Text(_tabs[i].toUpperCase(), style: LK.label(10.5, color: i == _tab ? LK.onAccent : LK.muted, spacing: 1.1)),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: _error != null
            ? _message('Non riesco ad avviare le estensioni:\n$_error')
            : _starting && (_tab == 0 || _tab >= 3)
                ? Center(child: CircularProgressIndicator(color: LK.accent))
                : IndexedStack(index: _tab, children: [
                    if (_starting) const SizedBox.shrink() else SourceExploreTab(onExtensions: () => setState(() => _tab = 4)),
                    _UpdatesTab(onOpen: _openChapter),
                    _HistoryTab(onOpen: _openChapter),
                    if (_starting) const SizedBox.shrink() else const AniListTab(),
                    if (_starting) const SizedBox.shrink() else const ExtensionsPanel(),
                  ]),
      ),
    ]);
  }
}

Widget _message(String t) => Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Text(t, textAlign: TextAlign.center, style: LK.body(15, color: LK.muted, style: FontStyle.italic)),
      ),
    );

/// Copertina con titolo, come in una vetrina.
class _MangaTile extends StatelessWidget {
  final String title;
  final String? cover, sub;
  final String? sourceId, managerId;
  final double? progress;
  final VoidCallback onTap;
  const _MangaTile({required this.title, this.cover, this.sub, this.sourceId, this.managerId, this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(fit: StackFit.expand, children: [
                cover == null || cover!.isEmpty
                    ? Container(color: LK.accentSoft, alignment: Alignment.center, child: Text(title.isEmpty ? '?' : title[0], style: LK.display(30, color: LK.accentDark)))
                    : MangaImage(cover!, sourceId: sourceId, managerId: managerId),
                if (progress != null && progress! > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(value: progress, minHeight: 3, color: LK.accent, backgroundColor: const Color(0x66000000)),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.display(13).copyWith(height: 1.2)),
        if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.label(8.5, spacing: 0.5)),
      ]),
    );
  }
}

SliverGridDelegate _grid(BuildContext context) => SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 140,
      mainAxisSpacing: 16,
      crossAxisSpacing: 12,
      childAspectRatio: 0.52,
    );

// ======================================================================
// Libreria: registro di lettura (telefono) e rastrelliere (tablet orizzontale)
// ======================================================================
const _shelfNames = ['In corso', 'Da leggere', 'Completati'];
const _shelfWoods = [Wood('Noce', Color(0xFF6E4B33), Color(0xFF4E3322), Color(0xFF3E2718)), Wood('Quercia', Color(0xFFA9825A), Color(0xFF86633F), Color(0xFF6E4F30)), Wood('Mogano', Color(0xFF7E3B26), Color(0xFF5A2516), Color(0xFF461A0E))];

final _catFilter = ValueNotifier<String?>(null);

/// Scheda scelta nel registro (telefono): 0 in corso, 1 da leggere, 2 finiti.
final _registerTab = ValueNotifier<int>(0);

/// Tablet: il manga mostrato nel pannello di dettaglio accanto agli scaffali.
final mangaPaneSelection = ValueNotifier<SavedManga?>(null);
bool mangaPaneActive = false;

class _LibraryTab extends StatelessWidget {
  final VoidCallback onExplore;
  const _LibraryTab({required this.onExplore});

  void _open(BuildContext context, SavedManga m) {
    if (mangaPaneActive) {
      // tablet: il dettaglio si apre nel pannello a destra
      mangaPaneSelection.value = m;
      return;
    }
    Navigator.of(context).push(bookRoute(MangaDetail(manga: m)));
  }

  void _options(BuildContext context, SavedManga m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(width: 54, height: 78, child: (m.cover ?? '').isEmpty ? Container(color: LK.line) : MangaImage(m.cover!, sourceId: m.sourceId, managerId: m.managerId, tint: m.coverSpineColor == null ? null : Color(m.coverSpineColor!))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, style: LK.display(17)),
                  const SizedBox(height: 2),
                  Text(m.pending ? 'Da AniList · sorgente da scegliere' : m.sourceName, style: LK.label(9.5, spacing: 0.6)),
                  if (m.unread > 0) Text('${m.unread} capitoli da leggere', style: LK.body(12.5, color: LK.muted)),
                ]),
              ),
            ]),
          ),
          ListTile(
            leading: Icon(Icons.brush_outlined, color: LK.accent),
            title: Text('Modifica il dorso', style: LK.body(15)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SpineEditorScreen(
                  book: m.spineBook,
                  onSave: (b) {
                    m.applySpine(b);
                    MangaStore.I.save();
                  },
                ),
              ));
            },
          ),
          ListTile(
            leading: Icon(Icons.label_outline, color: LK.accent),
            title: Text('Categorie…', style: LK.body(15)),
            onTap: () {
              Navigator.pop(ctx);
              editMangaCategories(context, m);
            },
          ),
          ListTile(
            leading: Icon(Icons.done_all, color: LK.accent),
            title: Text('Segna tutto come letto', style: LK.body(15)),
            onTap: () {
              Navigator.pop(ctx);
              for (final c in m.chapters) {
                m.read.add(c.url);
              }
              m.newChapters = 0;
              m.lastReadAt ??= DateTime.now();
              MangaStore.I.save();
            },
          ),
          ListTile(
            leading: Icon(Icons.bookmark_remove_outlined, color: LK.muted),
            title: Text('Togli dalla libreria', style: LK.body(15)),
            onTap: () {
              Navigator.pop(ctx);
              MangaStore.I.toggleLibrary(m);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([MangaStore.I, _catFilter, LibraryStore.I, _registerTab]),
      builder: (context, _) {
        final store = MangaStore.I;
        final list = store.library;
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('La tua mensola dei manga è vuota.', textAlign: TextAlign.center, style: LK.display(18)),
                const SizedBox(height: 8),
                Text('Aggiungi un repository in «Estensioni», installa una sorgente e cerca i manga in «Esplora».',
                    textAlign: TextAlign.center, style: LK.body(14, color: LK.muted)),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onExplore,
                  style: OutlinedButton.styleFrom(foregroundColor: LK.accent, side: BorderSide(color: LK.accent)),
                  child: const Text('Vai a Esplora'),
                ),
              ]),
            ),
          );
        }
        final cat = _catFilter.value;
        final groups = [<SavedManga>[], <SavedManga>[], <SavedManga>[]];
        for (final m in list.where((m) => cat == null || m.categories.contains(cat))) {
          groups[m.shelf].add(m);
        }
        // in corso e completati: prima l'ultimo letto; da leggere: prima l'ultimo aggiunto
        groups[0].sort((a, b) => (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));
        groups[1].sort((a, b) => b.addedAt.compareTo(a.addedAt));
        groups[2].sort((a, b) => (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));
        final top = <Widget>[
          if (store.refreshing)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cerco nuovi capitoli… ${store.refreshDone}/${store.refreshTotal}', style: LK.label(9.5, spacing: 0.6)),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: store.refreshTotal == 0 ? null : store.refreshDone / store.refreshTotal, color: LK.accent, backgroundColor: LK.line),
              ]),
            ),
          if (store.categoryNames.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                for (final c in [null, ...store.categoryNames])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(c ?? 'Tutti', style: LK.body(13)),
                      selected: cat == c,
                      selectedColor: LK.accentSoft,
                      backgroundColor: LK.card,
                      side: BorderSide(color: LK.border),
                      onSelected: (_) => _catFilter.value = c,
                    ),
                  ),
              ]),
            ),
        ];
        // tablet in orizzontale: rastrelliere; telefono e tablet in verticale: registro di lettura
        if (isWide(context)) return _racks(context, groups, top);
        return _register(context, groups, top);
      },
    );
  }

  static const _tabNames = ['In corso', 'Da leggere', 'Finiti'];

  /// Dove sei arrivato, in breve: "Cap. 112 · pag. 8", "Cap. 41 · finito", "Da iniziare · 58 cap.".
  String _where(SavedManga m) {
    final ord = m.ordered;
    if (m.lastChapter != null) {
      final c = ord.where((c) => c.url == m.lastChapter).firstOrNull;
      if (c != null) return m.isRead(c) ? 'Cap. ${m.chapterNumber(c)} · finito' : 'Cap. ${m.chapterNumber(c)} · pag. ${m.lastPage + 1}';
    }
    if (m.readUpTo > 0) return 'Cap. ${m.readUpTo} · finito';
    final total = ord.isNotEmpty ? ord.length : (m.alTotal ?? 0);
    return total > 0 ? 'Da iniziare · $total cap.' : 'Da iniziare';
  }

  String _when(DateTime? d) {
    if (d == null) return 'MAI APERTO';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days <= 0) return 'LETTO OGGI';
    if (days == 1) return 'IERI';
    if (days < 7) return '$days GIORNI FA';
    if (days < 14) return 'SETTIMANA SCORSA';
    if (days < 60) return '${days ~/ 7} SETTIMANE FA';
    return '${days ~/ 30} MESI FA';
  }

  int _badge(SavedManga m) => m.newChapters > 0 ? m.newChapters : (m.shelf == 0 ? m.unread : 0);

  Widget _cover(SavedManga m, double w, double h, {double radius = 3}) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(fit: StackFit.expand, children: [
            (m.cover ?? '').isEmpty
                ? Container(
                    color: m.coverSpineColor == null ? LK.line : Color(m.coverSpineColor!),
                    alignment: Alignment.topLeft,
                    padding: const EdgeInsets.all(6),
                    child: Text(m.title.toUpperCase(), maxLines: 4, overflow: TextOverflow.ellipsis, style: LK.label(w > 100 ? 11 : 8.5, color: Colors.white, spacing: 0.5)),
                  )
                : MangaImage(m.cover!, sourceId: m.sourceId, managerId: m.managerId, tint: m.coverSpineColor == null ? null : Color(m.coverSpineColor!)),
            // la piega della rilegatura
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 5,
              child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x40000000), Color(0x00000000)]))),
            ),
          ]),
        ),
      );

  /// Riprende dal punto giusto: la pagina dove eri, o il primo capitolo non letto.
  void _continue(BuildContext context, SavedManga m) {
    final s = MangaStore.I.sourceFor(m);
    final ord = m.ordered;
    if (m.pending || s == null || ord.isEmpty) return _open(context, m);
    var c = ord.firstWhere((c) => !m.isRead(c), orElse: () => ord.last);
    var page = 0;
    final last = ord.where((x) => x.url == m.lastChapter).firstOrNull;
    if (last != null && !m.isRead(last)) {
      c = last;
      page = m.lastPage;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaReader(manga: m, source: s, chapter: c, startPage: page)));
  }

  // ---------------- telefono: registro di lettura ----------------
  Widget _register(BuildContext context, List<List<SavedManga>> groups, List<Widget> top) {
    final tab = _registerTab.value;
    final list = groups[tab];
    return Column(children: [
      ...top,
      Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: LK.line))),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (var k = 0; k < 3; k++)
            InkWell(
              onTap: () => _registerTab.value = k,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: k == tab ? LK.accent : Colors.transparent, width: 2.5))),
                child: Text('${_tabNames[k].toUpperCase()} · ${groups[k].length}', style: LK.label(10.5, color: k == tab ? LK.accent : LK.muted, spacing: 0.9)),
              ),
            ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          color: LK.accent,
          onRefresh: () => MangaStore.I.refreshLibrary(),
          child: list.isEmpty
              ? ListView(children: [
                  _message(switch (tab) {
                    0 => 'Nessun manga in corso: aprine uno da «Da leggere» o da Esplora.',
                    1 => 'Niente da leggere in lista.',
                    _ => 'Nessun manga finito, per ora.',
                  }),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 40),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _registerRow(context, list[i], highlight: i == 0 && tab == 0),
                ),
        ),
      ),
    ]);
  }

  Widget _registerRow(BuildContext context, SavedManga m, {bool highlight = false}) {
    final badge = _badge(m);
    final total = m.chapters.isNotEmpty ? m.chapters.length : (m.alTotal ?? 0);
    return Material(
      color: highlight ? LK.card : Colors.transparent,
      child: InkWell(
        onTap: () => _open(context, m),
        onLongPress: () => _options(context, m),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: LK.line))),
          child: Row(children: [
            DecoratedBox(
              decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x38000000), blurRadius: 8, offset: Offset(0, 4))]),
              child: Hero(tag: 'book-${m.spineBook.id}', child: _cover(m, 62, 88)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(16))),
                  if (badge > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: LK.accent, borderRadius: BorderRadius.circular(9)),
                      child: Text(m.newChapters > 0 ? '+$badge' : '$badge', style: LK.label(9.5, color: Colors.white, spacing: 0.2)),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(_where(m), maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(12.5, color: LK.muted, style: FontStyle.italic)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: m.progress, minHeight: 4, backgroundColor: LK.line, color: LK.accent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(total > 0 ? '${m.readUpTo} / $total' : '${m.readUpTo}', style: LK.label(9.5, spacing: 0.2)),
                ]),
                const SizedBox(height: 4),
                Text('${_when(m.lastReadAt)} · ${m.pending ? 'DA ANILIST' : m.sourceName.toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.label(9, spacing: 0.8)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------------- tablet orizzontale: rastrelliere ----------------
  Widget _racks(BuildContext context, List<List<SavedManga>> groups, List<Widget> top) {
    final reading = groups[0].where((m) => m.lastReadAt != null).firstOrNull ?? groups[0].firstOrNull;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (reading != null)
        Container(
          width: 320,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          decoration: BoxDecoration(border: Border(right: BorderSide(color: LK.line))),
          child: SingleChildScrollView(child: _nowReading(context, reading)),
        ),
      Expanded(
        child: RefreshIndicator(
          color: LK.accent,
          onRefresh: () => MangaStore.I.refreshLibrary(),
          child: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            ...top,
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 6),
              child: Text('Scorri ogni rastrelliera di lato · tieni premuta una copertina per le opzioni', style: LK.body(13, color: LK.muted, style: FontStyle.italic)),
            ),
            for (var k = 0; k < 3; k++)
              if (groups[k].isNotEmpty) _rack(context, k, groups[k]),
            if (groups.every((g) => g.isEmpty)) _message('Nessun manga in questa categoria.'),
          ]),
        ),
      ),
    ]);
  }

  Widget _nowReading(BuildContext context, SavedManga m) {
    final badge = _badge(m);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('STAI LEGGENDO', style: LK.label(10, spacing: 1.8)),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: () => _open(context, m),
        onLongPress: () => _options(context, m),
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Transform.rotate(
            angle: -0.044,
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x4D1E140A), blurRadius: 28, offset: Offset(0, 16))]),
              child: Hero(tag: 'book-${m.spineBook.id}', child: _cover(m, 200, 284, radius: 4)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      Text(m.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: LK.display(22)),
      const SizedBox(height: 6),
      Text(_where(m), style: LK.body(13.5, color: LK.muted, style: FontStyle.italic)),
      const SizedBox(height: 12),
      ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: m.progress, minHeight: 5, backgroundColor: LK.line, color: LK.accent)),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: LK.accent, shape: const StadiumBorder()),
          onPressed: () => _continue(context, m),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: Text('CONTINUA', style: LK.label(11.5, color: Colors.white, spacing: 1)),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(side: BorderSide(color: LK.border), shape: const StadiumBorder()),
          onPressed: () => _open(context, m),
          child: Text('CAPITOLI', style: LK.label(11.5, color: LK.ink, spacing: 1)),
        ),
      ]),
      if (badge > 0 || !m.pending)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            [if (m.newChapters > 0) '+${m.newChapters} CAPITOLI NUOVI' else if (badge > 0) '$badge CAPITOLI DA LEGGERE', if (!m.pending) m.sourceName.toUpperCase()].join(' · '),
            style: LK.label(9.5, spacing: 0.8),
          ),
        ),
    ]);
  }

  /// Una rastrelliera di legno: le copertine si appoggiano una sull'altra e scorrono di lato.
  Widget _rack(BuildContext context, int kind, List<SavedManga> list) {
    final key = 'manga:$kind';
    final wood = LibraryStore.I.app.woodFor(key, _shelfWoods[kind]);
    const coverW = 118.0, coverH = 166.0, step = 86.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 4, 30, 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(_tabNames[kind], style: LK.display(18, color: LK.accent, style: FontStyle.italic)),
            const SizedBox(width: 10),
            Text('${list.length} SERIE${kind == 0 && list.any((m) => m.newChapters > 0) ? ' · ${list.fold<int>(0, (s, m) => s + m.newChapters)} CAPITOLI NUOVI' : ''}', style: LK.label(9.5, spacing: 1)),
          ]),
        ),
        SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Stack(children: [
              Positioned.fill(
                bottom: 14,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 6, right: coverW),
                  itemExtent: step,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final badge = _badge(m);
                    return OverflowBox(
                      alignment: Alignment.bottomLeft,
                      minWidth: coverW,
                      maxWidth: coverW,
                      child: Transform.rotate(
                        angle: i.isOdd ? -0.035 : 0.018,
                        alignment: Alignment.bottomLeft,
                        child: GestureDetector(
                          onTap: () => _open(context, m),
                          onLongPress: () => _options(context, m),
                          child: Container(
                            width: coverW,
                            height: coverH,
                            decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x4D1E140A), blurRadius: 12, offset: Offset(-7, 5))]),
                            child: Stack(children: [
                              _cover(m, coverW, coverH),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 3,
                                child: ColoredBox(
                                  color: const Color(0x59000000),
                                  child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: m.progress, child: const ColoredBox(color: Color(0xFFE2B84B))),
                                ),
                              ),
                              if (badge > 0)
                                Positioned(
                                  right: 7,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(color: LK.accent, borderRadius: BorderRadius.circular(9)),
                                    child: Text(m.newChapters > 0 ? '+$badge' : '$badge', style: LK.label(9.5, color: Colors.white, spacing: 0.2)),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // il bordo della rastrelliera, davanti alle copertine
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 18,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [wood.base, wood.dark]),
                      boxShadow: const [BoxShadow(color: Color(0x333C2814), blurRadius: 10, offset: Offset(0, 6))],
                    ),
                    child: Align(alignment: Alignment.topCenter, child: Container(height: 4, color: Color.lerp(wood.base, Colors.white, 0.18))),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ======================================================================
// Esplora
// ======================================================================
/// Esplora le sorgenti installate (manga o anime).
class SourceExploreTab extends StatefulWidget {
  final VoidCallback onExtensions;
  final ItemType type;
  final void Function(BuildContext context, Source s, DMedia d)? onOpen;
  const SourceExploreTab({super.key, required this.onExtensions, this.type = ItemType.manga, this.onOpen});
  @override
  State<SourceExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<SourceExploreTab> {
  List<Source> _installed() =>
      (widget.type == ItemType.anime ? MangaStore.I.ext.installedAnimeExtensions : MangaStore.I.ext.installedMangaExtensions).toList();

  void _open(Source s, DMedia d) {
    if (widget.onOpen != null) return widget.onOpen!(context, s, d);
    final m = MangaStore.I.entry(s, d);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaDetail(manga: m)));
  }

  Source? _source;
  int _mode = 0; // 0 popolari, 1 novità, 2 ricerca
  final _q = TextEditingController();
  final List<DMedia> _items = [];
  int _page = 1;
  bool _hasNext = false, _loading = false;
  String? _error;
  int _run = 0;
  // ricerca in tutte le sorgenti
  bool _global = false;
  final List<(Source, List<DMedia>)> _globalRes = [];
  int _globalPending = 0;

  Future<void> _globalSearch() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    final my = ++_run;
    final sources = _installed();
    setState(() {
      _globalRes.clear();
      _globalPending = sources.length;
    });
    searchSources(
      sources,
      q,
      alive: () => my == _run && mounted,
      onResult: (s, list) {
        if (list.isNotEmpty) setState(() => _globalRes.add((s, list)));
      },
      onDone: () => setState(() => _globalPending--),
    );
  }

  Widget _globalView() {
    if (_q.text.trim().isEmpty) return _message('Scrivi un titolo: lo cerco in tutte le sorgenti installate.');
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      if (_globalPending > 0) LinearProgressIndicator(color: LK.accent, backgroundColor: LK.line),
      if (_globalPending == 0 && _globalRes.isEmpty) _message('Nessuna sorgente l\'ha trovato.'),
      for (final (s, list) in _globalRes) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text('${s.name} · ${(s.lang ?? '').toUpperCase()}', style: LK.label(10, color: LK.accent, spacing: 1)),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final d = list[i];
              return SizedBox(
                width: 110,
                child: _MangaTile(
                  title: d.title ?? '',
                  cover: d.cover,
                  sourceId: s.id,
                  managerId: s.managerId ?? s.extensionType,
                  onTap: () => _open(s, d),
                ),
              );
            },
          ),
        ),
      ],
    ]);
  }

  Future<void> _load({bool more = false}) async {
    final s = _source;
    if (s == null) return;
    final my = more ? _run : ++_run;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _items.clear();
        _page = 1;
      }
    });
    try {
      final Pages r;
      if (_mode == 2) {
        r = await s.methods.search(_q.text.trim(), _page, []);
      } else if (_mode == 1) {
        r = await s.methods.getLatestUpdates(_page);
      } else {
        r = await s.methods.getPopular(_page);
      }
      if (my != _run || !mounted) return;
      setState(() {
        _items.addAll(r.list);
        _hasNext = r.hasNextPage;
        _page++;
      });
      // le copertine sotto lo schermo arrivano mentre guardi quelle in alto
      MangaImages.prefetch(r.list.map((x) => x.cover ?? ''), sourceId: s.id, managerId: s.managerId ?? s.extensionType);
    } catch (e) {
      if (my == _run && mounted) setState(() => _error = '$e');
    } finally {
      if (my == _run && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final sources = _installed();
      if (sources.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Nessuna sorgente installata.', style: LK.display(18)),
              const SizedBox(height: 8),
              Text('Aggiungi un repository e installa almeno una sorgente ${widget.type == ItemType.anime ? 'anime' : 'manga'}.', textAlign: TextAlign.center, style: LK.body(14, color: LK.muted)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: widget.onExtensions,
                style: OutlinedButton.styleFrom(foregroundColor: LK.accent, side: BorderSide(color: LK.accent)),
                child: const Text('Vai a Estensioni'),
              ),
            ]),
          ),
        );
      }
      if (_source == null || !sources.any((s) => s.id == _source!.id)) {
        _source = sources.first;
        WidgetsBinding.instance.addPostFrameCallback((_) => _load());
      }
      return Column(children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(Icons.travel_explore, size: 18, color: LK.accent),
                  label: Text('Tutte le sorgenti', style: LK.body(13)),
                  selected: _global,
                  selectedColor: LK.accentSoft,
                  backgroundColor: LK.card,
                  side: BorderSide(color: LK.border),
                  onSelected: (_) {
                    setState(() => _global = true);
                    _globalSearch();
                  },
                ),
              ),
              for (final s in sources)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: (s.iconUrl ?? '').isEmpty ? null : CircleAvatar(backgroundImage: NetworkImage(s.iconUrl!), backgroundColor: Colors.transparent),
                    label: Text('${s.name} · ${(s.lang ?? '').toUpperCase()}', style: LK.body(13)),
                    selected: !_global && s.id == _source?.id,
                    selectedColor: LK.accentSoft,
                    backgroundColor: LK.card,
                    side: BorderSide(color: LK.border),
                    onSelected: (_) {
                      setState(() {
                        _source = s;
                        _global = false;
                      });
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: TvTextField(
            controller: _q,
            hint: 'Cerca',
            onSubmitted: (v) {
              if (_global) {
                setState(() {});
                _globalSearch();
                return;
              }
              setState(() => _mode = v.trim().isEmpty ? 0 : 2);
              _load();
            },
            decoration: InputDecoration(
              hintText: _global ? 'Cerca in tutte le sorgenti…' : 'Cerca in ${_source?.name ?? ''}…',
              isDense: true,
              prefixIcon: Icon(Icons.search, color: LK.muted),
              suffixIcon: _mode == 2
                  ? IconButton(
                      icon: Icon(Icons.close, color: LK.muted),
                      onPressed: () {
                        _q.clear();
                        setState(() => _mode = 0);
                        _load();
                      },
                    )
                  : null,
              filled: true,
              fillColor: LK.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
            ),
          ),
        ),
        if (_mode != 2 && !_global)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final (i, l) in const [(0, 'Popolari'), (1, 'Novità')])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(l, style: LK.body(13)),
                    selected: _mode == i,
                    selectedColor: LK.accentSoft,
                    backgroundColor: LK.card,
                    side: BorderSide(color: LK.border),
                    onSelected: (_) {
                      setState(() => _mode = i);
                      _load();
                    },
                  ),
                ),
            ]),
          ),
        Expanded(
          child: _global
              ? _globalView()
              : _error != null && _items.isEmpty
              ? _message('La sorgente non risponde:\n$_error')
              : _items.isEmpty && _loading
                  ? Center(child: CircularProgressIndicator(color: LK.accent))
                  : _items.isEmpty
                      ? _message('Nessun risultato.')
                      : NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.pixels > n.metrics.maxScrollExtent - 400 && _hasNext && !_loading) _load(more: true);
                            return false;
                          },
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                            gridDelegate: _grid(context),
                            itemCount: _items.length,
                            itemBuilder: (context, i) {
                              final d = _items[i];
                              final s = _source!;
                              return _MangaTile(
                                title: d.title ?? '',
                                cover: d.cover,
                                sourceId: s.id,
                                managerId: s.managerId ?? s.extensionType,
                                onTap: () => _open(s, d),
                              );
                            },
                          ),
                        ),
        ),
      ]);
    });
  }
}

// ======================================================================
// Estensioni e repository
// ======================================================================
/// Repository ed estensioni (manga o anime).
class ExtensionsPanel extends StatefulWidget {
  final ItemType type;
  const ExtensionsPanel({super.key, this.type = ItemType.manga});
  @override
  State<ExtensionsPanel> createState() => _ExtensionsTabState();
}

class _ExtensionsTabState extends State<ExtensionsPanel> {
  bool get _anime => widget.type == ItemType.anime;
  String _lang = 'tutte';
  String _filter = '';
  final _filterCtl = TextEditingController();
  bool _settingUp = false;
  final Set<String> _busy = {};

  ExtensionManager get ext => MangaStore.I.ext;

  Future<void> _addRepo() async {
    final url = TextEditingController();
    var manager = 'mangayomi';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          backgroundColor: LK.paper,
          title: Text('Aggiungi repository', style: LK.display(20)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TIPO', style: LK.label(10, spacing: 1.2)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final e in MangaStore.managers.entries)
                ChoiceChip(
                  label: Text(e.value, style: LK.body(13)),
                  selected: manager == e.key,
                  selectedColor: LK.accentSoft,
                  onSelected: (_) => setD(() => manager = e.key),
                ),
            ]),
            const SizedBox(height: 12),
            TvTextField(
              controller: url,
              autofocus: true,
              url: true,
              hint: 'Indirizzo del repository',
              decoration: InputDecoration(
                hintText: manager == 'aniyomi' ? 'https://…/index.min.json' : (_anime ? 'https://…/anime_index.json' : 'https://…/manga_index.json'),
                labelText: 'Indirizzo del repository',
              ),
            ),
            if (manager == 'aniyomi' && !MangaStore.I.mihonReady) ...[
              const SizedBox(height: 10),
              Text('Per le estensioni Mihon serve prima attivarne il supporto (lo trovi in questa pagina).', style: LK.body(12.5, color: LK.accent)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Aggiungi')),
          ],
        );
      }),
    );
    if (ok != true || url.text.trim().isEmpty) return;
    if (manager == 'aniyomi' && !MangaStore.I.mihonReady) {
      _snack('Attiva prima il supporto alle estensioni Mihon.');
      return;
    }
    try {
      await ext.addRepo(url.text.trim(), widget.type, manager);
      await ext.refreshExtensions(refreshAvailableSource: true);
      _snack('Repository aggiunto');
    } catch (e) {
      _snack('Non riesco ad aggiungere il repository: $e');
    }
    if (mounted) setState(() {});
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _setupMihon() async {
    setState(() => _settingUp = true);
    try {
      await MangaStore.I.setupMihon();
      _snack('Supporto Mihon attivo');
    } catch (e) {
      _snack('Attivazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _settingUp = false);
    }
  }

  Future<void> _do(Source s, Future<void> Function() action, String done) async {
    setState(() => _busy.add('${s.managerId}${s.id}'));
    try {
      await action();
      _snack(done);
    } catch (e) {
      _snack('Errore: $e');
    } finally {
      if (mounted) setState(() => _busy.remove('${s.managerId}${s.id}'));
    }
  }

  Widget _sourceRow(Source s, {required bool installed}) {
    final busy = _busy.contains('${s.managerId}${s.id}');
    final mid = s.managerId ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.line)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 38,
            height: 38,
            child: (s.iconUrl ?? '').isEmpty
                ? Container(color: LK.accentSoft, alignment: Alignment.center, child: Text((s.name ?? '?')[0], style: LK.display(16, color: LK.accentDark)))
                : Image.network(s.iconUrl!, cacheWidth: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: LK.accentSoft)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name ?? '', style: LK.display(14.5)),
            Text(
              [(s.lang ?? '').toUpperCase(), 'v${installed ? s.version : (s.versionLast ?? s.version)}', MangaStore.managers[mid] ?? mid, if (s.isNsfw == true) '18+'].where((x) => x.isNotEmpty).join(' · '),
              style: LK.label(9, spacing: 0.4),
            ),
          ]),
        ),
        if (busy)
          Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: LK.accent)))
        else if (!installed)
          IconButton(tooltip: 'Installa', icon: Icon(Icons.download_outlined, color: LK.accent), onPressed: () => _do(s, s.install, '${s.name} installata'))
        else ...[
          if (s.hasUpdate == true) IconButton(tooltip: 'Aggiorna', icon: Icon(Icons.system_update_alt, color: LK.accent), onPressed: () => _do(s, s.update, '${s.name} aggiornata')),
          IconButton(tooltip: 'Disinstalla', icon: Icon(Icons.delete_outline, color: LK.muted), onPressed: () => _do(s, s.uninstall, '${s.name} disinstallata')),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final installed = (_anime ? ext.installedAnimeExtensions : ext.installedMangaExtensions).toList();
      final ids = installed.map((s) => '${s.managerId}|${s.id}').toSet();
      var available = (_anime ? ext.availableAnimeExtensions : ext.availableMangaExtensions).where((s) => !ids.contains('${s.managerId}|${s.id}')).toList();
      final langs = {'tutte', ...available.map((s) => (s.lang ?? '').toLowerCase()).where((l) => l.isNotEmpty)}.toList();
      if (_lang != 'tutte') available = available.where((s) => (s.lang ?? '').toLowerCase() == _lang).toList();
      if (_filter.isNotEmpty) available = available.where((s) => (s.name ?? '').toLowerCase().contains(_filter)).toList();
      available.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      final repos = <(String, Repo)>[
        for (final mid in MangaStore.managers.keys)
          for (final r in ext.getReposRx(widget.type, mid).value) (mid, r),
      ];
      final ctrl = AnymeXRuntimeBridge.controller;
      return RefreshIndicator(
        color: LK.accent,
        onRefresh: () => ext.refreshExtensions(refreshAvailableSource: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            Row(children: [
              const Expanded(child: SectionLabel('Repository')),
              TextButton.icon(onPressed: _addRepo, icon: Icon(Icons.add, color: LK.accent, size: 18), label: Text('Aggiungi', style: LK.body(13, color: LK.accent))),
            ]),
            if (repos.isEmpty)
              Text(_anime ? 'Nessun repository. Aggiungi l\'indirizzo di un repository di estensioni anime (Mangayomi o Aniyomi).' : 'Nessun repository. Aggiungi l\'indirizzo di un repository di estensioni Mangayomi o Mihon.', style: LK.body(13.5, color: LK.muted, style: FontStyle.italic))
            else
              for (final (mid, r) in repos)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  decoration: BoxDecoration(color: LK.parchment, borderRadius: BorderRadius.circular(10), border: Border.all(color: LK.parchmentBorder)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name ?? Uri.tryParse(r.url)?.host ?? r.url, style: LK.body(14, color: LK.parchmentInk)),
                        Text('${MangaStore.managers[mid]} · ${r.url}', maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.label(8.5, spacing: 0.2)),
                      ]),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: LK.muted, size: 18),
                      onPressed: () async {
                        await ext.removeRepo(r, widget.type);
                        setState(() {});
                      },
                    ),
                  ]),
                ),
            const SizedBox(height: 10),
            // Supporto Mihon / Tachiyomi
            if (!MangaStore.I.mihonReady)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Estensioni Mihon / Tachiyomi', style: LK.display(16)),
                  const SizedBox(height: 4),
                  Text('Per usarle serve un piccolo motore aggiuntivo (si scarica una volta sola).', style: LK.body(13, color: LK.muted)),
                  const SizedBox(height: 10),
                  if (_settingUp || ctrl.isDownloading.value) ...[
                    LinearProgressIndicator(value: ctrl.downloadProgress.value > 0 ? ctrl.downloadProgress.value : null, color: LK.accent, backgroundColor: LK.line),
                    const SizedBox(height: 6),
                    Text('${ctrl.status.value} ${ctrl.sizeInfo.value}', style: LK.label(9, spacing: 0.3)),
                  ] else
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: _setupMihon, child: const Text('Attiva supporto Mihon')),
                  if (ctrl.error.value.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(ctrl.error.value, style: LK.body(12, color: LK.accent))),
                ]),
              ),
            const SizedBox(height: 18),
            SectionLabel('Installate (${installed.length})'),
            if (installed.isEmpty) Text('Ancora nessuna sorgente installata.', style: LK.body(13.5, color: LK.muted, style: FontStyle.italic)),
            for (final s in installed) _sourceRow(s, installed: true),
            const SizedBox(height: 18),
            SectionLabel('Disponibili (${available.length})'),
            TvTextField(
              controller: _filterCtl,
              hint: 'Filtra per nome…',
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Filtra per nome…',
                isDense: true,
                prefixIcon: Icon(Icons.search, color: LK.muted),
                filled: true,
                fillColor: LK.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final l in langs)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(l == 'tutte' ? 'Tutte' : l.toUpperCase(), style: LK.body(12.5)),
                      selected: _lang == l,
                      selectedColor: LK.accentSoft,
                      backgroundColor: LK.card,
                      side: BorderSide(color: LK.border),
                      onSelected: (_) => setState(() => _lang = l),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            for (final s in available.take(200)) _sourceRow(s, installed: false),
          ],
        ),
      );
    });
  }
}

// ======================================================================
// Novità e cronologia
// ======================================================================
String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Oggi';
  if (diff == 1) return 'Ieri';
  if (diff < 7) return '$diff giorni fa';
  const mesi = ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'];
  return '${d.day} ${mesi[d.month - 1]} ${d.year}';
}

String _two(int n) => n.toString().padLeft(2, '0');

class _EventRow extends StatelessWidget {
  final MangaEvent e;
  final String sub;
  final bool dim;
  final VoidCallback onTap;
  final Widget? trailing;
  const _EventRow({required this.e, required this.sub, required this.onTap, this.dim = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final m = MangaStore.I.byKey(e.mangaKey);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 42,
              height: 60,
              child: m == null || (m.cover ?? '').isEmpty ? Container(color: LK.line) : MangaImage(m.cover!, sourceId: m.sourceId, managerId: m.managerId, tint: m.coverSpineColor == null ? null : Color(m.coverSpineColor!)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(14.5, color: dim ? LK.muted : LK.ink)),
              Text(e.chapterName, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(13.5, color: dim ? LK.muted : LK.ink)),
              Text(sub, style: LK.label(9, spacing: 0.4)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

class _UpdatesTab extends StatelessWidget {
  final Future<void> Function(MangaEvent, {bool resume}) onOpen;
  const _UpdatesTab({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MangaStore.I,
      builder: (context, _) {
        final store = MangaStore.I;
        final list = store.updates.where((e) => store.byKey(e.mangaKey)?.inLibrary ?? false).toList();
        if (list.isEmpty) {
          return RefreshIndicator(
            color: LK.accent,
            onRefresh: () => store.refreshLibrary(),
            child: ListView(children: [
              const SizedBox(height: 60),
              _message('Ancora nessun capitolo nuovo.\nTira giù o premi le due frecce per controllare.'),
            ]),
          );
        }
        final rows = <Widget>[];
        String? lastDay;
        for (final e in list) {
          final day = _dayLabel(e.at);
          if (day != lastDay) {
            rows.add(Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 4), child: Text(day.toUpperCase(), style: LK.label(10, color: LK.accent, spacing: 1.2))));
            lastDay = day;
          }
          final m = store.byKey(e.mangaKey);
          final read = m?.read.contains(e.chapterUrl) ?? false;
          rows.add(_EventRow(
            e: e,
            dim: read,
            sub: read ? 'LETTO' : 'NUOVO',
            onTap: () => onOpen(e),
            trailing: read ? Icon(Icons.check, color: LK.muted, size: 18) : Icon(Icons.fiber_new_outlined, color: LK.accent),
          ));
        }
        return RefreshIndicator(
          color: LK.accent,
          onRefresh: () => store.refreshLibrary(),
          child: ListView(padding: const EdgeInsets.only(bottom: 40), children: rows),
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final Future<void> Function(MangaEvent, {bool resume}) onOpen;
  const _HistoryTab({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MangaStore.I,
      builder: (context, _) {
        final store = MangaStore.I;
        final list = store.history.where((e) => store.byKey(e.mangaKey) != null).toList();
        if (list.isEmpty) return _message('Qui compariranno i capitoli che leggi.');
        final rows = <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: LK.paper,
                      title: Text('Cancellare la cronologia?', style: LK.display(19)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
                        FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancella')),
                      ],
                    ),
                  );
                  if (ok == true) store.clearHistory();
                },
                icon: Icon(Icons.delete_sweep_outlined, color: LK.muted, size: 18),
                label: Text('Cancella tutto', style: LK.body(13, color: LK.muted)),
              ),
            ),
          ),
        ];
        String? lastDay;
        for (final e in list) {
          final day = _dayLabel(e.at);
          if (day != lastDay) {
            rows.add(Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 4), child: Text(day.toUpperCase(), style: LK.label(10, color: LK.accent, spacing: 1.2))));
            lastDay = day;
          }
          final m = store.byKey(e.mangaKey)!;
          final current = m.lastChapter == e.chapterUrl && !m.read.contains(e.chapterUrl);
          rows.add(_EventRow(
            e: e,
            sub: '${_two(e.at.hour)}:${_two(e.at.minute)}${current ? ' · pagina ${m.lastPage + 1}' : ''}',
            onTap: () => onOpen(e, resume: true),
            trailing: IconButton(icon: Icon(Icons.close, color: LK.muted, size: 18), onPressed: () => store.removeHistory(e)),
          ));
        }
        return ListView(padding: const EdgeInsets.only(bottom: 40), children: rows);
      },
    );
  }
}
