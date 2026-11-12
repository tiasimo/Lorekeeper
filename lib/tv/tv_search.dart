import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';

import '../services/anime_store.dart';
import '../services/manga_store.dart';
import '../widgets/manga_image.dart';
import 'tv_anime_detail.dart';
import 'tv_manga_detail.dart';
import 'tv_widgets.dart';

/// Ricerca sulla TV: scrivi un titolo e cerca in tutte le sorgenti anime o manga installate.
class TvSearch extends StatefulWidget {
  final ValueChanged<(String, String)>? onFocusInfo;
  const TvSearch({super.key, this.onFocusInfo});
  @override
  State<TvSearch> createState() => _TvSearchState();
}

class _TvSearchState extends State<TvSearch> {
  final _q = TextEditingController();
  bool _anime = true;
  final List<(Source, List<DMedia>)> _res = [];
  int _pending = 0, _run = 0;

  List<Source> get _sources => (_anime ? MangaStore.I.ext.installedAnimeExtensions : MangaStore.I.ext.installedMangaExtensions).toList();

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    await MangaStore.I.ensureBridge();
    final my = ++_run;
    final sources = _sources;
    setState(() {
      _res.clear();
      _pending = sources.length;
    });
    for (final s in sources) {
      s.methods.search(q, 1, []).then((r) {
        if (my != _run || !mounted || r.list.isEmpty) return;
        setState(() => _res.add((s, r.list)));
      }).catchError((_) {}).whenComplete(() {
        if (my == _run && mounted) setState(() => _pending--);
      });
    }
  }

  void _open(Source s, DMedia d) {
    if (_anime) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvAnimeDetail(anime: AnimeStore.I.entry(s, d))));
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvMangaDetail(manga: MangaStore.I.entry(s, d))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(56, 16, 56, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              style: tvDisplay(24),
              cursorColor: TV.accent,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Scrivi il titolo e premi Cerca',
                hintStyle: tvBody(20, color: TV.muted),
                prefixIcon: const Icon(Icons.search, color: TV.muted, size: 28),
                filled: true,
                fillColor: const Color(0x14F3E7CF),
                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: TV.accent, width: 3)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          TvButton(label: 'Anime', primary: _anime, onSelect: () => setState(() => _anime = true)),
          const SizedBox(width: 10),
          TvButton(label: 'Manga', primary: !_anime, onSelect: () => setState(() => _anime = false)),
          const SizedBox(width: 10),
          TvButton(label: 'Cerca', icon: Icons.search, onSelect: _search),
        ]),
      ),
      if (_pending > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 56), child: LinearProgressIndicator(color: TV.accent, backgroundColor: Color(0x22F3E7CF))),
      if (_sources.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 40, 56, 0),
          child: Text('Nessuna sorgente ${_anime ? 'anime' : 'manga'} installata: aggiungila dalla scheda Estensioni.', style: tvBody(18, color: TV.muted)),
        )
      else if (_res.isEmpty && _pending == 0 && _q.text.trim().isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(56, 40, 56, 0), child: Text('Nessuna sorgente l\'ha trovato.', style: tvBody(18, color: TV.muted))),
      for (final (s, list) in _res)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 20, 56, 4),
            child: Text('${s.name} · ${(s.lang ?? '').toUpperCase()}', style: tvLabel(13, color: TV.peach, spacing: 1)),
          ),
          SizedBox(
            height: 250,
            child: FocusTraversalGroup(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.fromLTRB(56, 14, 56, 14),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 22),
                itemBuilder: (_, i) {
                  final d = list[i];
                  return TvFocus(
                    scale: 1.1,
                    radius: BorderRadius.circular(8),
                    onFocus: (f) {
                      if (f) widget.onFocusInfo?.call((d.title ?? '', s.name ?? ''));
                    },
                    onSelect: () => _open(s, d),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 150,
                        height: 214,
                        child: (d.cover ?? '').isEmpty
                            ? Container(color: const Color(0xFF3A2E28), alignment: Alignment.center, padding: const EdgeInsets.all(8), child: Text(d.title ?? '', textAlign: TextAlign.center, style: tvDisplay(14)))
                            : MangaImage(d.cover!, sourceId: s.id, managerId: s.managerId ?? s.extensionType),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
    ]);
  }
}
