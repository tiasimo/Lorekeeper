import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/gemini.dart';
import '../services/library_store.dart';
import '../services/wiki.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'wiki_screens.dart';

// ======================================================================
// Chiedi al libro: domande senza spoiler
// ======================================================================

class AskBookScreen extends StatefulWidget {
  final Book book;
  const AskBookScreen({super.key, required this.book});
  @override
  State<AskBookScreen> createState() => _AskBookScreenState();
}

class _AskBookScreenState extends State<AskBookScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  final List<(String, String?)> _chat = []; // (domanda, risposta)
  bool _busy = false;

  static const _ideas = ['Chi è questo personaggio?', 'Riassumimi gli ultimi capitoli', 'Perché sono in viaggio?', 'Che legame c\'è tra i protagonisti?'];

  Future<void> _send([String? text]) async {
    final q = (text ?? _ctl.text).trim();
    if (q.isEmpty || _busy) return;
    _ctl.clear();
    final history = [for (final c in _chat) if (c.$2 != null) (c.$1, c.$2!)];
    setState(() {
      _chat.add((q, null));
      _busy = true;
    });
    _toEnd();
    String answer;
    try {
      answer = await WikiStore.I.askBook(widget.book, q, history.length > 6 ? history.sublist(history.length - 6) : history);
      if (answer.isEmpty) answer = 'Non sono riuscito a trovare una risposta.';
    } on GeminiError catch (e) {
      answer = '⚠ ${e.message}';
    } catch (e) {
      answer = '⚠ Qualcosa è andato storto: $e';
    }
    if (!mounted) return;
    setState(() {
      _chat[_chat.length - 1] = (q, answer);
      _busy = false;
    });
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });

  Widget _bubble(String text, {required bool mine}) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? LK.accent : LK.parchment,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 3),
              bottomRight: Radius.circular(mine ? 3 : 14),
            ),
            border: mine ? null : Border.all(color: LK.parchmentBorder),
          ),
          child: SelectableText(text, style: LK.body(14.5, color: mine ? Colors.white : LK.parchmentInk, height: 1.45)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BackLink(trail: 'Libro'),
              Text('Chiedi al libro', style: LK.display(26)),
              const SizedBox(height: 4),
              Text('Le risposte usano solo ciò che hai già letto di «${b.title}»: niente spoiler.', style: LK.body(13, color: LK.muted)),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                if (_chat.isEmpty) ...[
                  const SizedBox(height: 30),
                  Icon(Icons.auto_stories, size: 44, color: LK.border),
                  const SizedBox(height: 10),
                  Text('Hai dimenticato chi è qualcuno o perché è successo qualcosa? Chiedi pure.',
                      textAlign: TextAlign.center, style: LK.body(14, color: LK.muted, style: FontStyle.italic)),
                  const SizedBox(height: 16),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    for (final i in _ideas)
                      ActionChip(
                        backgroundColor: LK.card,
                        side: BorderSide(color: LK.border),
                        label: Text(i, style: LK.body(13)),
                        onPressed: () {
                          if (i.contains('questo')) {
                            _ctl.text = 'Chi è ';
                          } else {
                            _send(i);
                          }
                        },
                      ),
                  ]),
                ],
                for (final c in _chat) ...[
                  _bubble(c.$1, mine: true),
                  if (c.$2 != null)
                    _bubble(c.$2!, mine: false)
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: LK.accent)),
                          const SizedBox(width: 10),
                          Text('Sfoglio le pagine…', style: LK.body(13, color: LK.muted, style: FontStyle.italic)),
                        ]),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Fai una domanda…',
                    filled: true,
                    fillColor: LK.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: LK.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: LK.border)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: LK.accent),
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ======================================================================
// Cronologia degli eventi
// ======================================================================

class TimelineScreen extends StatefulWidget {
  final Book book;
  const TimelineScreen({super.key, required this.book});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _Chapter {
  final int pos;
  final Book book;
  final int chapter;
  String? summary;
  final List<WikiEvent> events = [];
  _Chapter(this.pos, this.book, this.chapter);
}

class _TimelineScreenState extends State<TimelineScreen> {
  Wiki? _w;
  bool _onlyMajor = false;
  String? _who;

  @override
  void initState() {
    super.initState();
    WikiStore.I.forBook(widget.book).then((w) {
      if (mounted) setState(() => _w = w);
    });
  }

