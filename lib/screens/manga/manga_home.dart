import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/manga_image.dart';
import '../../widgets/spine.dart';
import '../../widgets/shelf_backdrop.dart';
import '../../services/library_store.dart';
import '../spine_editor_screen.dart';
import 'anilist_ui.dart';
import 'manga_detail.dart';

/// Sezione Manga: la tua libreria, l'esplorazione delle sorgenti e le estensioni.
class MangaHome extends StatefulWidget {
  const MangaHome({super.key});
  @override
  State<MangaHome> createState() => _MangaHomeState();
}

class _MangaHomeState extends State<MangaHome> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        if (_tab == 0) Positioned.fill(child: ShelfBackdrop(LibraryStore.I.app.mangaShelfBg)),
        TabletSafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BackLink(trail: 'Libreria'),
              Row(children: [
                Expanded(child: Text('Manga', style: LK.display(30))),
                ListenableBuilder(
                  listenable: MangaStore.I,
                  builder: (context, _) => MangaStore.I.refreshing
                      ? Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: LK.accent)))
                      : IconButton(
                          tooltip: 'Cerca nuovi capitoli',
                          icon: Icon(Icons.sync, color: LK.accent, size: 28),
                          onPressed: () async {
                            final n = await MangaStore.I.refreshLibrary();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'Nessun capitolo nuovo' : '$n ${n == 1 ? 'capitolo nuovo' : 'capitoli nuovi'}')));
                            }
                          },
                        ),
                ),
              ]),
              const SizedBox(height: 12),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Segmented(labels: const ['Libreria', 'Esplora', 'AniList', 'Estensioni'], selected: _tab, onChanged: (i) => setState(() => _tab = i)),
                ),
              ),
              const SizedBox(height: 10),
            ]),
          ),
          Expanded(
            child: _error != null
                ? _message('Non riesco ad avviare le estensioni:\n$_error')
                : _starting && _tab != 0
                    ? Center(child: CircularProgressIndicator(color: LK.accent))
                    : IndexedStack(index: _tab, children: [
                        _LibraryTab(onExplore: () => setState(() => _tab = 1)),
                        if (_starting) const SizedBox.shrink() else _ExploreTab(onExtensions: () => setState(() => _tab = 3)),
                        if (_starting) const SizedBox.shrink() else const AniListTab(),
                        if (_starting) const SizedBox.shrink() else const _ExtensionsTab(),
                      ]),
          ),
        ]),
      ),
      ]),
    );
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
// Libreria: scaffali fissi con i dorsi, divisi per stato
// ======================================================================
const _shelfNames = ['In corso', 'Da leggere', 'Completati'];
const _shelfWoods = [Wood('Noce', Color(0xFF6E4B33), Color(0xFF4E3322), Color(0xFF3E2718)), Wood('Quercia', Color(0xFFA9825A), Color(0xFF86633F), Color(0xFF6E4F30)), Wood('Mogano', Color(0xFF7E3B26), Color(0xFF5A2516), Color(0xFF461A0E))];

class _LibraryTab extends StatelessWidget {
  final VoidCallback onExplore;
  const _LibraryTab({required this.onExplore});

  void _open(BuildContext context, SavedManga m) {
    Navigator.of(context).push(bookRoute(MangaDetail(manga: m)));
  }

  void _options(BuildContext context, SavedManga m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(m.title, style: LK.display(17))),
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

