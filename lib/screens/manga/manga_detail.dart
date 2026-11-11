import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';

import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/manga_image.dart';
import 'anilist_ui.dart';
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

  Future<void> _refresh() async {
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
        if (m.read.contains(ord[i].url) && i + 1 < ord.length) return (ord[i + 1], 0);
        return (ord[i], m.lastPage);
      }
    }
    final first = ord.firstWhere((c) => !m.read.contains(c.url), orElse: () => ord.first);
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
                  const BackLink(trail: 'Manga'),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 116,
                      height: 170,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 12, offset: Offset(0, 5))]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: (m.cover ?? '').isEmpty ? Container(color: LK.accentSoft) : MangaImage(m.cover!, sourceId: m.sourceId, managerId: m.managerId),
                      ),
                    ),
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
                        Text('${m.chapters.length} capitoli · ${m.read.length} letti', style: LK.label(9.5, spacing: 0.6)),
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
                  final read = m.read.contains(c.url);
                  final current = c.url == m.lastChapter;
                  return ListTile(
                    dense: true,
                    title: Text(c.name, style: LK.body(14.5, color: read ? LK.muted : LK.ink)),
                    subtitle: Text(
                      [if ((c.scanlator ?? '').isNotEmpty) c.scanlator!, if (current && !read) 'pagina ${m.lastPage + 1}'].join(' · '),
                      style: LK.label(9, spacing: 0.3),
                    ),
                    trailing: read ? Icon(Icons.check, color: LK.muted, size: 18) : (current ? Icon(Icons.bookmark, color: LK.accent, size: 18) : null),
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