  List<_Chapter> _chapters(Wiki w, int limit) {
    final map = <String, _Chapter>{};
    _Chapter? at(String bookId, int ch) {
      final book = LibraryStore.I.byId(bookId);
      if (book == null || ch >= book.chapters.length) return null;
      final pos = wikiPos(book, ch);
      if (pos > limit) return null;
      return map.putIfAbsent('$bookId:$ch', () => _Chapter(pos, book, ch));
    }

    w.summaries.forEach((k, v) {
      final i = k.lastIndexOf(':');
      at(k.substring(0, i), int.tryParse(k.substring(i + 1)) ?? 1 << 30)?.summary = v;
    });
    for (final e in w.events) {
      at(e.bookId, e.chapter)?.events.add(e);
    }
    var list = map.values.toList()..sort((a, c) => a.pos.compareTo(c.pos));
    if (_who != null) list = list.where((c) => c.events.any((e) => e.who.contains(_who))).toList();
    if (_onlyMajor) list = list.where((c) => c.events.any((e) => e.major)).toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    final b = widget.book;
    if (w == null) return Scaffold(body: Center(child: CircularProgressIndicator(color: LK.accent)));
    final limit = WikiStore.I.limitFor(b);
    final list = _chapters(w, limit);
    // personaggi più presenti negli eventi, per il filtro
    final counts = <String, int>{};
    for (final e in w.events.where((e) => e.pos <= limit)) {
      for (final id in e.who) {
        if (w.entries[id]?.type == 'personaggio') counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final top = (counts.keys.toList()..sort((a, c) => counts[c]!.compareTo(counts[a]!))).take(10).toList();
    String? lastBook;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            const BackLink(trail: 'Wiki'),
            Text('Cronologia', style: LK.display(26)),
            const SizedBox(height: 4),
            Text('Cosa è successo, capitolo per capitolo, fino al punto in cui sei.', style: LK.body(13, color: LK.muted)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                FilterChip(
                  selected: _onlyMajor,
                  selectedColor: LK.accent.withValues(alpha: 0.2),
                  backgroundColor: LK.card,
                  side: BorderSide(color: LK.border),
                  label: Text('Solo svolte', style: LK.body(13)),
                  onSelected: (v) => setState(() => _onlyMajor = v),
                ),
                for (final id in top)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: FilterChip(
                      selected: _who == id,
                      selectedColor: LK.accent.withValues(alpha: 0.2),
                      backgroundColor: LK.card,
                      side: BorderSide(color: LK.border),
                      avatar: WikiAvatar(w.entries[id]!, size: 22),
                      label: Text(w.entries[id]!.name.split(' ').first, style: LK.body(13)),
                      onSelected: (v) => setState(() => _who = v ? id : null),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Text('La cronologia si riempie man mano che Gemini analizza i capitoli.',
                    textAlign: TextAlign.center, style: LK.body(14, color: LK.muted, style: FontStyle.italic)),
              ),
            for (final c in list) ...[
              if (lastBook != c.book.id && (lastBook = c.book.id) != null && c.book.series != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
                  child: Text(c.book.title.toUpperCase(), style: LK.label(11, color: LK.accent, spacing: 1.6)),
                ),
              _chapterTile(w, c),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chapterTile(Wiki w, _Chapter c) {
    final title = c.book.chapters[c.chapter].title;
    final events = _onlyMajor ? c.events.where((e) => e.major).toList() : c.events;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 26,
          child: Column(children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.events.any((e) => e.major) ? LK.accent : LK.paper,
                border: Border.all(color: LK.accent, width: 2),
              ),
            ),
            Expanded(child: Container(width: 2, color: LK.border)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CAP. ${c.chapter + 1}', style: LK.label(9.5, spacing: 1.2)),
              Text(title, style: LK.display(16)),
              if (c.summary != null && !_onlyMajor) ...[
                const SizedBox(height: 4),
                Text(c.summary!, style: LK.body(13.5, color: LK.muted, height: 1.45)),
              ],
              for (final e in events)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(e.major ? Icons.star_rounded : Icons.circle, size: e.major ? 15 : 6, color: e.major ? const Color(0xFFC9A227) : LK.muted),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.text, style: LK.body(14, height: 1.4).copyWith(fontWeight: e.major ? FontWeight.w600 : null)),
                        if (e.who.isNotEmpty)
                          Wrap(spacing: 4, children: [
                            for (final id in e.who)
                              if (w.entries[id] != null)
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: id))),
                                  child: Text('· ${w.entries[id]!.name}', style: LK.body(12, color: LK.accent)),
                                ),
                          ]),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
