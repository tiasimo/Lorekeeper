import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';

import '../../services/anilist.dart';
import '../../services/anime_store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/manga_image.dart';
import '../manga/manga_home.dart';
import 'anime_detail.dart';
import 'anime_player.dart';
import 'anime_widgets.dart';

/// Sezione Anime: videoteca con le custodie, Esplora ed Estensioni.
class AnimeSection extends StatefulWidget {
  final int view; // 0 videoteca, 1 esplora, 2 estensioni
  final ValueChanged<int> onView;
  const AnimeSection({super.key, required this.view, required this.onView});
  @override
  State<AnimeSection> createState() => _AnimeSectionState();
}

class _AnimeSectionState extends State<AnimeSection> {
  final store = AnimeStore.I;
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await store.load();
    try {
      await store.ensureBridge();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _starting = false);
    store.refreshIfDue();
  }

  void _openDetail(SavedAnime a) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimeDetail(anime: a)));

  @override
  Widget build(BuildContext context) {
    if (_starting) return Center(child: CircularProgressIndicator(color: LK.accent));
    if (_error != null && widget.view != 0) {
      return Center(child: Padding(padding: const EdgeInsets.all(30), child: Text('Il motore delle estensioni non parte:\n$_error', textAlign: TextAlign.center, style: LK.body(14, color: LK.muted))));
    }
    switch (widget.view) {
      case 1:
        return SourceExploreTab(
          type: ItemType.anime,
          onExtensions: () => widget.onView(2),
          onOpen: (context, s, d) => _openDetail(store.entry(s, d)),
        );
      case 2:
        return const ExtensionsPanel(type: ItemType.anime);
      default:
        return _Videoteca(onOpen: _openDetail, onExplore: () => widget.onView(1));
    }
  }
}

/// La videoteca, divisa come sulla TV: Sul lettore, Prossimamente, Collezione.
class _Videoteca extends StatefulWidget {
  final void Function(SavedAnime) onOpen;
  final VoidCallback onExplore;
  const _Videoteca({required this.onOpen, required this.onExplore});
  @override
  State<_Videoteca> createState() => _VideotecaState();
}

class _VideotecaState extends State<_Videoteca> {
  static int _remembered = 0; // la sezione resta quella scelta finché l'app è aperta
  int _part = _remembered;

  void Function(SavedAnime) get onOpen => widget.onOpen;
  VoidCallback get onExplore => widget.onExplore;

