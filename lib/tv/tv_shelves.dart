import 'package:flutter/material.dart';

import '../services/anime_store.dart';
import 'tv_anime_detail.dart';
import 'tv_widgets.dart';

/// Una parete di custodie su ripiani: «Prossimamente» (kind 1, custodie con il bordo bianco)
/// e «Collezione» (kind 2, steelbook: completati e, in fondo, abbandonati).
class TvShelves extends StatefulWidget {
  final int kind;
  const TvShelves({super.key, required this.kind});
  @override
  State<TvShelves> createState() => _TvShelvesState();
}

class _TvShelvesState extends State<TvShelves> {
  String? _focusKey;

  static const _perRow = 8;

  void _open(SavedAnime a) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvAnimeDetail(anime: a))).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AnimeStore.I,
      builder: (context, _) {
        final lib = AnimeStore.I.library;
        final plan = widget.kind == 1;
        final groups = plan
            ? [('DA VEDERE', (lib.where((a) => a.section == 1).toList()..sort((x, y) => y.addedAt.compareTo(x.addedAt))))]
            : [
                ('COMPLETATI', lib.where((a) => a.section == 2).toList()),
                ('ABBANDONATI', lib.where((a) => a.section == 3).toList()),
              ];
        final all = [for (final g in groups) ...g.$2];
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(48, 80, 48, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plan ? 'NIENTE IN PROGRAMMA' : 'LA COLLEZIONE È VUOTA', style: tvDisplay(44, weight: FontWeight.w700)),
              const SizedBox(height: 12),
              SizedBox(
                width: 760,
                child: Text(
                  plan
                      ? 'Qui stanno gli anime che vuoi guardare più avanti: aggiungili da «Cerca» con «Aggiungi a…», oppure mettili «da vedere» su AniList.'
                      : 'Qui arrivano gli anime che hai finito: ci passano da soli quando la serie è conclusa e hai visto l\'ultimo episodio.',
                  style: tvBody(17),
                ),
              ),
            ]),
          );
        }
        // righe della parete: un'intestazione per gruppo e poi i ripiani da 8 custodie
        final rows = <Object>[];
        for (final (name, list) in groups) {
          if (list.isEmpty) continue;
          rows.add('$name|${list.length} ${list.length == 1 ? 'disco' : 'dischi'}');
          for (var i = 0; i < list.length; i += _perRow) {
            rows.add(list.sublist(i, (i + _perRow).clamp(0, list.length)));
          }
        }
        final sel = all.where((a) => a.key == _focusKey).firstOrNull ?? all.first;
        return Column(children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              itemCount: rows.length,
              itemBuilder: (context, r) {
                final row = rows[r];
                if (row is String) {
                  final parts = row.split('|');
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Text(parts[0], style: tvDisplay(15, spacing: 2.5)),
                      const SizedBox(width: 14),
                      Text(parts[1], style: tvMono(12, color: TV.muted)),
                    ]),
                  );
                }
                return _shelf(row as List<SavedAnime>, plan);
              },
            ),
          ),
          _infoBar(sel, plan),
          const SizedBox(height: 30),
        ]);
      },
    );
  }

  Widget _shelf(List<SavedAnime> list, bool plan) {
    return Column(children: [
      SizedBox(
        height: 206,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(right: 22, bottom: 6),
                child: TvFocus(
                  scale: 1.1,
                  radius: BorderRadius.circular(plan ? 4 : 7),
                  onFocus: (f) {
                    if (f && _focusKey != a.key) setState(() => _focusKey = a.key);
                  },
                  onSelect: () => _open(a),
                  child: DvdCase(
                    anime: a,
                    width: 122,
                    style: plan ? DvdStyle.white : DvdStyle.steel,
                    dim: a.section == 3,
                    badgeLight: true,
                    badge: !plan && a.alScore > 0 ? '★ ${a.alScore % 1 == 0 ? a.alScore.toInt() : a.alScore}' : null,
                  ),
                ),
              ),
          ]),
        ),
      ),
      // il ripiano: un profilo di metallo con il suo riflesso
      Container(
        height: 5,
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5A5E66), Color(0xFF2A2C31)])),
      ),
      Container(
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x12FFFFFF), Color(0x00FFFFFF)])),
      ),
    ]);
  }

  Widget _infoBar(SavedAnime a, bool plan) {
    final total = a.alTotal ?? a.total;
    final air = a.nextAir;
    final sub = [
      if (total > 0) '$total episodi',
      if (a.genres.isNotEmpty) a.genres.take(2).join(', '),
      if (plan && air != null) 'in onda: ep. ${a.nextAirEp ?? ''} ${tvWhen(air)}',
      if (plan) 'ancora da iniziare',
      if (!plan && a.section == 3) 'abbandonato all\'episodio ${a.watchedUpTo}',
      if (!plan && a.section == 2 && a.alScore > 0) 'il tuo voto ★ ${a.alScore % 1 == 0 ? a.alScore.toInt() : a.alScore}',
      a.pending ? 'fonte da scegliere' : a.sourceName,
    ].join(' · ');
    return Container(
      height: 76,
      margin: const EdgeInsets.symmetric(horizontal: 48),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      color: TV.panel,
      child: Row(children: [
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: tvDisplay(26, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: tvBody(13)),
          ]),
        ),
        const SizedBox(width: 20),
        const TvHints(['◀▶▲▼ SCEGLI', 'OK MENU DEL DISCO']),
      ]),
    );
  }
}
