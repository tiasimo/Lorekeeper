import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/wiki.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import 'book_extras.dart';
import 'wiki_screens.dart';
import 'world_map.dart';

/// Tablet: pannello accanto al testo con chi c'è nella pagina, le domande al libro e la mappa.
class ReaderSidePanel extends StatefulWidget {
  final Book book;
  final String pageText;
  final VoidCallback onClose;
  const ReaderSidePanel({super.key, required this.book, required this.pageText, required this.onClose});
  @override
  State<ReaderSidePanel> createState() => _ReaderSidePanelState();
}

class _ReaderSidePanelState extends State<ReaderSidePanel> {
  int _tab = 0;
  Wiki? _w;

  @override
  void initState() {
    super.initState();
    WikiStore.I.forBook(widget.book).then((w) {
      if (mounted) setState(() => _w = w);
    });
  }

  List<WikiEntry> _inPage() {
    final w = _w;
    if (w == null) return const [];
    final text = widget.pageText.toLowerCase();
    if (text.isEmpty) return const [];
    final limit = WikiStore.I.limitFor(widget.book);
    final found = <(int, WikiEntry)>[];
    for (final e in w.entries.values) {
      if (!e.visibleAt(limit)) continue;
      final names = {e.name, ...e.aliases, if (e.name.split(' ').first.length >= 4) e.name.split(' ').first};
      var at = -1;
      for (final n in names) {
        if (n.length < 3) continue;
        final i = text.indexOf(n.toLowerCase());
        if (i >= 0 && (at < 0 || i < at)) at = i;
      }
      if (at >= 0) found.add((at, e));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found.take(14)) f.$2];
  }

  @override
  Widget build(BuildContext context) {
    final limit = WikiStore.I.limitFor(widget.book);
    return Container(
      width: 340,
      decoration: BoxDecoration(color: LK.paper, border: Border(left: BorderSide(color: LK.border))),
      child: SafeArea(
        left: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: LK.line, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    for (final (i, label) in [(0, 'In pagina'), (1, 'Chiedi'), (2, 'Mappa')])
                      Expanded(
                        child: Material(
                          color: _tab == i ? LK.card : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() => _tab = i),
                            child: SizedBox(
                              height: 38,
                              child: Center(child: Text(label.toUpperCase(), style: LK.label(9.5, color: _tab == i ? LK.accent : LK.muted, spacing: 0.8))),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              IconButton(tooltip: 'Chiudi il pannello', onPressed: widget.onClose, icon: Icon(Icons.close, color: LK.muted)),
            ]),
          ),
          Expanded(
            child: IndexedStack(index: _tab, children: [
              _w == null
                  ? Center(child: CircularProgressIndicator(color: LK.accent))
                  : Builder(builder: (context) {
                      final list = _inPage();
                      if (list.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Nessun personaggio o luogo della wiki in questa pagina.',
                              textAlign: TextAlign.center, style: LK.body(14, color: LK.muted, style: FontStyle.italic)),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final e = list[i];
                          final d = e.manual ? (e.manualText ?? '') : e.descriptionAt(limit);
                          final role = e.roleAt(limit);
                          return Material(
                            color: LK.card,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: e.id))),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: LK.border)),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  WikiAvatar(e, size: 42),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(e.name, style: LK.display(15.5)),
                                      Text('${e.type.toUpperCase()}${role.isEmpty ? '' : ' · ${role.toUpperCase()}'}',
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.label(8.5, spacing: 0.8)),
                                      if (d.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(d, maxLines: 4, overflow: TextOverflow.ellipsis, style: LK.body(13, color: LK.muted, height: 1.4)),
                                      ],
                                    ]),
                                  ),
                                ]),
                              ),
                            ),
                          );
                        },
                      );
                    }),
              EmbeddedPane(onClose: () => setState(() => _tab = 0), child: AskBookScreen(book: widget.book)),
              if (_tab == 2) WorldMapScreen(book: widget.book, embedded: true) else const SizedBox.shrink(),
            ]),
          ),
        ]),
      ),
    );
  }
}
