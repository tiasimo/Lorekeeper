import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../services/manga_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _months = ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'];
const _weekdays = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];

/// Riepilogo di un anno di letture.
class YearRecap {
  final int year;
  int novelSeconds = 0, mangaSeconds = 0, novelChapters = 0, mangaChapters = 0, days = 0, bestStreak = 0;
  int? bestMonth, bestWeekday;
  final List<Book> finished = [];
  final List<(SavedManga, int)> topManga = [];
  String? topAuthor;

  YearRecap(this.year) {
    final s = LibraryStore.I;
    final perMonth = List.filled(12, 0), perWeekday = List.filled(7, 0);
    final active = <DateTime>{};
    void scan(Map<String, int> m, void Function(int v) add, {bool time = false}) {
      m.forEach((k, v) {
        final parts = k.split('-');
        if (parts.length != 3 || int.tryParse(parts[0]) != year) return;
        add(v);
        if (time && v > 0) {
          final d = DateTime(year, int.parse(parts[1]), int.parse(parts[2]));
          active.add(d);
          perMonth[d.month - 1] += v;
          perWeekday[d.weekday - 1] += v;
        }
      });
    }

    scan(s.secondsByDay, (v) => novelSeconds += v, time: true);
    scan(s.mangaSecondsByDay, (v) => mangaSeconds += v, time: true);
    scan(s.chaptersByDay, (v) => novelChapters += v);
    scan(s.mangaChaptersByDay, (v) => mangaChapters += v);
    days = active.length;
    final sorted = active.toList()..sort();
    var run = 0;
    for (var i = 0; i < sorted.length; i++) {
      run = i > 0 && sorted[i].difference(sorted[i - 1]).inHours <= 25 ? run + 1 : 1;
      bestStreak = math.max(bestStreak, run);
    }
    int? argmax(List<int> l) {
      var best = -1, at = -1;
      for (var i = 0; i < l.length; i++) {
        if (l[i] > best) (best, at) = (l[i], i);
      }
      return best > 0 ? at : null;
    }

    bestMonth = argmax(perMonth);
    bestWeekday = argmax(perWeekday);
    s.finishedBooks.forEach((id, ms) {
      final b = s.byId(id);
      if (b != null && DateTime.fromMillisecondsSinceEpoch(ms).year == year) finished.add(b);
    });
    finished.sort((a, c) => s.finishedBooks[a.id]!.compareTo(s.finishedBooks[c.id]!));
    final authors = <String, int>{};
    for (final b in finished) {
      if (b.author.trim().isNotEmpty) authors[b.author] = (authors[b.author] ?? 0) + 1;
    }
    if (authors.isNotEmpty) topAuthor = (authors.entries.toList()..sort((a, c) => c.value.compareTo(a.value))).first.key;
    final perManga = <String, int>{};
    for (final e in MangaStore.I.history.where((e) => e.at.year == year)) {
      perManga[e.mangaKey] = (perManga[e.mangaKey] ?? 0) + 1;
    }
    for (final e in (perManga.entries.toList()..sort((a, c) => c.value.compareTo(a.value))).take(3)) {
      final m = MangaStore.I.byKey(e.key);
      if (m != null) topManga.add((m, e.value));
    }
  }

  int get hours => ((novelSeconds + mangaSeconds) / 3600).round();
  bool get empty => novelSeconds + mangaSeconds == 0 && finished.isEmpty && novelChapters + mangaChapters == 0;

  /// Un titolo da lettore, in base a come hai letto.
  String get title {
    if (bestWeekday != null && bestWeekday! >= 5) return 'Il lettore del weekend';
    if (bestStreak >= 30) return 'Il guardiano costante';
    if (mangaSeconds > novelSeconds * 2) return 'Il divoratore di tavole';
    if (finished.length >= 12) return 'L\'archivista instancabile';
    if (hours >= 100) return 'Il viaggiatore di mondi';
    return 'Il custode delle storie';
  }
}

