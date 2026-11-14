import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';

import '../services/anime_store.dart';
import '../services/manga_store.dart';
import '../widgets/manga_image.dart';
import 'tv_anime_detail.dart';
import 'tv_keyboard.dart';
import 'tv_widgets.dart';

/// Ricerca sulla TV: scrivi un titolo e lo cerca in tutte le fonti anime installate.
/// Aprendo un risultato arrivi al menu del disco, dove c'è «Aggiungi a…».
class TvSearch extends StatefulWidget {
  const TvSearch({super.key});
  @override
  State<TvSearch> createState() => _TvSearchState();
}

class _TvSearchState extends State<TvSearch> {
  final _q = TextEditingController();
  final List<(Source, List<DMedia>)> _res = [];
  int _pending = 0, _run = 0;

  List<Source> get _sources => MangaStore.I.ext.installedAnimeExtensions.toList();

  @override
  void dispose() {
    _run++;
    _q.dispose();
    super.dispose();
  }

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
    searchSources(
      sources,
      q,
      alive: () => my == _run && mounted,
      onResult: (s, list) {
        if (list.isNotEmpty) setState(() => _res.add((s, list.take(12).toList())));
      },
      onDone: () => setState(() => _pending--),
    );
  }

  void _open(Source s, DMedia d) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvAnimeDetail(anime: AnimeStore.I.entry(s, d))));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(48, 14, 48, 10),
        child: Row(children: [
          Expanded(
            child: TvTextField(
              controller: _q,
              hint: 'Cerca un anime',
              style: tvBody(20, color: TV.ink),
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Premi OK per scrivere il titolo',
                hintStyle: tvBody(18, color: TV.muted),
                prefixIcon: const Icon(Icons.search, color: TV.muted, size: 26),
                filled: true,
                fillColor: TV.panel,
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide.none),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: TV.accent, width: 3)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          TvButton(label: 'Cerca', icon: Icons.search, onSelect: _search),
        ]),
      ),
      if (_pending > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 48), child: LinearProgressIndicator(color: TV.accent, backgroundColor: TV.panelHi, minHeight: 3)),
      if (_sources.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 40, 48, 0),
          child: Text('Nessuna fonte anime installata: aggiungila da Impostazioni › Estensioni, oppure sincronizza con Google Drive per avere quelle del telefono.', style: tvBody(17)),
        )
      else if (_res.isEmpty && _pending == 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 40, 48, 0),
          child: Text(_q.text.trim().isEmpty ? 'Scrivi un titolo: lo cerco in tutte le fonti installate, due alla volta.' : 'Nessuna fonte l\'ha trovato.', style: tvBody(17)),
        ),
      for (final (s, list) in _res)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 18, 48, 0),
            child: Text('${s.name ?? ''} · ${(s.lang ?? '').toUpperCase()}'.toUpperCase(), style: tvLabel(14, color: TV.peach, spacing: 2)),
          ),
          SizedBox(
            height: 262,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(48, 14, 48, 6),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 22),
              itemBuilder: (_, i) {
                final d = list[i];
                return SizedBox(
                  width: 136,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TvFocus(
                      onSelect: () => _open(s, d),
                      child: SizedBox(
                        width: 136,
                        height: 193,
                        child: (d.cover ?? '').isEmpty
                            ? Container(color: TV.panelHi, alignment: Alignment.bottomLeft, padding: const EdgeInsets.all(8), child: Text((d.title ?? '').toUpperCase(), maxLines: 4, overflow: TextOverflow.ellipsis, style: tvDisplay(14, weight: FontWeight.w700)))
                            : MangaImage(d.cover!, sourceId: s.id, managerId: s.managerId ?? s.extensionType),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(d.title ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: tvBody(12.5, color: TV.ink, weight: FontWeight.w600)),
                  ]),
                );
              },
            ),
          ),
        ]),
    ]);
  }
}