  void _resume(BuildContext context, SavedAnime a) {
    final s = AnimeStore.I.sourceFor(a);
    final next = a.firstUnwatched;
    if (a.pending || s == null || next == null) return onOpen(a);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimePlayer(anime: a, source: s, episode: next)));
  }

  Future<void> _importAniList(BuildContext context) async {
    final al = AniList.I;
    await al.load();
    if (!al.loggedIn) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Collega AniList dalle impostazioni dei manga, poi riprova.')));
      return;
    }
    try {
      final n = AnimeStore.I.importAniList(await al.myList(type: 'ANIME'));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'La videoteca è già allineata ad AniList' : '$n anime aggiunti da AniList')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AniList non risponde: $e')));
    }
  }

  void _options(BuildContext context, SavedAnime a) => showModalBottomSheet(
        context: context,
        backgroundColor: LK.paper,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(a.title, style: LK.display(18))),
            ListTile(
              leading: Icon(Icons.bookmark_outline, color: LK.accent),
              title: Text('Sposta in…', style: LK.body(15)),
              subtitle: Text('Ora: ${animeListLabel(a)}', style: LK.body(12.5, color: LK.muted)),
              onTap: () {
                Navigator.pop(ctx);
                showAnimeListSheet(context, a);
              },
            ),
            for (final st in caseStyles)
              ListTile(
                leading: Icon(Icons.style_outlined, color: LK.accent),
                title: Text('Custodia $st', style: LK.body(15)),
                trailing: a.caseStyle == st ? Icon(Icons.check, color: LK.accent) : null,
                onTap: () {
                  a.caseStyle = st;
                  AnimeStore.I.save();
                  Navigator.pop(ctx);
                },
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AnimeStore.I,
      builder: (context, _) {
        final store = AnimeStore.I;
        final lib = store.library;
        for (final a in lib) {
          store.ensureColor(a);
        }
        final player = lib.where((a) => a.section == 0).toList()..sort(SavedAnime.compareOnPlayer);
        final plan = lib.where((a) => a.section == 1).toList()..sort((x, y) => y.addedAt.compareTo(x.addedAt));
        final done = lib.where((a) => a.section == 2).toList();
        final dropped = lib.where((a) => a.section == 3).toList();
        final counts = [player.length, plan.length, done.length + dropped.length];
        // il primo disco sul lettore che ha un episodio da guardare
        final cont = player.where((a) => a.listStatus != 'PAUSED' && !a.pending && a.firstUnwatched != null && (a.lastWatchedAt != null || a.watchedUpTo > 0)).firstOrNull;
        final shelves = switch (_part) {
          0 => [
              ('In onda', player.where((a) => a.listStatus != 'PAUSED' && a.mediaStatus == 'RELEASING').toList()),
              ('In corso', player.where((a) => a.listStatus != 'PAUSED' && a.mediaStatus != 'RELEASING').toList()),
              ('In pausa', player.where((a) => a.listStatus == 'PAUSED').toList()),
            ],
          1 => [('Da vedere', plan)],
          _ => [('Completati', done), ('Abbandonati', dropped)],
        };
        final empty = shelves.every((g) => g.$2.isEmpty);
        return RefreshIndicator(
          color: LK.accent,
          onRefresh: () => store.refreshLibrary(),
          child: ListView(padding: const EdgeInsets.only(bottom: 110), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Center(
                child: FittedBox(
                  child: Segmented(
                    labels: [
                      for (final (i, n) in const ['Sul lettore', 'Prossimamente', 'Collezione'].indexed) counts[i] > 0 ? '$n ${counts[i]}' : n,
                    ],
                    selected: _part,
                    onChanged: (i) => setState(() => _part = _remembered = i),
                  ),
                ),
              ),
            ),
            if (lib.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
                child: Column(children: [
                  Text('La videoteca è vuota', style: LK.display(20)),
                  const SizedBox(height: 6),
                  Text('Cerca un anime in Esplora (dopo aver installato una sorgente anime) oppure importa la tua lista AniList.', textAlign: TextAlign.center, style: LK.body(14, color: LK.muted)),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, children: [
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: onExplore, child: const Text('Esplora')),
                    OutlinedButton(onPressed: () => _importAniList(context), child: const Text('Importa da AniList')),
                  ]),
                ]),
              )
            else if (empty)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 30, 28, 0),
                child: Text(
                  switch (_part) {
                    0 => 'Nessun anime sul lettore. Iniziane uno da Prossimamente o cercalo in Esplora: appena guardi un episodio arriva qui.',
                    1 => 'Niente in programma. Aggiungi qui gli anime che vuoi guardare più avanti con «Aggiungi a…» nella loro scheda.',
                    _ => 'La collezione è vuota. Gli anime arrivano qui da soli quando la serie è conclusa e hai visto l\'ultimo episodio.',
                  },
                  textAlign: TextAlign.center,
                  style: LK.body(14, color: LK.muted),
                ),
              ),
            if (_part == 0 && cont != null) _continue(context, cont),
            for (final (name, list) in shelves)
              if (list.isNotEmpty) _shelf(context, name, list),
            if (lib.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _importAniList(context),
                    icon: Icon(Icons.sync, size: 18, color: LK.accent),
                    label: Text('Allinea con AniList', style: LK.body(13.5, color: LK.accent)),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _continue(BuildContext context, SavedAnime a) {
    final next = a.firstUnwatched;
    final pos = next == null ? 0 : (a.positions[next.url] ?? 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Material(
        color: LK.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _resume(context, a),
          onLongPress: () => onOpen(a),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: LK.line)),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  height: 68,
                  child: Stack(fit: StackFit.expand, children: [
                    (a.cover ?? '').isEmpty ? Container(color: LK.accentSoft) : MangaImage(a.cover!, sourceId: a.sourceId, managerId: a.managerId),
                    Container(color: const Color(0x33000000)),
                    Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(color: Color(0xEEFAF7F2), shape: BoxShape.circle),
                        child: Icon(Icons.play_arrow, color: LK.accent, size: 20),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('CONTINUA A GUARDARE', style: LK.label(9.5, spacing: 1.6)),
                  const SizedBox(height: 3),
                  Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(16)),
                  if (next != null)
                    Text(
                      'Ep. ${a.numberOf(next)}${pos > 0 ? ' · ripreso da ${pos ~/ 60} min' : ''}',
                      style: LK.body(12.5, color: LK.muted, style: FontStyle.italic),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _shelf(BuildContext context, String name, List<SavedAnime> list) {
    return LayoutBuilder(builder: (context, c) {
      final inner = c.maxWidth - 32 - 24;
      final caseW = inner >= 560 ? 120.0 : 100.0;
      final perRow = ((inner + 12) / (caseW + 12)).floor().clamp(1, 20);
      final rows = <List<SavedAnime>>[for (var i = 0; i < list.length; i += perRow) list.sublist(i, (i + perRow).clamp(0, list.length))];
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(children: [
              Text(name, style: LK.display(17, color: LK.accent, style: FontStyle.italic)),
              const SizedBox(width: 8),
              Text('${list.length} SERIE', style: LK.label(9.5, spacing: 1)),
            ]),
          ),
          for (final row in rows) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: LK.dark ? const [Color(0xFF2E2620), Color(0xFF241D18)] : const [Color(0xFFE9DFCF), Color(0xFFDCCDB6)]),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < row.length; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == row.length - 1 ? 0 : 12),
                    child: GestureDetector(
                      onTap: () => onOpen(row[i]),
                      onLongPress: () => _options(context, row[i]),
                      child: Hero(
                        tag: caseHeroTag(row[i]),
                        child: BluRayCase(
                        anime: row[i],
                        width: caseW,
                        tilt: row.length > 1 ? (i == 0 ? 0.14 : (i == row.length - 1 ? -0.14 : 0)) : 0,
                        badge: row[i].newEpisodes > 0 ? row[i].newEpisodes : (row[i].section == 0 && row[i].total > 0 ? row[i].unwatched : null),
                      ),
                      ),
                    ),
                  ),
              ]),
            ),
            Container(
              height: 12,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF6B503D), Color(0xFF4E3A2C)]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
                boxShadow: [BoxShadow(color: Color(0x2E000000), blurRadius: 10, offset: Offset(0, 6))],
              ),
            ),
          ],
        ]),
      );
    });
  }
}