class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key});
  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  final _key = GlobalKey();
  late int _year;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.month == 1 && now.day < 20 ? now.year - 1 : now.year;
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'lorekeeper_$_year.png'));
      await f.writeAsBytes(data!.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: 'Il mio $_year di letture su Lorekeeper');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Non riesco a creare l\'immagine: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = YearRecap(_year);
    final now = DateTime.now().year;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            const Align(alignment: Alignment.centerLeft, child: BackLink(trail: 'Diario')),
            Row(children: [
              Expanded(child: Text('Il tuo anno', style: LK.display(28))),
              IconButton(onPressed: () => setState(() => _year--), icon: Icon(Icons.chevron_left, color: LK.ink)),
              Text('$_year', style: LK.display(18)),
              IconButton(onPressed: _year >= now ? null : () => setState(() => _year++), icon: Icon(Icons.chevron_right, color: LK.ink)),
            ]),
            const SizedBox(height: 10),
            if (r.empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text('Nessuna lettura registrata nel $_year.', textAlign: TextAlign.center, style: LK.body(15, color: LK.muted, style: FontStyle.italic)),
              )
            else ...[
              Center(
                child: FittedBox(
                  child: RepaintBoundary(key: _key, child: _RecapCard(r)),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: LK.accent, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _share,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.ios_share),
                label: const Text('Condividi come immagine'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecapCard extends StatelessWidget {
  final YearRecap r;
  const _RecapCard(this.r);

  static const _gold = Color(0xFFE2B95C), _cream = Color(0xFFF7EEDC), _dim = Color(0xB3F7EEDC);

  Widget _stat(String big, String small) => Expanded(
        child: Column(children: [
          Text(big, style: LK.display(30, color: _gold)),
          Text(small.toUpperCase(), textAlign: TextAlign.center, style: LK.label(8.5, color: _dim, spacing: 1.4)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final fin = r.finished;
    return Container(
      width: 360,
      height: 640,
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B2433), Color(0xFF2C1F33), Color(0xFF3A1E24)]),
      ),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _StarsPainter(r.year))),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('LOREKEEPER', textAlign: TextAlign.center, style: LK.label(10, color: _gold, spacing: 5)),
            const SizedBox(height: 6),
            Text('Il mio ${r.year}', textAlign: TextAlign.center, style: LK.display(38, color: _cream)),
            Text('di letture', textAlign: TextAlign.center, style: LK.body(16, color: _dim, style: FontStyle.italic)),
            const SizedBox(height: 22),
            Row(children: [
              _stat('${r.hours}', 'ore lette'),
              _stat('${r.novelChapters + r.mangaChapters}', 'capitoli'),
              _stat('${r.days}', 'giorni'),
            ]),
            const SizedBox(height: 18),
            Container(height: 1, color: const Color(0x33E2B95C)),
            const SizedBox(height: 16),
            Text(fin.isEmpty ? 'NESSUN LIBRO FINITO (ANCORA)' : '${fin.length} ${fin.length == 1 ? 'LIBRO FINITO' : 'LIBRI FINITI'}',
                textAlign: TextAlign.center, style: LK.label(9.5, color: _gold, spacing: 2)),
            const SizedBox(height: 10),
            if (fin.isNotEmpty)
              SizedBox(
                height: 92,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final b in fin.take(14))
                    Container(
                      width: fin.length > 9 ? 18 : 24,
                      height: 70 + (b.title.length % 4) * 6.0,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: Color(b.spineColor),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: const Color(0x33000000)),
                      ),
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Center(
                          child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(8, color: Color(b.spineTitleColor ?? 0xFFF7EEDC))),
                        ),
                      ),
                    ),
                ]),
              ),
            Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 20), color: const Color(0xFF6B4A2B)),
            const SizedBox(height: 16),
            if (r.topManga.isNotEmpty) ...[
              Text('MANGA PIÙ LETTI', textAlign: TextAlign.center, style: LK.label(9.5, color: _gold, spacing: 2)),
              const SizedBox(height: 6),
              for (final (m, n) in r.topManga)
                Text('${m.title} · $n cap.', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: LK.body(13, color: _cream)),
              const SizedBox(height: 12),
            ],
            if (r.bestMonth != null)
              Text.rich(
                TextSpan(style: LK.body(13, color: _dim), children: [
                  const TextSpan(text: 'Il mese più letto: '),
                  TextSpan(text: _months[r.bestMonth!], style: LK.body(13, color: _cream)),
                  if (r.bestWeekday != null) ...[
                    const TextSpan(text: ' · il giorno preferito: '),
                    TextSpan(text: _weekdays[r.bestWeekday!], style: LK.body(13, color: _cream)),
                  ],
                ]),
                textAlign: TextAlign.center,
              ),
            if (r.bestStreak > 1)
              Text('Serie più lunga: ${r.bestStreak} giorni di fila', textAlign: TextAlign.center, style: LK.body(13, color: _dim)),
            if (r.topAuthor != null) Text('Autore dell\'anno: ${r.topAuthor}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: LK.body(13, color: _dim)),
            const Spacer(),
            Text('TITOLO DELL\'ANNO', textAlign: TextAlign.center, style: LK.label(8.5, color: _dim, spacing: 2)),
            Text(r.title, textAlign: TextAlign.center, style: LK.display(22, color: _gold, style: FontStyle.italic)),
          ]),
        ),
      ]),
    );
  }
}

class _StarsPainter extends CustomPainter {
  final int seed;
  _StarsPainter(this.seed);
  @override
  void paint(Canvas c, Size s) {
    final rnd = math.Random(seed);
    for (var i = 0; i < 70; i++) {
      final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height * 0.6);
      c.drawCircle(o, rnd.nextDouble() * 1.3 + 0.2, Paint()..color = Colors.white.withValues(alpha: rnd.nextDouble() * 0.5 + 0.1));
    }
    c.drawCircle(Offset(s.width * 0.82, s.height * 0.1), 18, Paint()..color = const Color(0x33E2B95C));
    c.drawCircle(Offset(s.width * 0.82, s.height * 0.1), 11, Paint()..color = const Color(0xCCF2D99A));
  }

  @override
  bool shouldRepaint(_StarsPainter o) => o.seed != seed;
}
