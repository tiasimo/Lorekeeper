import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../screens/book_extras.dart';
import '../screens/world_map.dart';
import '../services/library_store.dart';
import '../services/wiki.dart';
import '../theme.dart';

/// Pannello laterale della Home su tablet: obiettivo del giorno, settimana,
/// ultimi fatti della cronologia e scorciatoie per il libro in corso.
class TodayPanel extends StatelessWidget {
  const TodayPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = LibraryStore.I;
    final now = DateTime.now();
    final today = (s.secondsByDay[LibraryStore.dayKey(now)] ?? 0) + (s.mangaSecondsByDay[LibraryStore.dayKey(now)] ?? 0);
    final goal = s.app.goalMinutes * 60;
    final week = [
      for (var i = 6; i >= 0; i--)
        () {
          final d = now.subtract(Duration(days: i));
          final k = LibraryStore.dayKey(d);
          return (d, (s.secondsByDay[k] ?? 0) + (s.mangaSecondsByDay[k] ?? 0));
        }(),
    ];
    final maxWeek = week.map((e) => e.$2).fold<int>(1, math.max);
    final last = s.lastRead;
    const days = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];
    return Container(
      width: 300,
      decoration: BoxDecoration(color: LK.card, border: Border(left: BorderSide(color: LK.border))),
      child: SafeArea(
        left: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          children: [
            Text('OBIETTIVO DI OGGI', style: LK.label(10)),
            const SizedBox(height: 12),
            Row(children: [
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: goal == 0 ? 0 : (today / goal).clamp(0.0, 1.0),
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                      backgroundColor: LK.line,
                      color: LK.accent,
                    ),
                  ),
                  if (today >= goal && goal > 0) Icon(Icons.check, color: LK.accent),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '${today ~/ 60}', style: LK.display(28)),
                    TextSpan(text: ' / ${s.app.goalMinutes} min', style: LK.body(15, color: LK.muted)),
                  ])),
                  Text(s.streak > 1 ? 'Serie: ${s.streak} giorni di fila' : 'Leggi oggi per iniziare una serie', style: LK.body(13, color: LK.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 26),
            Text('QUESTA SETTIMANA', style: LK.label(10)),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (d, sec) in week)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          height: math.max(6, 72 * sec / maxWeek),
                          decoration: BoxDecoration(
                            color: sec == 0 ? LK.line : (d.day == now.day ? LK.accent : LK.accentSoft),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(days[d.weekday - 1], style: LK.label(9.5, spacing: 0.2)),
                      ]),
                    ),
                  ),
              ]),
            ),
            if (last != null) ...[
              const SizedBox(height: 26),
              Text('DALLA CRONOLOGIA', style: LK.label(10)),
              const SizedBox(height: 10),
              _RecentEvents(book: last),
              const SizedBox(height: 18),
              _tool(context, Icons.question_answer_outlined, 'Chiedi al libro', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AskBookScreen(book: last)))),
              _tool(context, Icons.timeline, 'Cronologia', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimelineScreen(book: last)))),
              _tool(context, Icons.map_outlined, 'Mappa del mondo', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorldMapScreen(book: last)))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tool(BuildContext context, IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size.fromHeight(48),
            backgroundColor: LK.paper,
            side: BorderSide(color: LK.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onTap,
          icon: Icon(icon, color: LK.accent, size: 18),
          label: Text(label, style: LK.body(14)),
        ),
      );
}

class _RecentEvents extends StatelessWidget {
  final Book book;
  const _RecentEvents({required this.book});

  @override
  Widget build(BuildContext context) => FutureBuilder<Wiki>(
        future: WikiStore.I.forBook(book),
        builder: (context, snap) {
          final w = snap.data;
          if (w == null) return const SizedBox(height: 20);
          final limit = WikiStore.I.limitFor(book);
          final ev = w.events.where((e) => e.pos <= limit).toList()..sort((a, b) => b.pos.compareTo(a.pos));
          if (ev.isEmpty) {
            return Text('Gli eventi compaiono man mano che Gemini analizza i capitoli.', style: LK.body(13, color: LK.muted, style: FontStyle.italic));
          }
          return Container(
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: LK.border, width: 2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in ev.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e.major ? '★ ' : ''}${e.text}', style: LK.body(13.5, height: 1.4)),
                    Text('Cap. ${e.chapter + 1}', style: LK.body(12, color: LK.muted)),
                  ]),
                ),
            ]),
          );
        },
      );
}
