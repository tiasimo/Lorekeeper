import 'package:flutter/material.dart';

import '../screens/manga/manga_detail.dart';
import '../screens/manga/manga_reader.dart';
import '../services/anilist.dart';
import '../services/manga_store.dart';
import '../widgets/manga_image.dart';
import 'tv_widgets.dart';

/// Scheda di un manga sulla TV: copertina e informazioni a sinistra, capitoli a destra.
class TvMangaDetail extends StatefulWidget {
  final SavedManga manga;
  const TvMangaDetail({super.key, required this.manga});
  @override
  State<TvMangaDetail> createState() => _TvMangaDetailState();
}

class _TvMangaDetailState extends State<TvMangaDetail> {
  final store = MangaStore.I;
  SavedManga get m => widget.manga;
  bool _loading = false, _newestFirst = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (m.pending) return;
    await store.ensureBridge();
    final s = store.sourceFor(m);
    if (s == null) {
      if (mounted) setState(() => _error = 'La sorgente «${m.sourceName}» non è installata su questa TV: installala da Estensioni.');
      return;
    }
    setState(() => _loading = true);
    try {
      await store.refresh(s, m);
    } catch (e) {
      _error = 'Non riesco a caricare i capitoli: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

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
    return (ord.firstWhere((c) => !m.isRead(c), orElse: () => ord.first), 0);
  }

  void _read(MChapter c, {int page = 0}) {
    final s = store.sourceFor(m);
    if (s == null || m.pending) {
      // la scelta della sorgente è quella della versione telefono
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaDetail(manga: m)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaReader(manga: m, source: s, chapter: c, startPage: page))).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final resume = _resume;
    final ord = _newestFirst ? m.ordered.reversed.toList() : m.ordered;
    return Scaffold(
      backgroundColor: TV.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.5, -0.4), radius: 1.2, colors: [Color(0xFF2E2420), TV.bg, TV.bgDeep], stops: [0, 0.6, 1]),
        ),
        padding: const EdgeInsets.fromLTRB(56, 40, 56, 30),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 380,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('‹ MANGA', style: tvLabel(12)),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 300,
                  height: 430,
                  child: (m.cover ?? '').isEmpty ? Container(color: const Color(0xFF3A2E28)) : MangaImage(m.cover!, sourceId: m.sourceId, managerId: m.managerId),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (m.anilistId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF24476E), borderRadius: BorderRadius.circular(12)),
                    child: Text('ANILIST · ${(alStatuses[m.alStatus] ?? 'non in lista').toUpperCase()}', style: tvLabel(11, color: const Color(0xFFE5EEF7), spacing: 0.6)),
                  ),
                Text(m.pending ? 'Sorgente da scegliere' : m.sourceName, style: tvBody(14, color: TV.muted)),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: tvBody(14, color: TV.peach))),
            ]),
          ),
          const SizedBox(width: 40),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 34),
              Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tvDisplay(34)),
              const SizedBox(height: 16),
              Row(children: [
                TvButton(
                  autofocus: true,
                  primary: true,
                  icon: Icons.menu_book,
                  label: m.pending
                      ? 'Scegli la sorgente'
                      : (resume == null ? 'Nessun capitolo' : '${m.lastReadAt == null ? 'Leggi' : 'Continua'} · cap. ${m.chapterNumber(resume.$1)}'),
                  onSelect: () {
                    if (m.pending) {
                      _read(MChapter(url: '', name: '', number: ''));
                    } else if (resume != null) {
                      _read(resume.$1, page: resume.$2);
                    }
                  },
                ),
                const SizedBox(width: 14),
                TvButton(label: _newestFirst ? 'Dal primo' : 'Dall\'ultimo', icon: Icons.swap_vert, onSelect: () => setState(() => _newestFirst = !_newestFirst)),
                if (_loading) ...[
                  const SizedBox(width: 18),
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: TV.accent)),
                ],
              ]),
              const SizedBox(height: 20),
              Text('CAPITOLI · ${ord.length}', style: tvLabel(12, spacing: 2)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                  itemCount: ord.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = ord[i];
                    final read = m.isRead(c);
                    return TvFocus(
                      scale: 1.02,
                      radius: BorderRadius.circular(12),
                      onSelect: () => _read(c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(color: const Color(0x14F3E7CF), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvDisplay(18, color: read ? TV.muted : TV.ink))),
                          if (c.url == m.lastChapter && !read) Text('Pag. ${m.lastPage + 1}', style: tvBody(13, color: TV.peach)),
                          const SizedBox(width: 10),
                          if (read) const Icon(Icons.check, color: Color(0xFF7FC4A0), size: 24),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
