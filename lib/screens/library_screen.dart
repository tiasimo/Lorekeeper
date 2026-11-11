import 'package:file_picker/file_picker.dart';
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

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final store = LibraryStore.I;
  bool _importing = false;

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

  void _openBook(Book b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookScreen(book: b)));

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
              store.moveShelfEntry(index, index - 1 < 0 ? 0 : index - 1);
            },
          ),
          if (manual) ListTile(
            leading: const Icon(Icons.chevron_right),
            title: const Text('Sposta a destra'),
            onTap: () {
              Navigator.pop(ctx);
              store.moveShelfEntry(index, index + 1);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: LK.accent),
            title: Text(book != null ? 'Rimuovi dalla libreria' : 'Rimuovi divisorio'),
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
            Text('Tocca un\'illustrazione per aggiungerla in fondo allo scaffale. Tieni premuto un elemento dello scaffale per spostarlo o rimuoverlo.',
                style: LK.body(13, color: LK.muted)),
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
                    onTap: () {
                      store.addDivider(d.id);
                      Navigator.pop(ctx);
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
          return Stack(children: [
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  Padding(
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
                      IconButton(
                        tooltip: 'Impostazioni',
                        icon: Icon(Icons.tune, color: LK.accent),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      ),
                    ]),
                  ),
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Center(
                child: FloatingNav(selected: 0, items: [
                  NavItem(Icons.collections_bookmark_outlined, 'Libreria', () {}),
                  NavItem(Icons.menu_book_outlined, 'Continua a leggere', _continue),
                  NavItem(Icons.add, 'Importa EPUB', _import),
                  NavItem(Icons.tune, 'Impostazioni', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
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

  Widget _shelf() {
    final entries = _visible;
    return Column(children: [
      SizedBox(
        height: 240,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: entries.length + 1,
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
            if (e.startsWith('d:')) {
              final d = DividerArt.byId(e.substring(2));
              if (d == null) return const SizedBox.shrink();
              return GestureDetector(
                onLongPress: () => _entryOptions(e),
                child: Align(alignment: Alignment.bottomCenter, child: Image.asset(d.asset, height: 220, fit: BoxFit.contain)),
              );
            }
            final b = store.byId(e.substring(2));
            if (b == null) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => _openBook(b),
              onLongPress: () => _entryOptions(e),
              child: Align(alignment: Alignment.bottomCenter, child: SpineView.of(b, baseHeight: 205)),
            );
          },
        ),
      ),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: ShelfBoard()),
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
          ]),
        ),
      ),
    );
  }
}
