import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/annotations.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _months = ['Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno', 'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'];
const _short = ['G', 'F', 'M', 'A', 'M', 'G', 'L', 'A', 'S', 'O', 'N', 'D'];

/// Calendario e statistiche di lettura per mese e per anno.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final store = LibraryStore.I;
  int _mode = 0; // 0 mese, 1 anno
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _year = DateTime.now().year;

  int _secs(DateTime d) => store.secondsByDay[LibraryStore.dayKey(d)] ?? 0;
  int _chs(DateTime d) => store.chaptersByDay[LibraryStore.dayKey(d)] ?? 0;

  String _fmt(int secs) {
    final m = secs ~/ 60;
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }

  List<(Book, DateTime)> _finished(bool Function(DateTime) inRange) {
    final out = <(Book, DateTime)>[];
    store.finishedBooks.forEach((id, ms) {
      final b = store.byId(id);
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (b != null && inRange(d)) out.add((b, d));
    });
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  Widget _stat(String v, String l) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: LK.line)),
          child: Column(children: [
            Text(v, textAlign: TextAlign.center, style: LK.display(19, color: LK.accentDark)),
            const SizedBox(height: 2),
            Text(l, textAlign: TextAlign.center, style: LK.label(8.5, spacing: 0.8)),
          ]),
        ),
      );

  Color _heat(int secs, int goal) {
    if (secs <= 0) return LK.line;
    final f = (secs / (goal * 60)).clamp(0.15, 1.0);
    return Color.lerp(LK.accentSoft, LK.accent, f)!;
  }

  // ---------------- mese ----------------
  List<Widget> _monthView() {
    final goal = math.max(1, store.app.goalMinutes);
    final first = _month;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final lead = (first.weekday + 6) % 7; // lunedì = 0
    var total = 0, read = 0, chs = 0, best = 0;
    for (var d = 1; d <= days; d++) {
      final s = _secs(DateTime(first.year, first.month, d));
      total += s;
      if (s > 0) read++;
      if (s > best) best = s;
      chs += _chs(DateTime(first.year, first.month, d));
    }
    final done = _finished((d) => d.year == first.year && d.month == first.month);
    final today = DateTime.now();
    return [
      Row(children: [
        IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: Icon(Icons.chevron_left, color: LK.ink)),
        Expanded(child: Text('${_months[first.month - 1]} ${first.year}', textAlign: TextAlign.center, style: LK.display(20))),
        IconButton(
          onPressed: DateTime(_month.year, _month.month + 1).isAfter(today) ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
          icon: Icon(Icons.chevron_right, color: LK.ink),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [for (final d in const ['L', 'M', 'M', 'G', 'V', 'S', 'D']) Expanded(child: Center(child: Text(d, style: LK.label(10, spacing: 0))))]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (var i = 0; i < lead; i++) const SizedBox.shrink(),
          for (var d = 1; d <= days; d++)
            Builder(builder: (context) {
              final day = DateTime(first.year, first.month, d);
              final s = _secs(day);
              final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
              final met = s >= goal * 60;
              return Tooltip(
                message: s > 0 ? '${_fmt(s)}${_chs(day) > 0 ? ' · ${_chs(day)} cap.' : ''}' : 'Nessuna lettura',
                child: Container(
                  decoration: BoxDecoration(
                    color: _heat(s, goal),
                    borderRadius: BorderRadius.circular(8),
                    border: isToday ? Border.all(color: LK.ink, width: 1.6) : null,
                  ),
                  child: Stack(children: [
                    Center(child: Text('$d', style: LK.body(13, color: s > 0 ? LK.onAccent : LK.muted))),
                    if (met) Positioned(right: 3, top: 1, child: Text('✦', style: TextStyle(fontSize: 8, color: LK.onAccent))),
                  ]),
                ),
              );
            }),
        ],
      ),
      const SizedBox(height: 16),
      Row(children: [
        _stat(_fmt(total), 'TEMPO'),
        const SizedBox(width: 8),
        _stat('$read', 'GIORNI'),
        const SizedBox(width: 8),
        _stat('$chs', 'CAPITOLI'),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _stat(read == 0 ? '—' : _fmt(total ~/ read), 'MEDIA AL GIORNO'),
        const SizedBox(width: 8),
        _stat(best == 0 ? '—' : _fmt(best), 'GIORNO MIGLIORE'),
        const SizedBox(width: 8),
        _stat('${done.length}', 'LIBRI FINITI'),
      ]),
      ..._finishedList(done),
    ];
  }

  // ---------------- anno ----------------
  List<Widget> _yearView() {
    final goal = math.max(1, store.app.goalMinutes);
    final perMonth = List<int>.filled(12, 0);
    var total = 0, read = 0, chs = 0;
    for (var d = DateTime(_year); d.year == _year; d = d.add(const Duration(days: 1))) {
      final s = _secs(d);
      perMonth[d.month - 1] += s;
      total += s;
      if (s > 0) read++;
      chs += _chs(d);
    }
    final maxM = math.max(1, perMonth.reduce(math.max));
    final done = _finished((d) => d.year == _year);
    final now = DateTime.now();
    // mappa di calore: 53 settimane × 7 giorni
    final start = DateTime(_year).subtract(Duration(days: (DateTime(_year).weekday + 6) % 7));
    return [
      Row(children: [
        IconButton(onPressed: () => setState(() => _year--), icon: Icon(Icons.chevron_left, color: LK.ink)),
        Expanded(child: Text('$_year', textAlign: TextAlign.center, style: LK.display(22))),
        IconButton(onPressed: _year >= now.year ? null : () => setState(() => _year++), icon: Icon(Icons.chevron_right, color: LK.ink)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _stat(_fmt(total), 'TEMPO'),
        const SizedBox(width: 8),
        _stat('$read', 'GIORNI'),
        const SizedBox(width: 8),
        _stat('$chs', 'CAPITOLI'),
        const SizedBox(width: 8),
        _stat('${done.length}', 'LIBRI'),
      ]),
      const SizedBox(height: 18),
      const SectionLabel('Mese per mese'),
      SizedBox(
        height: 150,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var m = 0; m < 12; m++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _mode = 0;
                  _month = DateTime(_year, m + 1);
                }),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (perMonth[m] > 0) Text('${perMonth[m] ~/ 3600}h', style: LK.label(8, spacing: 0)),
                  const SizedBox(height: 2),
                  Container(
                    height: 110 * perMonth[m] / maxM + 2,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(color: perMonth[m] > 0 ? LK.accent : LK.line, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 4),
                  Text(_short[m], style: LK.label(9, spacing: 0)),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 18),
      const SectionLabel('Ogni giorno dell\'anno'),
      LayoutBuilder(builder: (context, c) {
        final cell = (c.maxWidth - 52 * 2) / 53;
        return SizedBox(
          height: cell * 7 + 12,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var w = 0; w < 53; w++)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Column(children: [
                  for (var d = 0; d < 7; d++)
                    Builder(builder: (context) {
                      final day = start.add(Duration(days: w * 7 + d));
                      final inYear = day.year == _year;
                      return Container(
                        width: cell,
                        height: cell,
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(color: inYear ? _heat(_secs(day), goal) : Colors.transparent, borderRadius: BorderRadius.circular(1.5)),
                      );
                    }),
                ]),
              ),
          ]),
        );
      }),
      ..._finishedList(done),
    ];
  }

  List<Widget> _finishedList(List<(Book, DateTime)> done) {
    if (done.isEmpty) return const [];
    return [
      const SizedBox(height: 18),
      const SectionLabel('Libri finiti'),
      for (final (b, d) in done)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            BookCover(book: b, width: 40, height: 58),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.title, style: LK.display(15)),
                Text('${d.day} ${_months[d.month - 1].toLowerCase()} ${d.year}', style: LK.body(12.5, color: LK.muted)),
              ]),
            ),
            Builder(builder: (context) {
              final r = Annotations.I.of(b.id).rating;
              if (r == 0) return const SizedBox.shrink();
              return Row(children: [for (var i = 0; i < 5; i++) Icon(i < r ? Icons.star : Icons.star_border, size: 14, color: LK.gold)]);
            }),
          ]),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TabletSafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            const Align(alignment: Alignment.centerLeft, child: BackLink(trail: 'Libreria')),
            Text('Il tuo diario', style: LK.display(28)),
            const SizedBox(height: 4),
            Text('Serie attuale: ${store.streak} ${store.streak == 1 ? 'giorno' : 'giorni'} di fila · ${store.chaptersRead} capitoli in tutto', style: LK.body(13, color: LK.muted)),
            const SizedBox(height: 14),
            Center(child: Segmented(labels: const ['Mese', 'Anno'], selected: _mode, onChanged: (i) => setState(() => _mode = i))),
            const SizedBox(height: 14),
            ...(_mode == 0 ? _monthView() : _yearView()),
          ],
        ),
      ),
    );
  }
}
