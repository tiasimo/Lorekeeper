import 'package:flutter/material.dart';

import '../screens/anime/anime_detail.dart';
import '../screens/anime/anime_player.dart';
import '../screens/anime/anime_widgets.dart';
import '../services/anilist.dart';
import '../services/anime_store.dart';
import '../services/manga_store.dart';
import 'tv_widgets.dart';

/// La custodia aperta sulla TV: a sinistra custodia e informazioni, a destra gli episodi.
class TvAnimeDetail extends StatefulWidget {
  final SavedAnime anime;
  const TvAnimeDetail({super.key, required this.anime});
  @override
  State<TvAnimeDetail> createState() => _TvAnimeDetailState();
}

class _TvAnimeDetailState extends State<TvAnimeDetail> {
  final store = AnimeStore.I;
  SavedAnime get a => widget.anime;
  bool _loading = false;
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
    if (a.pending) return;
    await store.ensureBridge();
    final s = store.sourceFor(a);
    if (s == null) {
      setState(() => _error = 'La sorgente «${a.sourceName}» non è installata su questa TV: installala da Estensioni.');
      return;
    }
    setState(() => _loading = true);
    try {
      await store.refresh(s, a);
    } catch (e) {
      _error = 'La sorgente non risponde: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _play(MChapter e) {
    final s = store.sourceFor(a);
    if (s == null || a.pending) {
      // la scelta della sorgente è quella della versione telefono
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimeDetail(anime: a)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimePlayer(anime: a, source: s, episode: e)));
  }

  @override
  Widget build(BuildContext context) {
    final next = a.next;
    final eps = a.ordered;
    return Scaffold(
      backgroundColor: TV.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.5, -0.4), radius: 1.2, colors: [Color(0xFF2E2420), TV.bg, TV.bgDeep], stops: [0, 0.6, 1]),
        ),
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 24),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 520,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('‹ VIDEOTECA', style: tvLabel(12)),
              const SizedBox(height: 18),
              OpeningCase(anime: a),
              const SizedBox(height: 18),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (a.anilistId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF24476E), borderRadius: BorderRadius.circular(12)),
                    child: Text('ANILIST · ${(alStatuses[a.alStatus] ?? 'non in lista').toUpperCase()}', style: tvLabel(11, color: const Color(0xFFE5EEF7), spacing: 0.6)),
                  ),
                if (a.alScore > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF5A2A20), borderRadius: BorderRadius.circular(12)),
                    child: Text('★ ${a.alScore}', style: tvLabel(11, color: const Color(0xFFFBE9E2), spacing: 0.4)),
                  ),
                Text(a.pending ? 'Sorgente da scegliere' : a.sourceName, style: tvBody(14, color: TV.muted)),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: tvBody(14, color: TV.peach))),
            ]),
          ),
          const SizedBox(width: 48),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 34),
              Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tvDisplay(34)),
              const SizedBox(height: 16),
              Row(children: [
                TvButton(
                  autofocus: true,
                  primary: true,
                  icon: Icons.play_arrow,
                  label: a.pending ? 'Scegli la sorgente' : (next == null ? 'Nessun episodio' : '${a.lastWatchedAt == null ? 'Guarda' : 'Continua'} · ep. ${a.numberOf(next)}'),
                  onSelect: () {
                    if (a.pending || next != null) _play(next ?? MChapter(url: '', name: '', number: ''));
                  },
                ),
                const SizedBox(width: 14),
                TvButton(
                  label: a.inLibrary ? 'In videoteca' : 'Metti in videoteca',
                  icon: a.inLibrary ? Icons.bookmark : Icons.bookmark_add_outlined,
                  onSelect: () => store.toggleLibrary(a),
                ),
                if (_loading) ...[
                  const SizedBox(width: 18),
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: TV.accent)),
                ],
              ]),
              const SizedBox(height: 22),
              Text('EPISODI · ${eps.length}', style: tvLabel(12, spacing: 2)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                  itemCount: eps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final e = eps[i];
                    final seen = a.isWatched(e);
                    final pos = a.positions[e.url] ?? 0;
                    return TvFocus(
                      scale: 1.02,
                      radius: BorderRadius.circular(14),
                      onSelect: () => _play(e),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0x14F3E7CF), borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          Container(
                            width: 56,
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: seen ? const Color(0x22F3E7CF) : const Color(0x33E0703F), borderRadius: BorderRadius.circular(12)),
                            child: Text('${a.numberOf(e)}', style: tvDisplay(20, color: seen ? TV.muted : TV.ink)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvDisplay(19, color: seen ? TV.muted : TV.ink)),
                              if (pos > 0 && !seen) Text('Ripreso da ${pos ~/ 60} min', style: tvBody(13, color: TV.peach)),
                            ]),
                          ),
                          if (seen) const Icon(Icons.check, color: Color(0xFF7FC4A0), size: 26) else const Icon(Icons.play_circle_outline, color: TV.peach, size: 26),
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
