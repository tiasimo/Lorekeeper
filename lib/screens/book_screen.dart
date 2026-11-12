import '../widgets/adaptive.dart';
import 'book_extras.dart';
import 'world_map.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/annotations.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/quote_card.dart';
import 'reader_screen.dart';
import 'spine_editor_screen.dart';
import 'wiki_screens.dart';

class BookScreen extends StatefulWidget {
  final Book book;
  const BookScreen({super.key, required this.book});
  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  int _tab = 0;

  void _read([int? chapter]) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: widget.book, startChapter: chapter)));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    final wide = isWide(context);
    final list = ListenableBuilder(
          listenable: LibraryStore.I,
          builder: (context, _) {
            final cur = b.chapters.isEmpty ? 0 : b.lastChapter.clamp(0, b.chapters.length - 1);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                const Align(alignment: Alignment.centerLeft, child: BackLink(trail: 'Libreria')),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  bookHero(b, BookCover(book: b, width: 118, height: 170)),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Chip2(b.series ?? 'Novel'),
                      const SizedBox(height: 8),
                      Text(b.title, style: LK.display(26).copyWith(height: 1.1)),
                      if (b.author.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(b.author, style: LK.body(14, color: LK.muted, style: FontStyle.italic)),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '${b.chapters.length} capitoli${b.seriesIndex != null ? ' · vol. ${_fmt(b.seriesIndex!)}' : ''}',
                        style: LK.body(13, color: LK.muted),
                      ),
                      Text('Letto al ${(b.progress * 100).round()}%', style: LK.label(11, spacing: 0)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: LK.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _read(),
                        icon: LKIcon(LKGlyph.read, color: LK.onAccent, size: 20),
                        label: Text(b.lastReadAt == null ? 'INIZIA A LEGGERE' : 'CONTINUA', style: LK.label(12, color: LK.onAccent, spacing: 1.4)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: LK.card,
                        side: BorderSide(color: LK.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SpineEditorScreen(book: b))),
                      child: Icon(Icons.brush_outlined, color: LK.ink, size: 20),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                Center(child: Segmented(labels: const ['Capitoli', 'Wiki', 'Diario'], selected: _tab, onChanged: (i) => setState(() => _tab = i))),
                const SizedBox(height: 14),
                if (_tab == 0)
                  for (var i = 0; i < b.chapters.length; i++) _chapterRow(b, i, cur)
                else if (_tab == 1)
                  WikiView(book: b, onOpen: wide ? (e) => setState(() => _entry = e.id) : null)
                else
                  ..._diary(b),
              ],
            );
          },
        );
    if (!wide) return Scaffold(body: TabletSafeArea(child: list));
    // Tablet: a sinistra il libro (capitoli, wiki, diario), a destra la scheda o la mappa
    final entry = _entry;
    return Scaffold(
      body: SafeArea(
        child: Row(children: [
          SizedBox(width: 460, child: list),
          Container(width: 1, color: LK.border),
          Expanded(
            child: entry != null
                ? EmbeddedPane(
                    onClose: () => setState(() => _entry = null),
                    child: HeroMode(enabled: false, child: EntryScreen(key: ValueKey(entry), book: b, entryId: entry)),
                  )
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: LK.card, side: BorderSide(color: LK.border)),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AskBookScreen(book: b))),
                            icon: Icon(Icons.question_answer_outlined, color: LK.accent, size: 18),
                            label: Text('Chiedi al libro', style: LK.body(14)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: LK.card, side: BorderSide(color: LK.border)),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimelineScreen(book: b))),
                            icon: Icon(Icons.timeline, color: LK.accent, size: 18),
                            label: Text('Cronologia', style: LK.body(14)),
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(14)),
                        child: WorldMapScreen(book: b, embedded: true),
                      ),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }

  String? _entry; // tablet: scheda wiki aperta nel pannello

  final _review = TextEditingController();
  bool _reviewLoaded = false;

  @override
  void dispose() {
    if (_reviewLoaded) {
      final n = Annotations.I.of(widget.book.id);
      if (n.review != _review.text.trim()) {
        n.review = _review.text.trim();
        Annotations.I.save(widget.book.id);
      }
    }
    _review.dispose();
    super.dispose();
  }

  /// Voto, recensione, citazioni preferite e note del libro.
  List<Widget> _diary(Book b) {
    final n = Annotations.I.of(b.id);
    if (!_reviewLoaded) {
      _review.text = n.review;
      _reviewLoaded = true;
    }
    final favs = n.highlights.where((h) => h.favorite).toList();
    final others = n.highlights.where((h) => !h.favorite).toList()..sort((a, c) => a.chapter != c.chapter ? a.chapter.compareTo(c.chapter) : a.frac.compareTo(c.frac));
    String ch(int c) => c < b.chapters.length ? b.chapters[c].title : '';
    Widget quote(Highlight h) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
          decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.line)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 4, height: 44, margin: const EdgeInsets.only(right: 10, top: 2), decoration: BoxDecoration(color: Color(Annotations.colors[h.color % 4]), borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('«${h.text}»', style: LK.body(14.5, height: 1.5, style: FontStyle.italic)),
                if (h.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(h.note, style: LK.body(13.5, color: LK.muted))),
                const SizedBox(height: 4),
                Text(ch(h.chapter).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.label(8.5, spacing: 0.8)),
              ]),
            ),
            Column(children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(h.favorite ? Icons.star : Icons.star_border, color: h.favorite ? LK.gold : LK.muted, size: 20),
                onPressed: () async {
                  h.favorite = !h.favorite;
                  await Annotations.I.save(b.id);
                  setState(() {});
                },
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.ios_share, color: LK.accent, size: 19),
                onPressed: () => showQuoteShare(context, book: b, text: h.text, chapter: ch(h.chapter)),
              ),
            ]),
          ]),
        );
    return [
      const SectionLabel('Il tuo voto'),
      Row(children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed: () async {
              n.rating = n.rating == i ? 0 : i;
              await Annotations.I.save(b.id);
              setState(() {});
            },
            icon: Icon(i <= n.rating ? Icons.star_rounded : Icons.star_outline_rounded, color: LK.gold, size: 34),
          ),
      ]),
      const SizedBox(height: 10),
      const SectionLabel('Recensione'),
      TextField(
        controller: _review,
        maxLines: 6,
        minLines: 3,
        onEditingComplete: () {
          n.review = _review.text.trim();
          Annotations.I.save(b.id);
        },
        decoration: InputDecoration(
          hintText: 'Cosa ti è rimasto di questo libro?',
          filled: true,
          fillColor: LK.parchment,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.parchmentBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.parchmentBorder)),
        ),
      ),
      const SizedBox(height: 20),
      const SectionLabel('Citazioni preferite'),
      if (favs.isEmpty)
        Text('Mentre leggi, tieni premuta una frase e scegli «Citazione preferita».', style: LK.body(14, color: LK.muted, style: FontStyle.italic))
      else
        for (final h in favs) quote(h),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 16),
        const SectionLabel('Evidenziazioni e note'),
        for (final h in others) quote(h),
      ],
    ];
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _chapterRow(Book b, int i, int cur) {
    final done = i < cur;
    final current = i == cur && b.lastReadAt != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: LK.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _read(i),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: current ? LK.accentSoft : LK.line),
            ),
            child: Row(children: [
              SizedBox(width: 34, child: Text('${i + 1}', style: LK.display(16, color: LK.accent))),
              Expanded(child: Text(b.chapters[i].title, style: LK.body(15))),
              if (done) const Icon(Icons.check, color: Color(0xFF2F6B46), size: 18),
              if (current) Icon(Icons.bookmark, color: LK.accent, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