  Widget _spine(BuildContext context, SavedManga m) {
    MangaStore.I.ensureSpine(m);
    final b = m.spineBook;
    final badge = m.shelf == 1 ? 0 : m.unread;
    return GestureDetector(
      onTap: () => _open(context, m),
      onLongPress: () => _options(context, m),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
        Hero(tag: 'book-${b.id}', child: SpineView.of(b, baseHeight: 190)),
        if (badge > 0)
          Positioned(
            top: -8,
            child: Builder(builder: (context) {
              // il numero prende i colori del dorso
              final bg = Color(b.spineTitleColor ?? b.spineTextColor);
              final fg = Color(b.spineColor);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                constraints: const BoxConstraints(minWidth: 22),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: m.newChapters > 0 ? fg : bg, width: 1.5),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Text(badge > 999 ? '999+' : '$badge', textAlign: TextAlign.center, style: LK.label(9.5, color: fg, spacing: 0.2)),
              );
            }),
          ),
      ]),
    );
  }

  /// Scaffale fisso: i dorsi vanno a capo su più ripiani.
  Widget _shelf(BuildContext context, int kind, List<SavedManga> list) {
    final wood = _shelfWoods[kind];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(_shelfNames[kind], style: LK.display(20, color: LK.accent).copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(width: 10),
          Text('${list.length} ${list.length == 1 ? 'manga' : 'manga'}', style: LK.label(9.5, spacing: 0.8)),
        ]),
      ),
      LayoutBuilder(builder: (context, c) {
        final inner = c.maxWidth - 32 - ShelfSide.width * 2 - 20;
        // divido i dorsi in ripiani in base alla larghezza
        final rows = <List<SavedManga>>[];
        var cur = <SavedManga>[];
        var used = 0.0;
        for (final m in list) {
          final w = 42.0 * m.spineWidth * 190 / 200 + 6;
          if (used + w > inner && cur.isNotEmpty) {
            rows.add(cur);
            cur = [];
            used = 0;
          }
          cur.add(m);
          used += w;
        }
        if (cur.isNotEmpty) rows.add(cur);
        return Column(children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Stack(clipBehavior: Clip.none, children: [
                Column(children: [
                  SizedBox(
                    height: 230,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: ShelfSide.width + 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (final m in row) Padding(padding: const EdgeInsets.only(right: 6), child: _spine(context, m)),
                      ]),
                    ),
                  ),
                  ShelfBoard(wood: wood),
                ]),
                Positioned(left: 0, top: 6, bottom: -5, child: ShelfSide(wood: wood)),
                Positioned(right: 0, top: 6, bottom: -5, child: ShelfSide(wood: wood, right: true)),
              ]),
            ),
        ]);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MangaStore.I,
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
        final groups = [<SavedManga>[], <SavedManga>[], <SavedManga>[]];
        for (final m in list) {
          groups[m.shelf].add(m);
        }
        // in corso e completati: prima l'ultimo letto; da leggere: prima l'ultimo aggiunto
        groups[0].sort((a, b) => (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));
        groups[1].sort((a, b) => b.addedAt.compareTo(a.addedAt));
        groups[2].sort((a, b) => (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));
        return RefreshIndicator(
          color: LK.accent,
          onRefresh: () => store.refreshLibrary(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              if (store.refreshing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Cerco nuovi capitoli… ${store.refreshDone}/${store.refreshTotal}', style: LK.label(9.5, spacing: 0.6)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: store.refreshTotal == 0 ? null : store.refreshDone / store.refreshTotal, color: LK.accent, backgroundColor: LK.line),
                  ]),
                ),
              for (var k = 0; k < 3; k++)
                if (groups[k].isNotEmpty) _shelf(context, k, groups[k]),
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================
// Esplora
// ======================================================================
class _ExploreTab extends StatefulWidget {
  final VoidCallback onExtensions;
  const _ExploreTab({required this.onExtensions});
  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> {
  Source? _source;
  int _mode = 0; // 0 popolari, 1 novità, 2 ricerca
  final _q = TextEditingController();
  final List<DMedia> _items = [];
  int _page = 1;
  bool _hasNext = false, _loading = false;
  String? _error;
  int _run = 0;

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
    } catch (e) {
      if (my == _run && mounted) setState(() => _error = '$e');
    } finally {
      if (my == _run && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final sources = MangaStore.I.ext.installedMangaExtensions.toList();
      if (sources.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Nessuna sorgente installata.', style: LK.display(18)),
              const SizedBox(height: 8),
              Text('Aggiungi un repository e installa almeno una sorgente manga.', textAlign: TextAlign.center, style: LK.body(14, color: LK.muted)),
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
              for (final s in sources)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: (s.iconUrl ?? '').isEmpty ? null : CircleAvatar(backgroundImage: NetworkImage(s.iconUrl!), backgroundColor: Colors.transparent),
                    label: Text('${s.name} · ${(s.lang ?? '').toUpperCase()}', style: LK.body(13)),
                    selected: s.id == _source?.id,
                    selectedColor: LK.accentSoft,
                    backgroundColor: LK.card,
                    side: BorderSide(color: LK.border),
                    onSelected: (_) {
                      setState(() => _source = s);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              setState(() => _mode = v.trim().isEmpty ? 0 : 2);
              _load();
            },
            decoration: InputDecoration(
              hintText: 'Cerca in ${_source?.name ?? ''}…',
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
        if (_mode != 2)
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
          child: _error != null && _items.isEmpty
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
                                onTap: () {
                                  final m = MangaStore.I.entry(s, d);
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaDetail(manga: m)));
                                },
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
class _ExtensionsTab extends StatefulWidget {
  const _ExtensionsTab();
  @override
  State<_ExtensionsTab> createState() => _ExtensionsTabState();
}

class _ExtensionsTabState extends State<_ExtensionsTab> {
  String _lang = 'tutte';
  String _filter = '';
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
            TextField(
              controller: url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: manager == 'aniyomi' ? 'https://…/index.min.json' : 'https://…/manga_index.json',
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
      await ext.addRepo(url.text.trim(), ItemType.manga, manager);
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
                : Image.network(s.iconUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: LK.accentSoft)),
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
      final installed = ext.installedMangaExtensions.toList();
      final ids = installed.map((s) => '${s.managerId}|${s.id}').toSet();
      var available = ext.availableMangaExtensions.where((s) => !ids.contains('${s.managerId}|${s.id}')).toList();
      final langs = {'tutte', ...available.map((s) => (s.lang ?? '').toLowerCase()).where((l) => l.isNotEmpty)}.toList();
      if (_lang != 'tutte') available = available.where((s) => (s.lang ?? '').toLowerCase() == _lang).toList();
      if (_filter.isNotEmpty) available = available.where((s) => (s.name ?? '').toLowerCase().contains(_filter)).toList();
      available.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      final repos = <(String, Repo)>[
        for (final mid in MangaStore.managers.keys)
          for (final r in ext.getReposRx(ItemType.manga, mid).value) (mid, r),
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
              Text('Nessun repository. Aggiungi l\'indirizzo di un repository di estensioni Mangayomi o Mihon.', style: LK.body(13.5, color: LK.muted, style: FontStyle.italic))
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
                        await ext.removeRepo(r, ItemType.manga);
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
            TextField(
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
