import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/anime/anime_player.dart';
import '../screens/manga/anilist_ui.dart';
import '../services/anilist.dart';
import '../services/anime_store.dart';
import '../services/manga_store.dart';
import '../theme.dart';
import 'tv_widgets.dart';

/// Il menu del disco: a sinistra la custodia e le voci (riproduci, selezione episodi,
/// sposta in…, extra), a destra il pannello della voce scelta.
class TvAnimeDetail extends StatefulWidget {
  final SavedAnime anime;
  final int pane; // 0 episodi, 1 sposta in…, 2 extra
  const TvAnimeDetail({super.key, required this.anime, this.pane = 0});
  @override
  State<TvAnimeDetail> createState() => _TvAnimeDetailState();
}

class _TvAnimeDetailState extends State<TvAnimeDetail> {
  final store = AnimeStore.I;
  late SavedAnime a = widget.anime;
  late int _pane = widget.pane;
  bool _loading = false, _confirmRemove = false, _jumped = false;
  String? _error, _msg;
  List<AlMedia>? _alResults;
  final _paneNode = FocusNode(debugLabel: 'pannello', skipTraversal: true, canRequestFocus: false);
  final _menuNodes = List.generate(3, (i) => FocusNode(debugLabel: 'voce$i'));
  final _grid = ScrollController();

