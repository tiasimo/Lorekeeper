import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/anime/anime_player.dart';
import '../services/anilist.dart';
import '../services/anime_store.dart';
import '../services/drive_sync.dart';
import '../services/manga_store.dart';
import '../widgets/manga_image.dart';
import 'tv_anime_detail.dart';
import 'tv_widgets.dart';

/// «Sul lettore»: il disco che stai guardando a tutto schermo con il suo menu;
/// ◀ ▶ cambiano disco, in basso la striscia dei dischi in corso.
class TvNowPlaying extends StatefulWidget {
  final ValueChanged<int> onGo; // passa a un'altra sezione
  const TvNowPlaying({super.key, required this.onGo});
  @override
  State<TvNowPlaying> createState() => _TvNowPlayingState();
}

class _TvNowPlayingState extends State<TvNowPlaying> {
  String? _selKey;
  final _strip = ScrollController();
  String? _msg;

  static const _caseW = 84.0, _caseGap = 18.0;

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  /// I dischi sul lettore: prima quelli in corso (dall'ultimo guardato), in fondo quelli in pausa.
  List<SavedAnime> _discs() {
    final list = AnimeStore.I.library.where((a) => a.section == 0).toList();
    int rank(SavedAnime a) => a.listStatus == 'PAUSED' ? 1 : 0;
    list.sort((x, y) {
      final r = rank(x).compareTo(rank(y));
      if (r != 0) return r;
      return (y.lastWatchedAt ?? y.addedAt).compareTo(x.lastWatchedAt ?? x.addedAt);
    });
    return list;
  }

