import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';

import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/manga_image.dart';
import '../../services/manga_downloads.dart';
import '../spine_editor_screen.dart';
import 'anilist_ui.dart';
import 'manga_categories.dart';
import 'manga_reader.dart';

/// Scheda del manga: copertina, trama, generi e capitoli.
class MangaDetail extends StatefulWidget {
  final SavedManga manga;
  const MangaDetail({super.key, required this.manga});
  @override
  State<MangaDetail> createState() => _MangaDetailState();
}

class _MangaDetailState extends State<MangaDetail> {
  final store = MangaStore.I;
  SavedManga get m => widget.manga;
  bool _loading = false;
  String? _error;
  bool _newestFirst = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    store.ensureBridge().then((_) => _refresh());
  }

  Source? get _source => store.sourceFor(m);

  /// Manga importato da AniList: alla prima apertura si sceglie dove leggerlo.
  Future<void> _chooseSource() async {
    await store.ensureBridge();
    if (!mounted) return;
    final picked = await showModalBottomSheet<(Source, DMedia)>(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SourceSearchSheet(titles: [m.title]),
    );
    if (picked == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final dest = await store.attachSource(m, picked.$1, picked.$2);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MangaDetail(manga: dest)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Non riesco a collegare la sorgente: $e';
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (m.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _chooseSource());
      return;
    }
    final s = _source;
    if (s == null) {
      if (mounted) setState(() => _error = 'La sorgente «${m.sourceName}» non è installata: reinstallala da Estensioni.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await store.refresh(s, m);
    } catch (e) {
      if (mounted) setState(() => _error = 'Non riesco a caricare i capitoli: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _menu(String v) async {
    final dl = MangaDownloads.I;
    final ord = m.ordered;
    switch (v) {
      case 'dl5':
        final start = m.lastChapter == null ? 0 : ord.indexWhere((c) => c.url == m.lastChapter).clamp(0, ord.length);
        dl.enqueue(m, ord.skip(start).where((c) => !m.isRead(c)).take(5));
      case 'dlUnread':
        dl.enqueue(m, ord.where((c) => !m.isRead(c)));
      case 'dlAll':
        dl.enqueue(m, ord);
      case 'delRead':
        await dl.deleteAll(m, onlyRead: true);
      case 'delAll':
        await dl.deleteAll(m);
      case 'auto':
        await dl.setAutoDelete(!dl.autoDelete);
      case 'cat':
        await editMangaCategories(context, m);
      case 'spine':
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SpineEditorScreen(
            book: m.spineBook,
            onSave: (b) {
              m.applySpine(b);
              store.save();
            },
          ),
        ));
      case 'migrate':
        final picked = await showModalBottomSheet<(Source, DMedia)>(
          context: context,
          backgroundColor: LK.paper,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => SourceSearchSheet(titles: [m.title], title: 'Sposta su un\'altra sorgente', excludeSourceId: m.sourceId),
        );
        if (picked == null || !mounted) return;
        setState(() => _loading = true);
        try {
          final dest = await store.migrate(m, picked.$1, picked.$2);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MangaDetail(manga: dest)));
          return;
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Migrazione non riuscita: $e')));
        }
        if (mounted) setState(() => _loading = false);
    }
    if (mounted) setState(() {});
  }

  void _read(MChapter c, {int page = 0}) {
    final s = _source;
    if (s == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaReader(manga: m, source: s, chapter: c, startPage: page))).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Capitolo da cui riprendere: l'ultimo aperto, o il primo non letto.
  (MChapter, int)? get _resume {
    final ord = m.ordered;
    if (ord.isEmpty) return null;
    if (m.lastChapter != null) {
      final i = ord.indexWhere((c) => c.url == m.lastChapter);
      if (i >= 0) {
        if (m.isRead(ord[i]) && i + 1 < ord.length) return (ord[i + 1], 0);
        return (ord[i], m.lastPage);
      }
    }
    final first = ord.firstWhere((c) => !m.isRead(c), orElse: () => ord.first);
    return (first, 0);
  }

  @override
  Widget build(BuildContext context) {
    final ord = m.ordered;
    final list = _newestFirst ? ord.reversed.toList() : ord;
    final resume = _resume;
    return Scaffold(
      body: TabletSafeArea(
        child: RefreshIndicator(
          color: LK.accent,
          onRefresh: _refresh,
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(children: [
                    const Expanded(child: BackLink(trail: 'Manga')),
                    ListenableBuilder(
                      listenable: MangaDownloads.I,
                      builder: (context, _) => PopupMenuButton<String>(
                        color: LK.card,
                        icon: Icon(Icons.more_vert, color: LK.ink),
                        onSelected: _menu,
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'dl5', child: Text('Scarica i prossimi 5 capitoli', style: LK.body(14))),
                          PopupMenuItem(value: 'dlUnread', child: Text('Scarica i non letti', style: LK.body(14))),
                          PopupMenuItem(value: 'dlAll', child: Text('Scarica tutto', style: LK.body(14))),
                          PopupMenuItem(value: 'delRead', child: Text('Elimina gli scaricati già letti', style: LK.body(14))),
                          PopupMenuItem(value: 'delAll', child: Text('Elimina tutti gli scaricati (${MangaDownloads.I.downloadedCount(m)})', style: LK.body(14))),
                          CheckedPopupMenuItem(value: 'auto', checked: MangaDownloads.I.autoDelete, child: Text('Elimina dopo la lettura', style: LK.body(14))),
                          const PopupMenuDivider(),
                          PopupMenuItem(value: 'cat', child: Text('Categorie…', style: LK.body(14))),
                          PopupMenuItem(value: 'spine', child: Text('Modifica il dorso', style: LK.body(14))),
                          PopupMenuItem(value: 'migrate', child: Text('Migra a un\'altra sorgente', style: LK.body(14))),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    bookHero(m.spineBook, Container(
                      width: 116,
                      height: 170,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 12, offset: Offset(0, 5))]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: (m.cover ?? '').isEmpty ? Container(color: LK.accentSoft) : MangaImage(m.cover!, sourceId: m.sourceId, managerId: m.managerId, tint: m.coverSpineColor == null ? null : Color(m.coverSpineColor!)),
                      ),
                    )),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.title, style: LK.display(22)),
                        if ((m.author ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(m.author!, style: LK.body(14, color: LK.muted, style: FontStyle.italic)),
                        ],
                        const SizedBox(height: 6),
                        Text(m.sourceName.toUpperCase(), style: LK.label(9.5, color: LK.accent, spacing: 1.2)),
                        const SizedBox(height: 4),
                        Text('${m.chapters.length} capitoli · ${m.chapters.where(m.isRead).length} letti', style: LK.label(9.5, spacing: 0.6)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: LK.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: resume == null ? null : () => _read(resume.$1, page: resume.$2),
                          icon: LKIcon(LKGlyph.read, color: LK.onAccent, size: 20),
                          label: Text(
                            resume == null ? 'LEGGI' : (m.lastChapter == null ? 'INIZIA' : 'CONTINUA · ${resume.$1.number.isEmpty ? resume.$1.name : 'CAP. ${resume.$1.number}'}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LK.label(11.5, color: LK.onAccent, spacing: 1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(side: BorderSide(color: m.inLibrary ? LK.accent : LK.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => setState(() => store.toggleLibrary(m)),
                        icon: Icon(m.inLibrary ? Icons.bookmark : Icons.bookmark_add_outlined, color: LK.accent),
                        label: Text(m.inLibrary ? 'In libreria' : 'Aggiungi', style: LK.body(13.5)),
                      ),
                    ),
                  ]),
                  AniListCard(manga: m),
                  if ((m.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Text(m.description!.trim(), maxLines: _expanded ? null : 4, overflow: _expanded ? null : TextOverflow.ellipsis, style: LK.body(14.5, height: 1.55)),
                    ),
                  ],
                  if (m.genres.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final g in m.genres.take(12)) Chip2(g)]),
                  ],
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(child: SectionLabel('Capitoli (${m.chapters.length})')),
                    IconButton(
                      tooltip: _newestFirst ? 'Dal più recente' : 'Dal primo',
                      icon: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward, color: LK.muted, size: 20),
                      onPressed: () => setState(() => _newestFirst = !_newestFirst),
                    ),
                  ]),
                  if (m.pending)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: LK.parchment, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.parchmentBorder)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Arriva dalla tua lista AniList', style: LK.display(16, color: LK.parchmentInk)),
                        const SizedBox(height: 4),
                        Text('Scegli una volta sola dove leggerlo: poi i capitoli compaiono qui.', style: LK.body(13.5, color: LK.parchmentInk)),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: LK.accent),
                          onPressed: _chooseSource,
                          icon: const Icon(Icons.travel_explore, size: 18),
                          label: const Text('Scegli la sorgente'),
                        ),
                      ]),
                    ),
                  if (_loading && m.chapters.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: LK.accent))),
                  if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: LK.body(13.5, color: LK.accent))),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
              sliver: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  final read = m.isRead(c);
                  final current = c.url == m.lastChapter;
                  return ListTile(
                    dense: true,
                    title: Text(c.name, style: LK.body(14.5, color: read ? LK.muted : LK.ink)),
                    subtitle: Text(
                      [if ((c.scanlator ?? '').isNotEmpty) c.scanlator!, if (current && !read) 'pagina ${m.lastPage + 1}'].join(' · '),
                      style: LK.label(9, spacing: 0.3),
                    ),
                    leading: m.bookmarks.contains(c.url) ? Icon(Icons.bookmark, color: LK.gold, size: 18) : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (read) Icon(Icons.check, color: LK.muted, size: 18) else if (current) Icon(Icons.play_arrow_rounded, color: LK.accent, size: 20),
                      ListenableBuilder(
                        listenable: MangaDownloads.I,
                        builder: (context, _) {
                          final dl = MangaDownloads.I;
                          if (dl.isQueued(c)) {
                            final v = dl.progress[c.url] ?? 0;
                            return IconButton(
                              tooltip: 'Annulla',
                              onPressed: () => dl.cancel(c),
                              icon: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(value: v > 0 ? v : null, strokeWidth: 2.2, color: LK.accent)),
                            );
                          }
                          if (dl.isDownloaded(m, c)) {
                            return IconButton(tooltip: 'Elimina download', onPressed: () => dl.delete(m, c), icon: Icon(Icons.download_done, color: LK.accent, size: 20));
                          }
                          return IconButton(tooltip: 'Scarica', onPressed: () => dl.enqueue(m, [c]), icon: Icon(Icons.download_for_offline_outlined, color: LK.muted, size: 20));
                        },
                      ),
                    ]),
                    onTap: () => _read(c, page: current && !read ? m.lastPage : 0),
                    onLongPress: () => setState(() => store.markRead(m, c, read: !read)),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
