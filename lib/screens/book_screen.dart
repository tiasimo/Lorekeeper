import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: LibraryStore.I,
          builder: (context, _) {
            final cur = b.chapters.isEmpty ? 0 : b.lastChapter.clamp(0, b.chapters.length - 1);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                const Align(alignment: Alignment.centerLeft, child: BackLink(trail: 'Libreria')),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  BookCover(book: b, width: 118, height: 170),
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
                        icon: const Icon(Icons.menu_book_outlined, size: 18),
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
                Center(child: Segmented(labels: const ['Capitoli', 'Wiki'], selected: _tab, onChanged: (i) => setState(() => _tab = i))),
                const SizedBox(height: 14),
                if (_tab == 0)
                  for (var i = 0; i < b.chapters.length; i++) _chapterRow(b, i, cur)
                else
                  WikiView(book: b),
              ],
            );
          },
        ),
      ),
    );
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