  static const _tileH = 110.0, _rowH = 110.0 + 34 + 18;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    store.ensureColor(a);
    _refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    _paneNode.dispose();
    for (final n in _menuNodes) {
      n.dispose();
    }
    _grid.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (a.pending) return;
    await store.ensureBridge();
    final s = store.sourceFor(a);
    if (s == null) {
      if (mounted) setState(() => _error = 'La fonte «${a.sourceName}» non è installata su questa TV: installala da Impostazioni › Estensioni, oppure cambia fonte.');
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await store.refresh(s, a);
    } catch (e) {
      _error = 'La fonte non risponde: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chooseSource() async {
    await store.ensureBridge();
    if (!mounted) return;
    final picked = await showModalBottomSheet<(Source, DMedia)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (_) => SourceSearchSheet(titles: [a.title], title: 'Dove vuoi guardarlo?', anime: true),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dest = await store.attachSource(a, picked.$1, picked.$2);
      if (mounted) setState(() => a = dest);
    } catch (e) {
      _error = 'Non riesco a usare questa fonte: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _play(MChapter e) {
    if (a.pending) {
      _chooseSource();
      return;
    }
    final s = store.sourceFor(a);
    if (s == null) {
      setState(() => _error = 'La fonte «${a.sourceName}» non è installata su questa TV: installala da Impostazioni › Estensioni, oppure cambia fonte.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimePlayer(anime: a, source: s, episode: e))).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _setStatus(String status) async {
    await store.setStatus(a, status);
    if (!mounted) return;
    setState(() {
      _confirmRemove = false;
      _msg = store.syncError != null && a.anilistId != null ? 'Spostato qui sulla TV, ma AniList non ha risposto: ${store.syncError}' : 'Fatto: ora è in «${tvStatusNames[status]}».';
    });
  }

  Future<void> _linkSearch() async {
    setState(() => _msg = 'Cerco su AniList…');
    try {
      final r = await AniList.I.search(a.title, type: 'ANIME');
      if (mounted) {
        setState(() {
          _alResults = r.take(5).toList();
          _msg = r.isEmpty ? 'AniList non ha trovato niente con questo titolo.' : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _msg = 'AniList non risponde: $e');
    }
  }

  Future<void> _link(AlMedia m) async {
    final wanted = a.localStatus;
    try {
      await store.linkAniList(a, m);
      // se su AniList non era in lista, ci va con la sezione scelta qui
      if (a.alStatus == null && wanted != null) await store.setStatus(a, wanted);
      if (mounted) {
        setState(() {
          _alResults = null;
          _msg = 'Collegato ad AniList.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _msg = 'Non riesco a collegarlo: $e');
    }
  }

  void _enterPane() {
    final first = _paneNode.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
    first?.requestFocus();
  }

  /// ◀ dal pannello: se a sinistra non c'è altro nel pannello, torna alla sua voce di menu
  /// (non a quella che capita alla stessa altezza).
  KeyEventResult _paneKey(FocusNode node, KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final cur = FocusManager.instance.primaryFocus;
    if (cur == null) return KeyEventResult.ignored;
    final r = cur.rect;
    final hasLeft = _paneNode.traversalDescendants.any((n) => n != cur && n.rect.right <= r.left + 1 && n.rect.bottom > r.top && n.rect.top < r.bottom);
    if (hasLeft) return KeyEventResult.ignored;
    if (e is KeyDownEvent) _menuNodes[_pane.clamp(0, 2)].requestFocus();
    return KeyEventResult.handled;
  }

  String _two(int v) => v.toString().padLeft(2, '0');
  String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  String _score(double s) => '${s % 1 == 0 ? s.toInt() : s}';

  @override
  Widget build(BuildContext context) {
    final next = a.firstUnwatched;
    final air = a.nextAir;
    final started = a.watchedUpTo > 0 || a.lastWatchedAt != null;
    final total = a.alTotal ?? a.total;
    final pos = next == null ? 0 : (a.positions[next.url] ?? 0);
    final String playLabel;
    if (a.pending) {
      playLabel = 'Scegli la fonte';
    } else if (next != null) {
      playLabel = '${started ? 'Riprendi' : 'Inizia'} ep. ${_two(a.numberOf(next))}';
    } else if (a.ordered.isNotEmpty) {
      playLabel = 'Riguarda dal primo';
    } else {
      playLabel = _loading ? 'Carico gli episodi…' : 'Nessun episodio';
    }
    return Scaffold(
      backgroundColor: TV.bg,
      body: TvCanvas(
        child: Stack(children: [
          // un'ombra del colore della copertina dietro al menu
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color.lerp(a.caseColor == null ? TV.panelHi : Color(a.caseColor!), TV.bg, 0.6)!, TV.bg]),
              ),
            ),
          ),
          Positioned(
            left: 48,
            top: 36,
            width: 320,
            bottom: 30,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('‹ INDIETRO', style: tvMono(12)),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                DvdCase(anime: a, width: 104, style: dvdStyleFor(a), dim: a.section == 3),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.title.toUpperCase(), maxLines: 3, overflow: TextOverflow.ellipsis, style: tvDisplay(a.title.length > 28 ? 21 : 27, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text([if (total > 0) '$total episodi', if (a.alScore > 0) '★ ${_score(a.alScore)}'].join(' · '), style: tvBody(13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFF8C9198))),
                      child: Text(a.inLibrary ? (tvStatusNames[a.listStatus] ?? (a.section == 1 ? 'Prossimamente' : 'Sul lettore')).toUpperCase() : 'NON IN LISTA', style: tvMono(11, color: const Color(0xFFD6D9DD))),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 26),
              TvMenuItem(
                label: playLabel,
                trailing: pos > 0 ? _clock(pos) : null,
                autofocus: widget.pane == 0,
                onSelect: () {
                  if (a.pending) {
                    _chooseSource();
                  } else if (next != null) {
                    _play(next);
                  } else if (a.ordered.isNotEmpty) {
                    _play(a.ordered.first);
                  }
                },
              ),
              const SizedBox(height: 4),
              TvMenuItem(focusNode: _menuNodes[0], label: 'Selezione episodi', active: _pane == 0, onFocus: (f) => _showPane(f, 0), onSelect: _enterPane),
              const SizedBox(height: 4),
              TvMenuItem(focusNode: _menuNodes[1], label: a.inLibrary ? 'Sposta in…' : 'Aggiungi a…', active: _pane == 1, autofocus: widget.pane == 1, onFocus: (f) => _showPane(f, 1), onSelect: _enterPane),
              const SizedBox(height: 4),
              TvMenuItem(focusNode: _menuNodes[2], label: 'Extra', active: _pane == 2, autofocus: widget.pane == 2, onFocus: (f) => _showPane(f, 2), onSelect: _enterPane),
              const SizedBox(height: 4),
              TvMenuItem(label: a.pending ? 'Scegli la fonte' : 'Cambia fonte', onSelect: _chooseSource),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  [
                    'FONTE  ${a.pending ? 'da scegliere' : a.sourceName}',
                    if (air != null) 'EP. ${_two(a.nextAirEp ?? a.watchedUpTo + 1)} ESCE ${tvWhen(air).toUpperCase()}',
                    if (a.mediaStatus == 'RELEASING' && air == null) 'IN ONDA',
                  ].join('\n'),
                  style: tvMono(12, color: TV.muted).copyWith(height: 1.7),
                ),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 0, 0), child: Text(_error!, maxLines: 5, overflow: TextOverflow.ellipsis, style: tvBody(13, color: TV.peach))),
            ]),
          ),
          Positioned(
            left: 404,
            right: 48,
            top: 36,
            bottom: 40,
            child: Focus(
              focusNode: _paneNode,
              skipTraversal: true,
              canRequestFocus: false,
              onKeyEvent: _paneKey,
              child: switch (_pane) { 1 => _listPane(), 2 => _extraPane(), _ => _episodesPane() },
            ),
          ),
          Positioned(
            right: 48,
            bottom: 12,
            child: TvHints(switch (_pane) {
              0 => const ['◀▶▲▼ SCEGLI', 'OK RIPRODUCI', 'OK TENUTO: SEGNA VISTO', 'INDIETRO: ESCI'],
              _ => const ['▲▼ SCEGLI', 'OK CONFERMA', 'INDIETRO: ESCI'],
            }),
          ),
        ]),
      ),
    );
  }

  void _showPane(bool focused, int pane) {
    if (focused && _pane != pane) {
      setState(() {
        _pane = pane;
        _confirmRemove = false;
        _msg = null;
      });
    }
  }

  Widget _header(String title, String? sub) => Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(title, style: tvDisplay(26, spacing: 3)),
        const SizedBox(width: 14),
        if (sub != null) Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvMono(13, color: TV.muted))),
        if (_loading) ...[
          const SizedBox(width: 14),
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: TV.accent)),
        ],
      ]);

  // ---------------- selezione episodi ----------------
  Widget _episodesPane() {
    final eps = a.ordered;
    final seen = eps.where(a.isWatched).length;
    final next = a.firstUnwatched;
    // la prima volta la griglia parte dalla riga del prossimo episodio
    if (!_jumped && eps.isNotEmpty) {
      _jumped = true;
      final idx = next == null ? 0 : eps.indexWhere((e) => e.url == next.url);
      if (idx >= 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_grid.hasClients) _grid.jumpTo(((idx ~/ 4 - 1) * _rowH).clamp(0.0, _grid.position.maxScrollExtent));
        });
      }
    }
    final tint = a.caseColor == null ? TV.panel : Color.lerp(Color(a.caseColor!), TV.bg, 0.55)!;
    // senza AniList non so se la serie è finita: lo chiedo quando hai visto tutto
    final askDone = a.anilistId == null && a.section == 0 && eps.isNotEmpty && next == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('SELEZIONE EPISODI', eps.isEmpty ? null : '${_two(1)}–${_two(eps.length)} · visti $seen'),
      if (askDone)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
          child: Row(children: [
            Expanded(child: Text('Hai visto tutti gli episodi usciti. Se la serie è finita puoi metterla in Collezione; se è ancora in onda resta sul lettore.', style: tvBody(14))),
            const SizedBox(width: 16),
            TvButton(label: 'Sposta in Collezione', onSelect: () => _setStatus('COMPLETED')),
          ]),
        ),
      if (_msg != null && _pane == 0) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: tvBody(14, color: TV.peach))),
      const SizedBox(height: 12),
      Expanded(
        child: eps.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Text(
                  a.pending
                      ? 'Questo anime arriva dalla tua lista AniList: scegli la fonte da cui guardarlo con «Scegli la fonte».'
                      : (_loading ? 'Carico gli episodi dalla fonte…' : (_error ?? 'La fonte non ha episodi per questo titolo.')),
                  style: tvBody(17),
                ),
              )
            : GridView.builder(
                controller: _grid,
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: _tileH + 34, crossAxisSpacing: 16, mainAxisSpacing: 18),
                itemCount: eps.length,
                itemBuilder: (context, i) {
                  final e = eps[i];
                  final done = a.isWatched(e);
                  final p = a.positions[e.url] ?? 0;
                  final isNext = next != null && e.url == next.url;
                  return TvFocus(
                    onSelect: () => _play(e),
                    onLongSelect: () {
                      store.markWatched(a, e, watched: !done);
                      setState(() => _msg = done ? 'Episodio ${a.numberOf(e)} segnato come da vedere.' : 'Episodio ${a.numberOf(e)} segnato come visto.');
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        height: _tileH,
                        color: done ? TV.panel : tint,
                        child: Stack(children: [
                          Positioned(left: 10, top: 4, child: Text(_two(a.numberOf(e)), style: tvDisplay(36, color: done ? TV.muted : Colors.white, weight: FontWeight.w700))),
                          if (done) Positioned(right: 8, top: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: TV.bg, child: Text('VISTO', style: tvMono(10, color: const Color(0xFFD6D9DD), weight: FontWeight.w700)))),
                          if (isNext && !done) Positioned(right: 8, top: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: TV.accent, child: Text(p > 0 ? _clock(p) : 'PROSSIMO', style: tvMono(10, color: TV.bg, weight: FontWeight.w700)))),
                          if (p > 0 && !done) Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 4, color: const Color(0xB30A0A0B), alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: (p / 1440).clamp(0.05, 0.95), child: Container(color: TV.accent)))),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                        child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvBody(13, color: done ? TV.muted : TV.ink, weight: FontWeight.w600)),
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  // ---------------- aggiungi a… / sposta in… ----------------
  Widget _listPane() {
    final linked = a.anilistId != null && AniList.I.loggedIn;
    final cur = a.inLibrary ? a.section : -1;
    final paused = a.listStatus == 'PAUSED';
    Widget choice(String name, String sub, String status, bool here, {bool autofocus = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TvFocus(
            autofocus: autofocus,
            onSelect: () => _setStatus(status),
            builder: (context, focused) => Container(
              height: 84,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              color: focused ? TV.accent : TV.panel,
              child: Row(children: [
                SizedBox(width: 34, child: focused ? const Icon(Icons.play_arrow, color: TV.bg, size: 22) : null),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: tvDisplay(24, color: focused ? TV.bg : TV.ink, weight: focused ? FontWeight.w600 : FontWeight.w500, spacing: 2)),
                    const SizedBox(height: 4),
                    Text(sub, style: tvBody(14, color: focused ? TV.bg : TV.soft, weight: focused ? FontWeight.w600 : FontWeight.w500)),
                  ]),
                ),
                if (here) Text('È QUI ADESSO', style: tvMono(11, color: focused ? TV.bg : TV.peach, weight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(a.inLibrary ? 'SPOSTA IN…' : 'AGGIUNGI A…', linked ? 'si aggiorna anche su AniList' : (a.anilistId == null ? 'solo su questa lista: non è collegato ad AniList' : null)),
      const SizedBox(height: 20),
      SizedBox(
        width: 640,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          choice('SUL LETTORE', 'Lo sto guardando${linked ? ' · AniList: in corso' : ''}', 'CURRENT', cur == 0 && !paused),
          choice('PROSSIMAMENTE', 'Lo guarderò più avanti${linked ? ' · AniList: da vedere' : ''}', 'PLANNING', cur == 1),
          choice('COLLEZIONE', 'L\'ho già visto tutto${linked ? ' · AniList: completato' : ''}', 'COMPLETED', cur == 2),
          if (a.inLibrary) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 12, runSpacing: 12, children: [
              if (!paused) TvButton(label: 'Metti in pausa', onSelect: () => _setStatus('PAUSED')),
              if (cur != 3) TvButton(label: 'Abbandona', onSelect: () => _setStatus('DROPPED')),
              TvButton(
                label: _confirmRemove ? (linked ? 'Conferma: togli anche da AniList' : 'Conferma: togli dalla lista') : 'Togli dalla lista',
                onSelect: () async {
                  if (!_confirmRemove) {
                    setState(() => _confirmRemove = true);
                    return;
                  }
                  await store.removeFromList(a);
                  if (mounted) Navigator.of(context).maybePop();
                },
              ),
            ]),
          ],
          if (_confirmRemove)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(linked ? 'Toglierlo cancella anche progressi e voto su AniList. Premi di nuovo per confermare.' : 'Premi di nuovo per confermare.', style: tvBody(14, color: TV.peach)),
            ),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_msg!, style: tvBody(14, color: TV.peach))),
        ]),
      ),
    ]);
  }

  // ---------------- extra ----------------
  Widget _extraPane() {
    final desc = (a.description ?? '').replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    final total = a.alTotal ?? a.total;
    final canLink = AniList.I.loggedIn && a.anilistId == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('EXTRA', null),
      const SizedBox(height: 16),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(8), children: [
          if (a.genres.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(a.genres.take(6).join(' · ').toUpperCase(), style: tvLabel(13, color: TV.peach))),
          Text(desc.isEmpty ? 'La fonte non ha una trama per questo titolo.' : desc, maxLines: 9, overflow: TextOverflow.ellipsis, style: tvBody(16)),
          const SizedBox(height: 18),
          Text(
            [
              'FONTE     ${a.pending ? 'da scegliere' : a.sourceName}',
              'EPISODI   ${total > 0 ? total : '—'}${a.watchedUpTo > 0 ? ' · visti ${a.watchedUpTo}' : ''}',
              'ANILIST   ${a.anilistId == null ? 'non collegato' : '${tvStatusNames[a.alStatus] ?? 'non in lista'}${a.alScore > 0 ? ' · voto ★ ${_score(a.alScore)}' : ''}'}',
              if (a.mediaStatus != null) 'SERIE     ${const {'FINISHED': 'conclusa', 'RELEASING': 'in onda', 'NOT_YET_RELEASED': 'non ancora uscita', 'CANCELLED': 'cancellata', 'HIATUS': 'in pausa'}[a.mediaStatus] ?? a.mediaStatus}',
            ].join('\n'),
            style: tvMono(13, color: TV.soft).copyWith(height: 1.8),
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: [
            if (!a.pending) TvButton(label: 'Aggiorna gli episodi', icon: Icons.refresh, autofocus: true, onSelect: _refresh),
            if (canLink) TvButton(label: 'Collega ad AniList', icon: Icons.link, onSelect: _linkSearch),
          ]),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_msg!, style: tvBody(14, color: TV.peach))),
          if (_alResults != null)
            for (final m in _alResults!)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TvMenuItem(
                  label: m.title,
                  trailing: [if (m.year != null) '${m.year}', if (m.format != null) m.format!, if (m.episodes != null) '${m.episodes} ep.'].join(' · '),
                  height: 46,
                  size: 17,
                  onSelect: () => _link(m),
                ),
              ),
        ]),
      ),
    ]);
  }
}
