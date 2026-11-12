import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:home_widget/home_widget.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/dividers.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/spine.dart';
import 'book_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'spine_editor_screen.dart';
import 'manga/manga_detail.dart';
import 'manga/manga_home.dart';
import 'anime/anime_home.dart';
import 'manga/manga_settings.dart';
import '../services/background.dart';
import '../services/manga_store.dart';
import 'stats_screen.dart';
import '../widgets/shelf_backdrop.dart';
import '../widgets/lantern.dart';
import '../widgets/adaptive.dart';
import '../widgets/today_panel.dart';
import '../widgets/home_window.dart';
import '../widgets/shelf_cat.dart';
import '../services/drive_sync.dart';
import '../widgets/decor_objects.dart';
import '../widgets/seasonal.dart';
import '../widgets/shelf_customize.dart';
import '../widgets/shelf_order.dart';
import '../services/home_widget_sync.dart';
import '../services/updater.dart';
import '../widgets/update_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final store = LibraryStore.I;
  bool _importing = false;
  int _mangaView = 0; // manga: 0 libreria, 1 esplora
  int _animeView = 0; // anime: 0 videoteca, 1 esplora, 2 estensioni

  @override
  void initState() {
    super.initState();
    // Controllo silenzioso degli aggiornamenti (al massimo ogni 12 ore).
    Future.delayed(const Duration(seconds: 3), () async {
      final u = await Updater.checkIfDue();
      if (u != null && mounted) showUpdateDialog(context, u);
    });
    // Scorciatoie tenendo premuta l'icona dell'app
    _setupShortcuts();
    // Manga: controllo dei nuovi capitoli in background ogni 3 ore
    Background.setup();
    DriveSync.I.init();
    // e all'apertura (al massimo ogni 12 ore)
    Future.delayed(const Duration(seconds: 6), () => MangaStore.I.refreshIfDue().catchError((_) => 0));
    // Widget "Continua a leggere": apre direttamente l'ultimo libro.
    HomeWidgetSync.update();
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_fromWidget).catchError((_) {});
    _widgetSub = HomeWidget.widgetClicked.listen(_fromWidget, onError: (_) {});
  }

  StreamSubscription<Uri?>? _widgetSub;

  void _setupShortcuts() {
    const qa = QuickActions();
    qa.initialize((type) async {
      // attendo che la libreria sia pronta
      for (var i = 0; i < 40 && !store.loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) return;
      switch (type) {
        case 'novel':
          store.app.section = 0;
          store.saveAppPrefs();
          _continue();
        case 'manga':
          store.app.section = 1;
          store.saveAppPrefs();
          await MangaStore.I.load();
          final m = HomeWidgetSync.lastManga();
          if (m != null && mounted) Navigator.of(context).push(bookRoute(MangaDetail(manga: m)));
        case 'import':
          store.app.section = 0;
          store.saveAppPrefs();
          _import();
      }
    });
    qa.setShortcutItems(const [
      ShortcutItem(type: 'novel', localizedTitle: 'Continua novel', icon: 'ic_shortcut_book'),
      ShortcutItem(type: 'manga', localizedTitle: 'Continua manga', icon: 'ic_shortcut_manga'),
      ShortcutItem(type: 'import', localizedTitle: 'Importa EPUB', icon: 'ic_shortcut_add'),
    ]).catchError((_) {});
  }

  Future<void> _fromWidget(Uri? uri) async {
    if (uri == null || !mounted) return;
    await MangaStore.I.load();
    if (HomeWidgetSync.mangaIsLatest() && mounted) {
      final m = HomeWidgetSync.lastManga()!;
      Navigator.of(context).push(bookRoute(MangaDetail(manga: m)));
      return;
    }
    if (!mounted) return;
    final b = HomeWidgetSync.lastRead();
    if (b != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: b)));
  }

  @override
  void dispose() {
    _widgetSub?.cancel();
    super.dispose();
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['epub'], allowMultiple: true);
    if (res == null) return;
    setState(() => _importing = true);
    var ok = 0;
    final errors = <String>[];
    for (final f in res.files) {
      if (f.path == null) continue;
      try {
        await store.importEpub(f.path!);
        ok++;
      } catch (e) {
        errors.add(f.name);
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    final msg = errors.isEmpty
        ? (ok == 1 ? 'Novel aggiunta allo scaffale' : '$ok novel aggiunte allo scaffale')
        : 'Non sono riuscito a leggere: ${errors.join(', ')}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openBook(Book b) {
    if (!File(b.filePath).existsSync()) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: LK.paper,
          title: Text('Manca il file', style: LK.display(20)),
          content: Text('«${b.title}» è stato ripristinato da un backup senza l\'EPUB. Reimportalo: ritroverà progressi, wiki e note.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: LK.accent),
              onPressed: () {
                Navigator.pop(ctx);
                _import();
              },
              child: const Text('Reimporta EPUB'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.of(context).push(bookRoute(BookScreen(book: b)));
  }

  void _continue() {
    final b = store.lastRead ?? (store.books.isEmpty ? null : store.books.first);
    if (b == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importa prima una novel')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: b)));
  }

  void _entryOptions(String entry) {
    final index = store.shelf.indexOf(entry);
    if (index < 0) return;
    final manual = store.app.shelfSort == 'Manuale' && store.app.shelfFilter == 'Tutti';
    final book = entry.startsWith('b:') ? store.byId(entry.substring(2)) : null;
    showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (book != null)
            ListTile(
              leading: const Icon(Icons.brush_outlined),
              title: const Text('Modifica dorso'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SpineEditorScreen(book: book)));
              },
            ),
          if (manual) ListTile(
            leading: const Icon(Icons.chevron_left),
            title: const Text('Sposta a sinistra'),
            onTap: () {
              Navigator.pop(ctx);
              store.moveInShelf(entry, -1);
            },
          ),
          if (manual) ListTile(
            leading: const Icon(Icons.chevron_right),
            title: const Text('Sposta a destra'),
            onTap: () {
              Navigator.pop(ctx);
              store.moveInShelf(entry, 1);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: LK.accent),
            title: Text(book != null ? 'Rimuovi dalla libreria' : (entry.startsWith('o:') ? 'Togli l\'oggetto' : 'Rimuovi divisorio')),
            onTap: () async {
              Navigator.pop(ctx);
              if (book != null) {
                final ok = await _confirm('Rimuovere "${book.title}"?', 'Verranno cancellati il file e i progressi di lettura.');
                if (ok) await store.deleteBook(book);
              } else {
                store.removeShelfEntry(index);
              }
            },
          ),
        ]),
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LK.paper,
        title: Text(title, style: LK.display(20)),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Rimuovi')),
        ],
      ),
    );
    return r ?? false;
  }

  void _customize() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            Text('Personalizza scaffale', style: LK.display(22)),
            const SizedBox(height: 6),
            Text('Ogni serie ha il suo scaffale. Tieni premuto un libro o un divisorio per spostarlo o rimuoverlo.',
                style: LK.body(13, color: LK.muted)),
            const SizedBox(height: 14),
            StatefulBuilder(builder: (ctx, set) {
              const opts = ['Scelti da me', 'Automatici'];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Segmented(
                  labels: opts,
                  selected: opts.indexOf(store.app.dividers).clamp(0, 1),
                  onChanged: (i) {
                    store.app.dividers = opts[i];
                    store.saveAppPrefs();
                    set(() {});
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  store.app.dividers == 'Automatici'
                      ? 'Lorekeeper mette da solo un\'illustrazione su ogni scaffale.'
                      : 'Tocca un\'illustrazione e scegli su quale scaffale metterla.',
                  style: LK.body(12, color: LK.muted, style: FontStyle.italic),
                ),
              ]);
            }),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.58,
              children: [
                for (final d in DividerArt.all)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _placeDivider(d);
                    },
                    child: Column(children: [
                      Expanded(child: Image.asset(d.asset, fit: BoxFit.contain)),
                      Container(height: 6, color: LK.shelf),
                      const SizedBox(height: 6),
                      Text(d.name, textAlign: TextAlign.center, maxLines: 2, style: LK.body(11, color: LK.muted, style: FontStyle.italic)),
                    ]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final last = store.lastRead;
          final section = store.app.section;
          final wide = isWide(context);
          mangaPaneActive = wide;
          final header = Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
                    child: Row(children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(style: LK.display(27), children: [
                            const TextSpan(text: 'Bentornato '),
                            TextSpan(
                              text: '${store.readerName.isEmpty ? 'lettore' : store.readerName}!',
                              style: TextStyle(fontStyle: FontStyle.italic, color: LK.accent),
                            ),
                          ]),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.only(right: 10), child: HomeWindow()),
                      const Padding(padding: EdgeInsets.only(right: 4), child: HomeLantern()),
                      IconButton(
                        tooltip: 'Impostazioni',
                        icon: LKIcon(LKGlyph.settings, color: LK.accent),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => section == 1 ? const MangaSettingsScreen() : const SettingsScreen(),
                        )),
                      ),
                    ]),
                  );
          // Novel | Manga
          final switcher = Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
            child: Center(
              child: Segmented(
                labels: const ['Novel', 'Manga', 'Anime'],
                selected: section,
                onChanged: (i) {
                  store.app.section = i;
                  store.saveAppPrefs();
                },
              ),
            ),
          );
          final body = Stack(children: [
            if (section == 2)
              SafeArea(
                child: Column(children: [
                  header,
                  if (!wide) switcher,
                  const SizedBox(height: 8),
                  Expanded(child: AnimeSection(view: _animeView, onView: (v) => setState(() => _animeView = v))),
                ]),
              )
            else if (section == 1)
              SafeArea(
                child: Column(children: [
                  header,
                  if (!wide) switcher,
                  const SizedBox(height: 8),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: wide ? 0 : 86),
                      child: MangaSection(view: _mangaView, onExplore: () => setState(() => _mangaView = 1)),
                    ),
                  ),
                ]),
              )
            else
            SafeArea(
              child: ListView(
                padding: EdgeInsets.only(bottom: wide ? 40 : 120),
                children: [
                  header,
                  if (!wide) switcher,
                  const SizedBox(height: 14),
                  if (store.books.length > 1) _sortBar(),
                  _shelf(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _customize,
                        icon: Icon(Icons.edit_outlined, size: 16, color: LK.ink),
                        label: Text('PERSONALIZZA', style: LK.label(11, color: LK.ink, spacing: 1.4)),
                        style: OutlinedButton.styleFrom(backgroundColor: LK.card, side: BorderSide(color: LK.border)),
                      ),
                    ),
                  ),
                  if (store.books.isEmpty) _emptyCard(),
                  if (last != null) _continueCard(last),
                  _journal(),
                ],
              ),
            ),
            if (!wide)
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Center(
                child: section == 2
                    ? FloatingNav(selected: _animeView, items: [
                        NavItem(LKGlyph.library, 'Videoteca', () => setState(() => _animeView = 0)),
                        NavItem(LKGlyph.search, 'Esplora', () => setState(() => _animeView = 1)),
                        NavItem(LKGlyph.settings, 'Estensioni', () => setState(() => _animeView = 2)),
                      ])
                    : section == 1
                    ? FloatingNav(selected: _mangaView, items: [
                        NavItem(LKGlyph.library, 'Libreria', () => setState(() => _mangaView = 0)),
                        NavItem(LKGlyph.search, 'Esplora', () => setState(() => _mangaView = 1)),
                        NavItem(LKGlyph.settings, 'Impostazioni', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MangaSettingsScreen()))),
                      ])
                    : FloatingNav(selected: 0, items: [
                        NavItem(LKGlyph.library, 'Libreria', () {}),
                        NavItem(LKGlyph.read, 'Continua a leggere', _continue),
                        NavItem(LKGlyph.add, 'Importa EPUB', _import),
                        NavItem(LKGlyph.settings, 'Impostazioni', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                      ]),
              ),
            ),
            if (_importing)
              Container(
                color: const Color(0x66000000),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: LK.paper, borderRadius: BorderRadius.circular(16)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: LK.accent),
                    const SizedBox(height: 14),
                    Text('Sistemo i libri sullo scaffale…', style: LK.body(14)),
                  ]),
                ),
              ),
          ]);
          if (!wide) return body;
          // Tablet: barra laterale, contenuto e pannello a destra
          final rail = SideRail(
            selected: section == 2 ? _animeView : (section == 1 ? _mangaView : 0),
            accentIndex: section == 0 ? 2 : null,
            items: section == 2
                ? [
                    NavItem(LKGlyph.library, 'Videoteca', () => setState(() => _animeView = 0)),
                    NavItem(LKGlyph.search, 'Esplora', () => setState(() => _animeView = 1)),
                    NavItem(LKGlyph.settings, 'Estensioni', () => setState(() => _animeView = 2)),
                  ]
                : section == 1
                ? [
                    NavItem(LKGlyph.library, 'Libreria', () => setState(() => _mangaView = 0)),
                    NavItem(LKGlyph.search, 'Esplora', () => setState(() => _mangaView = 1)),
                    NavItem(LKGlyph.settings, 'Impostazioni', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MangaSettingsScreen()))),
                  ]
                : [
                    NavItem(LKGlyph.library, 'Libreria', () {}),
                    NavItem(LKGlyph.read, 'Continua', _continue),
                    NavItem(LKGlyph.add, 'Importa EPUB', _import),
                    NavItem(LKGlyph.chapters, 'Diario', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsScreen()))),
                    NavItem(LKGlyph.settings, 'Impostazioni', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                  ],
            bottom: VerticalSwitch(
              labels: const ['Novel', 'Manga', 'Anime'],
              selected: section,
              onChanged: (i) {
                store.app.section = i;
                store.saveAppPrefs();
              },
            ),
          );
          return Row(children: [
            rail,
            Expanded(child: body),
            if (section == 0) const TodayPanel(),
            if (section == 1 && _mangaView == 0)
              ValueListenableBuilder<SavedManga?>(
                valueListenable: mangaPaneSelection,
                builder: (context, m, _) => m == null
                    ? const SizedBox.shrink()
                    : Container(
                        width: 400,
                        decoration: BoxDecoration(border: Border(left: BorderSide(color: LK.border))),
                        child: EmbeddedPane(
                          onClose: () => mangaPaneSelection.value = null,
                          child: HeroMode(enabled: false, child: MangaDetail(key: ValueKey(m.key), manga: m)),
                        ),
                      ),
              ),
          ]);
        },
      ),
    );
  }

  List<String> get _visible {
    final app = store.app;
    if (app.shelfSort == 'Manuale' && app.shelfFilter == 'Tutti') return store.shelf;
    bool keep(Book b) {
      switch (app.shelfFilter) {
        case 'In corso':
          return b.lastReadAt != null && b.progress < 0.98;
        case 'Da leggere':
          return b.lastReadAt == null;
        case 'Finiti':
          return b.progress >= 0.98;
        default:
          return true;
      }
    }

    final books = [
      for (final e in store.shelf)
        if (e.startsWith('b:') && store.byId(e.substring(2)) != null) store.byId(e.substring(2))!
    ].where(keep).toList();
    switch (app.shelfSort) {
      case 'Titolo':
        books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'Serie':
        books.sort((a, b) {
          final sa = (a.series ?? a.title).toLowerCase(), sb = (b.series ?? b.title).toLowerCase();
          final c = sa.compareTo(sb);
          return c != 0 ? c : (a.seriesIndex ?? 0).compareTo(b.seriesIndex ?? 0);
        });
        break;
      case 'Ultimo letto':
        books.sort((a, b) => (b.lastReadAt ?? DateTime(1970)).compareTo(a.lastReadAt ?? DateTime(1970)));
        break;
    }
    return [for (final b in books) 'b:${b.id}'];
  }

  Widget _sortBar() {
    final app = store.app;
    Widget menu(String label, String value, List<String> opts, void Function(String) set) => PopupMenuButton<String>(
          color: LK.card,
          onSelected: (v) {
            set(v);
            store.saveAppPrefs();
          },
          itemBuilder: (_) => [
            for (final o in opts)
              PopupMenuItem(value: o, child: Text(o, style: LK.body(14, color: o == value ? LK.accent : LK.ink))),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: LK.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$label: ', style: LK.label(10, spacing: 0.6)),
              Text(value, style: LK.body(12)),
              Icon(Icons.expand_more, size: 16, color: LK.muted),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        menu('ORDINA', app.shelfSort, const ['Manuale', 'Serie', 'Titolo', 'Ultimo letto'], (v) => app.shelfSort = v),
        menu('MOSTRA', app.shelfFilter, const ['Tutti', 'In corso', 'Da leggere', 'Finiti'], (v) => app.shelfFilter = v),
      ]),
    );
  }

  static const _decor = ['candela', 'calamaio', 'pianta', 'clessidra', 'pila'];

  Future<void> _placeDivider(DividerArt d) async {
    if (store.app.dividers == 'Automatici') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('I divisori sono in modalità automatica: passa a "Scelti da me" per sceglierli tu')),
      );
      return;
    }
    final groups = store.shelfGroups();
    if (groups.isEmpty) return;
    String key = groups.first.$1;
    if (groups.length > 1) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: LK.paper,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Su quale scaffale?', style: LK.display(19))),
            for (final g in groups)
              ListTile(
                leading: Container(width: 26, height: 8, decoration: BoxDecoration(color: Wood.forKey(g.$1).base, borderRadius: BorderRadius.circular(2))),
                title: Text(g.$2 ?? 'Volumi singoli', style: LK.body(15)),
                onTap: () => Navigator.pop(ctx, g.$1),
              ),
          ]),
        ),
      );
      if (picked == null) return;
      key = picked;
    }
    store.addDividerToShelf(key, d.id);
  }

  Widget _row(String key, List<String> raw, {bool addButton = false}) {
    final auto = store.app.dividers == 'Automatici';
    final entries = <String>[for (final e in raw) if (!(auto && e.startsWith('d:'))) e];
    final books = entries.where((e) => e.startsWith('b:')).length;
    if (auto && books > 0) entries.add('d:${DividerArt.all[key.hashCode.abs() % DividerArt.all.length].id}');
    if (books <= 3 && !entries.any((e) => e.startsWith('o:'))) entries.add('a:${_decor[(key.hashCode ~/ 7).abs() % _decor.length]}');
    final wood = store.app.woodFor(key);
    final season = store.app.decoFor(key) ? currentSeason() : null;
    // compleanno della saga: il giorno in cui hai aggiunto il primo volume
    var sagaBirthday = false;
    final adds = [for (final e in raw) if (e.startsWith('b:')) store.byId(e.substring(2))?.addedAt].whereType<DateTime>().toList()..sort();
    if (key != '_flat' && adds.isNotEmpty) {
      final now = DateTime.now(), first = adds.first;
      sagaBirthday = first.year < now.year && first.month == now.month && first.day == now.day;
    }
    final list = ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: entries.length + (addButton ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == entries.length) {
              return Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Material(
                    color: LK.line,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _import,
                      child: SizedBox(width: 54, height: 54, child: Icon(Icons.add, color: LK.muted)),
                    ),
                  ),
                ),
              );
            }
            final e = entries[i];
            if (e.startsWith('o:') || e.startsWith('a:')) {
              return GestureDetector(
                onLongPress: e.startsWith('o:') ? () => _entryOptions(e) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(alignment: Alignment.bottomCenter, child: DecorObject(e.substring(2), height: 150)),
                ),
              );
            }
            if (e.startsWith('d:')) {
              final d = DividerArt.byId(e.substring(2));
              if (d == null) return const SizedBox.shrink();
              return GestureDetector(
                onLongPress: auto ? null : () => _entryOptions(e),
                child: Align(alignment: Alignment.bottomCenter, child: Image.asset(d.asset, height: 220, fit: BoxFit.contain)),
              );
            }
            final b = store.byId(e.substring(2));
            if (b == null) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => _openBook(b),
              onLongPress: () => _entryOptions(e),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Hero(tag: 'book-${b.id}', child: SpineView.of(b, baseHeight: 205)),
              ),
            );
          },
        );
    // I libri scorrono tra due fianchi di legno e spariscono dietro di essi.
    Widget shade(Alignment from) => IgnorePointer(
          child: Container(
            width: 22,
            decoration: BoxDecoration(gradient: LinearGradient(begin: from, end: -from, colors: const [Color(0x47000000), Color(0x00000000)])),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(children: [
          SizedBox(
            height: 240,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ShelfSide.width - 1),
              child: ClipRect(
                child: Stack(children: [
                  Positioned.fill(child: list),
                  Positioned(left: 0, top: 0, bottom: 0, child: shade(Alignment.centerLeft)),
                  Positioned(right: 0, top: 0, bottom: 0, child: shade(Alignment.centerRight)),
                ]),
              ),
            ),
          ),
          ShelfBoard(wood: wood),
        ]),
        Positioned(left: 0, top: 6, bottom: -5, child: ShelfSide(wood: wood)),
        Positioned(right: 0, top: 6, bottom: -5, child: ShelfSide(wood: wood, right: true)),
        if (season != null) Positioned.fill(child: SeasonalDecor(season: season, boardTop: 240, seed: key.hashCode, sagaBirthday: sagaBirthday)),
        if (store.app.cat) Positioned.fill(child: ShelfCat(rowKey: key, boardTop: 240)),
      ]),
    );
  }

  Widget _shelf() {
    final app = store.app;
    final bg = app.shelfBg;
    final wall = bg != 'Carta' && shelfBackdrops.contains(bg);
    bool wallOf(String k) {
      final b = app.bgFor(k);
      return b != 'Carta' && shelfBackdrops.contains(b);
    }
    if (app.shelfSort != 'Manuale' || app.shelfFilter != 'Tutti') {
      CatBrain.I.setRows(const ['_flat']);
      return ShelfWall(kind: bg, child: _row('_flat', [for (final e in _visible) if (e.startsWith('b:')) e], addButton: true));
    }
    final groups = store.shelfGroups();
    CatBrain.I.setRows(groups.isEmpty ? const [LibraryStore.singleShelf] : [for (final g in groups) g.$1]);
    if (groups.isEmpty) return ShelfWall(kind: bg, child: _row(LibraryStore.singleShelf, const [], addButton: true));
    return Column(children: [
      for (var i = 0; i < groups.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : (wall ? 8 : 0)),
          child: ShelfWall(
            kind: app.bgFor(groups[i].$1),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.fromLTRB(wallOf(groups[i].$1) ? 14 : 24, i == 0 || wallOf(groups[i].$1) ? 4 : 22, wallOf(groups[i].$1) ? 8 : 16, 6),
                child: Row(children: [
                  Flexible(
                    child: shelfTitlePill(
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                          child: Text(groups[i].$2 ?? 'Altri libri', maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(18, color: LK.accent, style: FontStyle.italic)),
                        ),
                        const SizedBox(width: 10),
                        Text('${groups[i].$3.where((e) => e.startsWith('b:')).length} volumi', style: LK.label(10, spacing: 0.6)),
                      ]),
                      onWall: wallOf(groups[i].$1),
                    ),
                  ),
                  const Spacer(),
                  if (groups.length > 1)
                    IconButton(
                      tooltip: 'Cambia l\'ordine degli scaffali',
                      visualDensity: VisualDensity.compact,
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: LK.paper.withValues(alpha: 0.88), shape: BoxShape.circle),
                        child: Icon(Icons.swap_vert, size: 17, color: LK.muted),
                      ),
                      onPressed: () => showShelfOrder(context),
                    ),
                  IconButton(
                    tooltip: 'Personalizza lo scaffale',
                    visualDensity: VisualDensity.compact,
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: LK.paper.withValues(alpha: 0.88), shape: BoxShape.circle),
                      child: Icon(Icons.format_paint_outlined, size: 17, color: LK.muted),
                    ),
                    onPressed: () => showShelfCustomize(context, key: groups[i].$1, title: groups[i].$2 ?? 'Altri libri'),
                  ),
                ]),
              ),
              _row(groups[i].$1, groups[i].$3, addButton: i == groups.length - 1),
            ]),
          ),
        ),
    ]);
  }

  Widget _emptyCard() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: LK.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Lo scaffale è vuoto', style: LK.display(20)),
            const SizedBox(height: 6),
            Text('Importa i tuoi file EPUB: la copertina arriva dal file e il dorso prende i suoi colori.', style: LK.body(14, color: LK.muted)),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: LK.accent),
              onPressed: _import,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Importa EPUB'),
            ),
          ]),
        ),
      );

  Widget _continueCard(Book b) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Material(
          color: LK.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: b))),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: LK.line)),
              child: Row(children: [
                BookCover(book: b, width: 54, height: 78),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CONTINUA A LEGGERE', style: LK.label(10, spacing: 2)),
                    const SizedBox(height: 4),
                    Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(18)),
                    if (b.chapters.isNotEmpty)
                      Text(b.chapters[b.lastChapter.clamp(0, b.chapters.length - 1)].title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(13, color: LK.muted, style: FontStyle.italic)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(value: b.progress, minHeight: 4, backgroundColor: LK.line, color: LK.accent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${(b.progress * 100).round()}%', style: LK.label(11, spacing: 0)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _journal() {
    final s = store.secondsThisWeek;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    final time = h > 0 ? '${h}h ${m}m' : '${m}m';
    Widget stat(String v, String l) => Expanded(
          child: Column(children: [
            Text(v, style: LK.display(22, color: LK.accentDark)),
            const SizedBox(height: 2),
            Text(l, textAlign: TextAlign.center, style: LK.label(9, color: LK.parchmentInk, spacing: 1)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsScreen())),
        child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: LK.parchment, borderRadius: BorderRadius.circular(6), border: Border.all(color: LK.parchmentBorder)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: LK.parchmentBorder)),
          child: Column(children: [
            Text('DIARIO DI LETTURA', style: LK.display(15)),
            const SizedBox(height: 14),
            Row(children: [
              stat('${store.streak}', 'GIORNI DI FILA'),
              stat('${store.chaptersRead}', 'CAPITOLI LETTI'),
              stat(time, 'QUESTA SETTIMANA'),
            ]),
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final goal = store.app.goalMinutes;
              final today = store.secondsToday ~/ 60;
              final done = today >= goal;
              return Column(children: [
                Row(children: [
                  Text('OGGI', style: LK.label(9, color: LK.parchmentInk, spacing: 1)),
                  const Spacer(),
                  Text(done ? 'Obiettivo raggiunto ✦' : '$today / $goal min', style: LK.body(12, color: LK.parchmentInk)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (today / goal).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: LK.parchmentBorder.withValues(alpha: 0.5),
                    color: LK.accent,
                  ),
                ),
              ]);
            }),
            const SizedBox(height: 12),
            Text('CALENDARIO E STATISTICHE ›', style: LK.label(9.5, color: LK.accent, spacing: 1.2)),
          ]),
        ),
      ),
      ),
    );
  }
}
