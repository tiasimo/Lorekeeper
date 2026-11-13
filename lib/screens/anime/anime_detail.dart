import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';

import '../../services/anilist.dart';
import '../../services/anime_store.dart';
import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../tv/tv_keyboard.dart';
import '../../widgets/common.dart';
import '../manga/anilist_ui.dart';
import 'anime_player.dart';
import 'anime_widgets.dart';

/// La custodia aperta: libretto con la trama, disco, AniList ed episodi.
class AnimeDetail extends StatefulWidget {
  final SavedAnime anime;
  const AnimeDetail({super.key, required this.anime});
  @override
  State<AnimeDetail> createState() => _AnimeDetailState();
}

class _AnimeDetailState extends State<AnimeDetail> {
  final store = AnimeStore.I;
  late SavedAnime a = widget.anime;
  bool _loading = false;
  String? _error;
  bool _newestFirst = false;

  Source? get _source => store.sourceFor(a);

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    store.ensureBridge().then((_) => _refresh());
    store.ensureColor(a);
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
    if (a.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _chooseSource());
      return;
    }
    final s = _source;
    if (s == null) {
      if (mounted) setState(() => _error = 'La sorgente «${a.sourceName}» non è installata: reinstallala da Estensioni.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await store.refresh(s, a);
    } catch (e) {
      _error = 'La sorgente non risponde: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chooseSource() async {
    final picked = await showModalBottomSheet<(Source, DMedia)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (_) => SourceSearchSheet(titles: [a.title], title: 'Dove vuoi guardarlo?', anime: true),
    );
    if (picked == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final dest = await store.attachSource(a, picked.$1, picked.$2);
      setState(() => a = dest);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _play(MChapter e) {
    final s = _source;
    if (s == null) {
      _chooseSource();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimePlayer(anime: a, source: s, episode: e)));
  }

  Future<void> _linkAniList() async {
    if (!AniList.I.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Collega prima AniList dalle impostazioni dei manga.')));
      return;
    }
    final q = TextEditingController(text: a.title);
    List<AlMedia> res = [];
    var busy = false;
    final picked = await showModalBottomSheet<AlMedia>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> go() async {
          set(() => busy = true);
          try {
            res = await AniList.I.search(q.text.trim(), type: 'ANIME');
          } catch (_) {
            res = [];
          }
          set(() => busy = false);
        }

        if (res.isEmpty && !busy && q.text.isNotEmpty) Future.microtask(go);
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TvTextField(controller: q, hint: 'Cerca su AniList', onSubmitted: (_) => go(), decoration: InputDecoration(prefixIcon: Icon(Icons.search, color: LK.muted), hintText: 'Cerca su AniList')),
            ),
            if (busy) LinearProgressIndicator(color: LK.accent),
            Expanded(
              child: ListView(children: [
                for (final m in res)
                  ListTile(
                    leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 40, height: 58, child: m.cover == null ? Container(color: LK.line) : Image.network(m.cover!, cacheWidth: 120, fit: BoxFit.cover))),
                    title: Text(m.title, style: LK.display(14)),
                    subtitle: Text([m.format, if (m.year != null) '${m.year}', if (m.episodes != null) '${m.episodes} ep.'].whereType<String>().join(' · '), style: LK.label(9.5, spacing: 0.4)),
                    onTap: () => Navigator.pop(ctx, m),
                  ),
              ]),
            ),
          ]),
        );
      }),
    );
    if (picked == null) return;
    await store.linkAniList(a, picked);
  }

  void _caseSheet() => showModalBottomSheet(
        context: context,
        backgroundColor: LK.paper,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('La custodia', style: LK.display(19)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                for (final st in caseStyles)
                  GestureDetector(
                    onTap: () {
                      a.caseStyle = st;
                      store.save();
                      Navigator.pop(ctx);
                    },
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: a.caseStyle == st ? LK.accent : Colors.transparent, width: 2)),
                        child: BluRayCase(anime: SavedAnime.fromJson({...a.toJson(), 'cs': st}), width: 76),
                      ),
                      const SizedBox(height: 6),
                      Text(st, style: LK.body(13)),
                    ]),
                  ),
              ]),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final eps = _newestFirst ? a.ordered.reversed.toList() : a.ordered;
    final next = a.next;
    return Scaffold(
      body: TabletSafeArea(
        child: RefreshIndicator(
          color: LK.accent,
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
            Row(children: [
              const Expanded(child: BackLink(trail: 'Anime')),
              IconButton(tooltip: 'Cambia custodia', onPressed: _caseSheet, icon: Icon(Icons.style_outlined, color: LK.ink)),
              IconButton(
                tooltip: a.inLibrary ? 'Togli dalla videoteca' : 'Metti in videoteca',
                onPressed: () => store.toggleLibrary(a),
                icon: Icon(a.inLibrary ? Icons.bookmark : Icons.bookmark_add_outlined, color: a.inLibrary ? LK.accent : LK.ink),
              ),
            ]),
            // la custodia si apre: la copertina gira sul dorso e scopre libretto e disco
            OpeningCase(anime: a),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ActionChip(
                backgroundColor: const Color(0xFFE5EEF7),
                side: BorderSide.none,
                label: Text(
                  a.anilistId == null ? 'COLLEGA ANILIST' : 'ANILIST · ${(alStatuses[a.alStatus] ?? 'Non in lista').toUpperCase()}',
                  style: LK.label(9.5, color: const Color(0xFF24476E), spacing: 0.6),
                ),
                onPressed: _linkAniList,
              ),
              if (a.alScore > 0) Chip(backgroundColor: LK.navOff, side: BorderSide.none, label: Text('★ ${a.alScore}', style: LK.label(9.5, color: LK.accentDark, spacing: 0.4))),
              Text(a.pending ? 'Sorgente da scegliere' : 'Sorgente: ${a.sourceName}', style: LK.body(12.5, color: LK.muted)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: LK.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: a.pending ? _chooseSource : (next == null ? null : () => _play(next)),
                    icon: Icon(a.pending ? Icons.travel_explore : Icons.play_arrow),
                    label: Text(
                      a.pending ? 'SCEGLI LA SORGENTE' : (next == null ? 'NESSUN EPISODIO' : '${a.lastWatchedAt == null ? 'GUARDA' : 'CONTINUA'} · EP. ${a.numberOf(next)}'),
                      style: LK.label(11.5, color: LK.onAccent, spacing: 1.2),
                    ),
                  ),
                ),
              ),
              if (!a.pending) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: LK.card, side: BorderSide(color: LK.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: _chooseSource,
                    child: Tooltip(message: 'Cambia sorgente', child: Icon(Icons.swap_horiz, color: LK.ink)),
                  ),
                ),
              ],
            ]),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: LK.body(13, color: LK.accent))),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Text('EPISODI · ${a.episodes.length}', style: LK.label(10))),
              if (_loading) SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: LK.accent)),
              IconButton(
                tooltip: _newestFirst ? 'Dal primo' : 'Dall\'ultimo',
                onPressed: () => setState(() => _newestFirst = !_newestFirst),
                icon: Icon(Icons.swap_vert, color: LK.muted),
              ),
            ]),
            for (final e in eps) _episodeRow(e),
          ]),
        ),
      ),
    );
  }

  /// Data di uscita leggibile (le sorgenti la danno in millisecondi, o 0 se non la sanno).
  static String? _date(String? raw) {
    if (raw == null || raw.isEmpty || raw == '0') return null;
    final ms = int.tryParse(raw);
    if (ms == null) return raw;
    if (ms <= 0) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _episodeRow(MChapter e) {
    final seen = a.isWatched(e);
    final pos = a.positions[e.url] ?? 0;
    final current = e.url == a.lastEpisode && !seen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: current ? const Color(0xFFFBF3E8) : LK.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _play(e),
          onLongPress: () => store.markWatched(a, e, watched: !seen),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.line)),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: seen ? LK.line : LK.accentSoft, borderRadius: BorderRadius.circular(10)),
                child: Text('${a.numberOf(e)}', style: LK.display(16, color: seen ? LK.muted : LK.accentDark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(14, color: seen ? LK.muted : LK.ink)),
                  if (pos > 0 && !seen) Text('Ripreso da ${pos ~/ 60}:${(pos % 60).toString().padLeft(2, '0')}', style: LK.body(11.5, color: LK.accent)),
                  if (pos == 0 && _date(e.date) != null) Text(_date(e.date)!, style: LK.body(11.5, color: LK.muted)),
                ]),
              ),
              if (seen) Icon(Icons.check, color: const Color(0xFF2F7A5B), size: 20) else Icon(Icons.play_circle_outline, color: LK.accent),
            ]),
          ),
        ),
      ),
    );
  }
}