  void _move(List<SavedAnime> list, int from, int by) {
    final to = (from + by).clamp(0, list.length - 1);
    if (to == from) return;
    setState(() => _selKey = list[to].key);
    if (_strip.hasClients) {
      final target = (to * (_caseW + _caseGap) - 360).clamp(0.0, _strip.position.maxScrollExtent);
      _strip.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void _openDisc(SavedAnime a, {int pane = 0}) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvAnimeDetail(anime: a, pane: pane))).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _play(SavedAnime a, MChapter e) {
    final s = AnimeStore.I.sourceFor(a);
    if (s == null) {
      _openDisc(a);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimePlayer(anime: a, source: s, episode: e))).then((_) {
      if (mounted) setState(() {});
    });
  }

  String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AnimeStore.I,
      builder: (context, _) {
        final list = _discs();
        if (list.isEmpty) return _empty();
        var i = list.indexWhere((a) => a.key == _selKey);
        if (i < 0) i = 0;
        final a = list[i];
        AnimeStore.I.ensureColor(a);
        return Focus(
          skipTraversal: true,
          canRequestFocus: false,
          onKeyEvent: (node, e) {
            final left = e.logicalKey == LogicalKeyboardKey.arrowLeft, right = e.logicalKey == LogicalKeyboardKey.arrowRight;
            if (!left && !right) return KeyEventResult.ignored;
            if (e is KeyDownEvent || e is KeyRepeatEvent) _move(list, i, left ? -1 : 1);
            return KeyEventResult.handled;
          },
          child: Stack(children: [
            Positioned.fill(child: _backdrop(a)),
            // a sinistra scuro per il testo, in basso scuro per la striscia
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xF00A0A0B), Color(0xC70A0A0B), Color(0x4D0A0A0B)], stops: [0, 0.4, 0.78]),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 320,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x000A0A0B), TV.bg], stops: [0, 0.62]),
                ),
              ),
            ),
            Positioned(left: 48, top: 104, width: 640, child: _menu(a, i, list.length)),
            Positioned(left: 0, right: 0, bottom: 34, child: _stripRow(list, i)),
            const Positioned(right: 48, bottom: 10, child: TvHints(['▲▼ MENU', '◀▶ CAMBIA DISCO', 'OK CONFERMA'])),
          ]),
        );
      },
    );
  }

  Widget _backdrop(SavedAnime a) {
    if ((a.banner ?? '').isNotEmpty) {
      return Image.network(a.banner!, fit: BoxFit.cover, cacheWidth: 960, gaplessPlayback: true, errorBuilder: (_, __, ___) => const ColoredBox(color: TV.bg));
    }
    if ((a.cover ?? '').isNotEmpty) {
      // la copertina è verticale: sta a destra, il resto resta nero
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(width: 620, height: 720, child: MangaImage(a.cover!, sourceId: a.sourceId, managerId: a.managerId)),
      );
    }
    return ColoredBox(color: a.caseColor == null ? TV.panel : Color.lerp(Color(a.caseColor!), TV.bg, 0.5)!);
  }

  Widget _menu(SavedAnime a, int i, int n) {
    final next = a.firstUnwatched;
    final air = a.nextAir;
    final pos = next == null ? 0 : (a.positions[next.url] ?? 0);
    final started = a.watchedUpTo > 0 || a.lastWatchedAt != null;
    final two = (int v) => v.toString().padLeft(2, '0');
    // la prima voce: riprendi, oppure cosa manca per poterlo fare
    final String first;
    final String? trailing;
    VoidCallback action;
    if (a.pending) {
      first = 'Scegli la fonte';
      trailing = null;
      action = () => _openDisc(a);
    } else if (next != null) {
      first = '${started ? 'Riprendi' : 'Inizia'} ep. ${two(a.numberOf(next))}';
      trailing = pos > 0 ? _clock(pos) : null;
      action = () => _play(a, next);
    } else if (air != null) {
      first = 'Ep. ${two(a.nextAirEp ?? a.watchedUpTo + 1)} esce ${tvWhen(air)}';
      trailing = null;
      action = () => _openDisc(a);
    } else {
      first = 'Apri il disco';
      trailing = null;
      action = () => _openDisc(a);
    }
    final total = a.alTotal ?? a.total;
    final meta = [
      if (total > 0) '$total episodi',
      if (a.listStatus == 'PAUSED') 'in pausa',
      if (a.newEpisodes > 0) '${a.newEpisodes} episodi nuovi',
      if (next != null && air != null) 'ep. ${a.nextAirEp ?? ''} ${tvWhen(air)}'.replaceAll('  ', ' '),
      if (a.alScore > 0) 'il tuo voto ★ ${a.alScore % 1 == 0 ? a.alScore.toInt() : a.alScore}',
      a.pending ? 'fonte da scegliere' : a.sourceName,
    ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('DISCO INSERITO · ${two(i + 1)} / ${two(n)}', style: tvMono(12, color: TV.peach, weight: FontWeight.w700).copyWith(letterSpacing: 2)),
      const SizedBox(height: 10),
      Text(a.title.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: tvDisplay(a.title.length > 22 ? 54 : 74, weight: FontWeight.w700).copyWith(height: 1)),
      const SizedBox(height: 10),
      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvBody(15)),
      const SizedBox(height: 24),
      SizedBox(
        width: 414,
        child: Column(children: [
          TvMenuItem(label: first, trailing: trailing, autofocus: true, height: 50, size: 22, onSelect: action),
          const SizedBox(height: 6),
          TvMenuItem(label: 'Selezione episodi', onSelect: () => _openDisc(a)),
          const SizedBox(height: 6),
          TvMenuItem(label: 'Sposta in…', onSelect: () => _openDisc(a, pane: 1)),
          const SizedBox(height: 6),
          TvMenuItem(label: 'Extra', onSelect: () => _openDisc(a, pane: 2)),
        ]),
      ),
    ]);
  }

  Widget _stripRow(List<SavedAnime> list, int sel) {
    final news = list.fold<int>(0, (s, a) => s + a.newEpisodes);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(48, 0, 48, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('SUL LETTORE', style: tvDisplay(15, spacing: 2.5)),
          const SizedBox(width: 14),
          Text('${list.length} ${list.length == 1 ? 'disco' : 'dischi'}${news > 0 ? ' · $news episodi nuovi' : ''}', style: tvMono(12, color: TV.muted)),
        ]),
      ),
      SizedBox(
        height: 164,
        child: ExcludeFocus(
          child: ListView.separated(
            controller: _strip,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(48, 10, 48, 8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: _caseGap),
            itemBuilder: (_, k) {
              final a = list[k];
              final on = k == sel;
              return Align(
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: on ? const [BoxShadow(color: TV.accent, spreadRadius: 6), BoxShadow(color: TV.bg, spreadRadius: 3)] : const [],
                  ),
                  child: DvdCase(
                    anime: a,
                    width: on ? 100 : _caseW,
                    style: DvdStyle.bluray,
                    dim: a.listStatus == 'PAUSED',
                    badge: a.newEpisodes > 0 ? '+${a.newEpisodes}' : null,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }

  Widget _empty() {
    final hasOthers = AnimeStore.I.library.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 150, 48, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NESSUN DISCO SUL LETTORE', style: tvDisplay(44, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
          width: 760,
          child: Text(
            hasOthers
                ? 'Qui arrivano gli anime che stai guardando. Iniziane uno da «Prossimamente» oppure cercalo in «Cerca».'
                : 'La tua lista è vuota: sincronizza con Google Drive per avere gli anime e AniList del telefono, oppure cerca un titolo in «Cerca».',
            style: tvBody(17),
          ),
        ),
        const SizedBox(height: 26),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if (hasOthers) TvButton(label: 'Vai a Prossimamente', primary: true, autofocus: true, onSelect: () => widget.onGo(1)),
          TvButton(label: 'Cerca un anime', icon: Icons.search, primary: !hasOthers, autofocus: !hasOthers, onSelect: () => widget.onGo(3)),
          if (AniList.I.loggedIn)
            TvButton(
              label: 'Importa la lista AniList',
              icon: Icons.download,
              onSelect: () async {
                try {
                  final n = AnimeStore.I.importAniList(await AniList.I.myList(type: 'ANIME'));
                  if (mounted) setState(() => _msg = n == 0 ? 'Nessun anime nuovo nella lista AniList.' : 'Aggiunti $n anime da AniList.');
                } catch (e) {
                  if (mounted) setState(() => _msg = 'AniList non risponde: $e');
                }
              },
            ),
          if (DriveSync.I.enabled) TvButton(label: 'Sincronizza ora', icon: Icons.sync, onSelect: () => DriveSync.I.sync()) else TvButton(label: 'Collega Google Drive', icon: Icons.cloud_sync_outlined, onSelect: () => widget.onGo(4)),
        ]),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 18), child: Text(_msg!, style: tvBody(15, color: TV.peach))),
      ]),
    );
  }
}
