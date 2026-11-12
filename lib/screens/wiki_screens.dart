import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../services/library_store.dart';
import '../services/wiki.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/wiki_styles.dart';
import 'book_extras.dart';

const _types = ['personaggio', 'luogo', 'termine'];
const _typeLabels = ['Personaggi', 'Luoghi', 'Termini'];

Color _avatarColor(String id) {
  const cols = [0xFF2F4A3A, 0xFF4A2F63, 0xFF26364A, 0xFF7A1E2E, 0xFF8A5A1E, 0xFF3E5A5A, 0xFF5A3A2A];
  return Color(cols[id.hashCode.abs() % cols.length]);
}

class WikiAvatar extends StatelessWidget {
  final WikiEntry e;
  final double size;
  const WikiAvatar(this.e, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final round = e.type == 'personaggio';
    final r = round ? BorderRadius.circular(size) : BorderRadius.circular(size * 0.22);
    if (e.photo != null && File(e.photo!).existsSync()) {
      return ClipRRect(borderRadius: r, child: Image.file(File(e.photo!), width: size, height: size, fit: BoxFit.cover));
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _avatarColor(e.id), borderRadius: r),
      child: Text(e.name.isEmpty ? '?' : e.name.characters.first.toUpperCase(), style: LK.display(size * 0.42, color: const Color(0xFFF2E6C8))),
    );
  }
}

String _where(Book book, WikiNote? n) {
  if (n == null) return '';
  if (n.bookId == book.id) return 'CAP. ${n.chapter + 1}';
  final other = LibraryStore.I.byId(n.bookId);
  if (other?.seriesIndex != null) {
    final v = other!.seriesIndex!;
    return 'VOL. ${v == v.roundToDouble() ? v.toInt() : v} · CAP. ${n.chapter + 1}';
  }
  return 'CAP. ${n.chapter + 1}';
}

// ======================================================================
// Scheda "Wiki" dentro la pagina del libro
// ======================================================================

class WikiView extends StatefulWidget {
  final Book book;
  const WikiView({super.key, required this.book});
  @override
  State<WikiView> createState() => _WikiViewState();
}

class _WikiViewState extends State<WikiView> {
  Wiki? _wiki;
  int _tab = 0;
  String _q = '';

  @override
  void initState() {
    super.initState();
    WikiStore.I.forBook(widget.book).then((w) {
      if (!mounted) return;
      setState(() => _wiki = w);
      WikiStore.I.fillDetails(widget.book);
      WikiStore.I.ensure(widget.book);
    });
  }

  Future<void> _newEntry() async {
    final name = TextEditingController(), text = TextEditingController();
    var type = _types[_tab];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: LK.paper,
          title: Text('Nuova voce', style: LK.display(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: type,
              isExpanded: true,
              dropdownColor: LK.card,
              items: [for (var i = 0; i < 3; i++) DropdownMenuItem(value: _types[i], child: Text(_typeLabels[i]))],
              onChanged: (v) => set(() => type = v ?? type),
            ),
            TextField(controller: text, maxLines: 3, decoration: const InputDecoration(labelText: 'Descrizione')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Crea')),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await WikiStore.I.addManual(widget.book, name.text, type, text.text);
      if (mounted) setState(() {});
    }
  }

  void _openEntry(WikiEntry e) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: e.id)));

  /// Riga dell'elenco: aspetto diverso per personaggi, luoghi e i tre stili dei termini.
  Widget _tile(Wiki w, WikiEntry e, int limit) {
    final b = widget.book;
    final sub = e.manual ? (e.manualText ?? '') : e.roleAt(limit);
    final where = e.manual ? 'AGGIUNTA DA TE' : _where(b, e.first);
    Widget card({required Widget child, Border? border, Color? color}) => Material(
          color: color ?? LK.card,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openEntry(e),
            child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: border ?? Border.all(color: LK.line)), child: child),
          ),
        );
    if (e.type == 'luogo') {
      final kind = e.extraAt('kind', limit) as String?;
      return card(
        border: Border.all(color: Colors.transparent, width: 0),
        child: SizedBox(
          height: 78,
          child: Stack(children: [
            Positioned.fill(
              child: e.photo != null && File(e.photo!).existsSync()
                  ? Image.file(File(e.photo!), fit: BoxFit.cover)
                  : Landscape(entry: e, limit: limit, height: 78, fade: false),
            ),
            const Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xC01C1714), Color(0x001C1714)], stops: [0, 0.8]))),
            ),
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              right: 40,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(18, color: const Color(0xFFFFF6E4))),
                Text([if (kind != null) kind, if (sub.isNotEmpty) sub].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(12.5, color: const Color(0xE6FFF6E4), style: FontStyle.italic)),
                Text(where, style: LK.label(8.5, color: const Color(0xB3FFF6E4), spacing: 1)),
              ]),
            ),
            const Positioned(right: 10, top: 0, bottom: 0, child: Icon(Icons.chevron_right, color: Color(0xCCFFF6E4))),
          ]),
        ),
      );
    }
    if (e.type == 'termine') {
      final style = termStyle(w, e, limit);
      final cat = termCategory(e, limit, style);
      if (style == 'grimorio') {
        return card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(gradient: grimoireGradient, borderRadius: BorderRadius.circular(8), border: Border.all(color: grimoireGold)),
                child: Center(child: Sigil(seed: e.id.hashCode, size: 36)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.name, style: LK.display(16)),
                  Text([cat, if (sub.isNotEmpty) sub].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.body(13, color: LK.muted)),
                ]),
              ),
              Icon(Icons.chevron_right, color: LK.border),
            ]),
          ),
        );
      }
      if (style == 'schedario') {
        final col = categoryColor(cat);
        return card(
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: col, width: 5))),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              Icon(categoryIcon(cat), color: col, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.name, style: LK.display(16)),
                  Text([cat, if (sub.isNotEmpty) sub].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.body(12.5, color: LK.muted)),
                ]),
              ),
              Icon(Icons.chevron_right, color: LK.border),
            ]),
          ),
        );
      }
      // dizionario
      return card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Text(e.name.characters.first.toUpperCase(), style: LK.display(26, color: LK.accent)),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: e.name, style: LK.display(15.5)),
                  if (sub.isNotEmpty) TextSpan(text: '  — $sub', style: LK.body(13, color: LK.muted, style: FontStyle.italic)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, color: LK.border),
          ]),
        ),
      );
    }
    return card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          WikiAvatar(e),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: LK.display(16)),
              if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.body(13, color: LK.muted)),
              Text(where, style: LK.label(9, spacing: 1)),
            ]),
          ),
          Icon(Icons.chevron_right, color: LK.border),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _wiki;
    if (w == null) return Padding(padding: const EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: LK.accent)));
    return ListenableBuilder(
      listenable: WikiStore.I,
      builder: (context, _) {
        final b = widget.book;
        final limit = WikiStore.I.limitFor(b);
        final st = WikiStore.I.status[w.key];
        final running = WikiStore.I.isRunning(b);
        final pend = WikiStore.I.pending(w, b, WikiStore.I.targetChapter(b));
        final q = _q.toLowerCase();
        final list = w.entries.values
            .where((e) => e.type == _types[_tab] && e.visibleAt(limit))
            .where((e) => q.isEmpty || e.name.toLowerCase().contains(q) || e.aliases.any((a) => a.toLowerCase().contains(q)))
            .toList()
          ..sort((a, c) => a.firstPos.compareTo(c.firstPos));

        String banner;
        if (running && st != null) {
          banner = st.phase ?? 'Gemini sta leggendo i capitoli… ${st.done}/${st.total}';
        } else if (pend > 0) {
          banner = '$pend capitoli da analizzare fino al punto in cui sei.';
        } else {
          banner = 'Aggiornata fino al punto in cui sei (anti-spoiler: ${LibraryStore.I.app.spoiler.toLowerCase()}).';
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: LK.parchment, borderRadius: BorderRadius.circular(10), border: Border.all(color: LK.parchmentBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(running ? Icons.auto_awesome : Icons.menu_book_outlined, size: 18, color: LK.parchmentInk),
                const SizedBox(width: 10),
                Expanded(child: Text(banner, style: LK.body(13, color: LK.parchmentInk))),
                if (!running && pend > 0)
                  TextButton(
                    onPressed: () => WikiStore.I.ensure(b, silent: false),
                    child: Text('AGGIORNA', style: LK.label(11, color: LK.accent, spacing: 1)),
                  ),
                if (!running)
                  PopupMenuButton<String>(
                    color: LK.card,
                    icon: Icon(Icons.more_vert, color: LK.parchmentInk, size: 20),
                    onSelected: (v) async {
                      if (v == 'links') {
                        final err = await WikiStore.I.analyzeLinksNow(b);
                        if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                        return;
                      }
                      if (v != 'rebuild') return;
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: LK.paper,
                          title: Text('Rigenerare la wiki?', style: LK.display(20)),
                          content: const Text('Gemini rilegge tutti i capitoli fino al punto in cui sei e ricrea schede complete, senza doppioni. Foto, note personali e voci create a mano restano.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
                            FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Rigenera')),
                          ],
                        ),
                      );
                      if (ok == true) WikiStore.I.rebuild(b);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'links', child: Text('Analizza i legami adesso', style: LK.body(14))),
                      PopupMenuItem(value: 'rebuild', child: Text('Rigenera wiki', style: LK.body(14))),
                    ],
                  ),
              ]),
              if (running && st != null && st.total > 0) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: st.done / st.total, color: LK.accent, backgroundColor: LK.parchmentBorder),
              ],
              if (st?.error != null && !running) ...[
                const SizedBox(height: 6),
                Text(st!.error!, style: LK.body(12, color: LK.accent)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Cerca nella wiki…',
              prefixIcon: Padding(padding: const EdgeInsets.all(12), child: LKIcon(LKGlyph.search, color: LK.muted, size: 20)),
              filled: true,
              fillColor: LK.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Segmented(labels: _typeLabels, selected: _tab, onChanged: (i) => setState(() => _tab = i))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: LK.card, side: BorderSide(color: LK.border)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GraphScreen(book: b))),
                icon: LKIcon(LKGlyph.graph, color: LK.accent, size: 18),
                label: Text('Grafo relazioni', style: LK.body(13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: LK.card, side: BorderSide(color: LK.border)),
                onPressed: _newEntry,
                icon: Icon(Icons.add, color: LK.accent, size: 18),
                label: Text('Nuova voce', style: LK.body(13)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: LK.card, side: BorderSide(color: LK.border)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AskBookScreen(book: b))),
                icon: Icon(Icons.question_answer_outlined, color: LK.accent, size: 18),
                label: Text('Chiedi al libro', style: LK.body(13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: LK.card, side: BorderSide(color: LK.border)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimelineScreen(book: b))),
                icon: Icon(Icons.timeline, color: LK.accent, size: 18),
                label: Text('Cronologia', style: LK.body(13)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                running ? 'Le voci compariranno qui man mano.' : 'Nessuna voce ancora.',
                textAlign: TextAlign.center,
                style: LK.body(14, color: LK.muted, style: FontStyle.italic),
              ),
            ),
          for (final e in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: _tile(w, e, limit)),
        ]);
      },
    );
  }
}

// ======================================================================
// Scheda di una voce (personaggio, luogo, termine)
// ======================================================================

class EntryScreen extends StatefulWidget {
  final Book book;
  final String entryId;
  const EntryScreen({super.key, required this.book, required this.entryId});
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  Wiki? _w;
  final _notes = TextEditingController();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    WikiStore.I.forBook(widget.book).then((w) {
      if (!mounted) return;
      setState(() => _w = w);
      _notes.text = w.entries[widget.entryId]?.myNotes ?? '';
    });
  }

  @override
  void dispose() {
    final w = _w, e = _w?.entries[widget.entryId];
    if (_dirty && w != null && e != null) {
      e.myNotes = _notes.text;
      WikiStore.I.save(w);
    }
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(WikiEntry e) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final src = r?.files.single.path;
    if (src == null || _w == null) return;
    final dest = p.join(WikiStore.I.photoDir(), '${_w!.key}_${e.id}_${DateTime.now().millisecondsSinceEpoch}${p.extension(src)}');
    await File(src).copy(dest);
    if (e.photo != null) {
      try {
        await File(e.photo!).delete();
      } catch (_) {}
    }
    e.photo = dest;
    await WikiStore.I.save(_w!);
    if (mounted) setState(() {});
  }

  /// Unisce questa voce a un'altra (doppione): restano un solo nome e tutte le informazioni.
  Future<void> _merge(WikiEntry e) async {
    final w = _w!;
    final others = w.entries.values.where((x) => x.id != e.id && x.type == e.type).toList()..sort((a, b) => a.name.compareTo(b.name));
    final target = await showModalBottomSheet<WikiEntry>(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => ListView(controller: scroll, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Text('Unisci «${e.name}» con…', style: LK.display(19))),
          for (final o in others) ListTile(leading: WikiAvatar(o, size: 36), title: Text(o.name, style: LK.body(15)), onTap: () => Navigator.pop(ctx, o)),
        ]),
      ),
    );
    if (target == null) return;
    w.mergeInto(e, target);
    await WikiStore.I.save(w);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: target.id)));
  }

  Future<void> _edit(WikiEntry e) async {
    final name = TextEditingController(text: e.name);
    final aliases = TextEditingController(text: e.aliases.join(', '));
    final text = TextEditingController(text: e.manualText ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LK.paper,
        title: Text('Modifica voce', style: LK.display(20)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: aliases, decoration: const InputDecoration(labelText: 'Altri nomi (separati da virgola)')),
            TextField(controller: text, maxLines: 3, decoration: const InputDecoration(labelText: 'Descrizione tua (opzionale)')),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              await WikiStore.I.deleteEntry(widget.book, e);
              if (mounted) Navigator.pop(context);
            },
            child: Text('Elimina', style: TextStyle(color: LK.accent)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              await _merge(e);
            },
            child: Text('Unisci con…', style: TextStyle(color: LK.ink)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isNotEmpty) e.name = name.text.trim();
    e.aliases
      ..clear()
      ..addAll(aliases.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
    e.manualText = text.text.trim().isEmpty ? null : text.text.trim();
    await WikiStore.I.save(_w!);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    final e = w?.entries[widget.entryId];
    if (w == null || e == null) return Scaffold(body: Center(child: CircularProgressIndicator(color: LK.accent)));
    final b = widget.book;
    final limit = WikiStore.I.limitFor(b);
    final notes = e.notesAt(limit);
    final rels = w.relationsAt(limit).where((r) => r.a == e.id || r.b == e.id).toList();
    final mentions = notes.map((n) => '${n.bookId}:${n.chapter}').toSet().length;
    final typeLabel = _typeLabels[_types.indexOf(e.type).clamp(0, 2)];
    return Scaffold(
      body: TabletSafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            Row(children: [
              const BackLink(trail: 'Wiki'),
              const Spacer(),
              IconButton(onPressed: () => _edit(e), icon: Icon(Icons.edit_outlined, color: LK.ink)),
            ]),
            ..._header(w, e, limit, typeLabel, mentions, rels.length),
            if (e.aliases.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionLabel('Chiamato anche'),
              Text(e.aliases.join(' · '), style: LK.body(14)),
            ],
            const SizedBox(height: 20),
            const SectionLabel('Descrizione'),
            if (e.manualText != null && e.manualText!.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(e.manualText!, style: LK.body(15, height: 1.6))),
            if (e.descriptionAt(limit).isNotEmpty) ...[
              Text(e.descriptionAt(limit), style: LK.body(15.5, height: 1.65)),
              // Novità uscite dopo l'ultima riscrittura completa (avviene ogni 10 capitoli).
              if (notes.any((n) => n.pos > e.descriptionPosAt(limit))) ...[
                const SizedBox(height: 14),
                Text('NOVITÀ RECENTI', style: LK.label(10, spacing: 1.4, color: LK.accent)),
                const SizedBox(height: 6),
                for (final n in notes.where((n) => n.pos > e.descriptionPosAt(limit)))
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(n.text, style: LK.body(15, height: 1.55))),
              ],
            ] else if (notes.isEmpty && (e.manualText == null || e.manualText!.isEmpty))
              Text('Ancora nessuna informazione fino al punto in cui sei.', style: LK.body(14, color: LK.muted, style: FontStyle.italic))
            else
              for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(n.text, style: LK.body(15, height: 1.55))),
            ..._afterDescription(w, e, limit, notes),
            if (notes.isNotEmpty && e.descriptionAt(limit).isNotEmpty && e.type != 'luogo')
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  iconColor: LK.accent,
                  collapsedIconColor: LK.muted,
                  title: Text('CRONOLOGIA CAPITOLO PER CAPITOLO', style: LK.label(10, spacing: 1.4)),
                  children: [
                    for (final n in notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            margin: const EdgeInsets.only(top: 3, right: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: LK.line, borderRadius: BorderRadius.circular(5)),
                            child: Text(_where(b, n).replaceAll('CAP. ', 'C').replaceAll('VOL. ', 'V'), style: LK.label(9, spacing: 0.4)),
                          ),
                          Expanded(child: Text(n.text, style: LK.body(14, height: 1.5, color: LK.muted))),
                        ]),
                      ),
                  ],
                ),
              ),
            if (rels.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SectionLabel('Collegamenti'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in rels)
                  Builder(builder: (context) {
                    final other = w.entries[r.a == e.id ? r.b : r.a];
                    if (other == null) return const SizedBox.shrink();
                    final label = r.a == e.id ? r.label : '${r.label} (inverso)';
                    return InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: b, entryId: other.id))),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
                        decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: LK.border)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          WikiAvatar(other, size: 28),
                          const SizedBox(width: 8),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(other.name, style: LK.body(13)),
                            Text(label, style: LK.label(9, spacing: 0.3)),
                          ]),
                        ]),
                      ),
                    );
                  }),
              ]),
            ],
            const SizedBox(height: 22),
            const SectionLabel('Le mie note'),
            TextField(
              controller: _notes,
              maxLines: 4,
              onChanged: (_) => _dirty = true,
              decoration: InputDecoration(
                hintText: 'Scrivi qui le tue impressioni…',
                filled: true,
                fillColor: LK.parchment,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.parchmentBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.parchmentBorder)),
              ),
            ),
            if (e.photo != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await File(e.photo!).delete();
                  } catch (_) {}
                  e.photo = null;
                  await WikiStore.I.save(w);
                  setState(() {});
                },
                icon: Icon(Icons.hide_image_outlined, color: LK.muted),
                label: Text('Rimuovi foto', style: LK.body(13, color: LK.muted)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- testata diversa per personaggi, luoghi e termini ----------

  List<Widget> _header(Wiki w, WikiEntry e, int limit, String typeLabel, int mentions, int relCount) {
    final b = widget.book;
    final first = e.manual ? '—' : _where(b, e.first).toLowerCase().replaceAll('cap.', 'Cap.').replaceAll('vol.', 'Vol.');
    if (e.type == 'luogo') return _placeHeader(w, e, limit, first, mentions);
    if (e.type == 'termine') {
      final style = termStyle(w, e, limit);
      if (style == 'grimorio') return _grimoireHeader(e, limit);
      if (style == 'schedario') return _archiveHeader(w, e, limit, first);
      return _dictionaryHeader(e, limit);
    }
    return [
      ParchmentCard(
        seal: e.name,
        child: Column(children: [
          GestureDetector(
            onTap: () => _pickPhoto(e),
            child: OvalPortrait(
              width: 132,
              height: 168,
              child: e.photo != null && File(e.photo!).existsSync()
                  ? Image.file(File(e.photo!), fit: BoxFit.cover)
                  : Container(
                      color: LK.line,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_outlined, color: LK.muted, size: 28),
                        const SizedBox(height: 6),
                        Text('AGGIUNGI\nRITRATTO', textAlign: TextAlign.center, style: LK.label(9, spacing: 1.2)),
                      ]),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Text(typeLabel.substring(0, typeLabel.length - 1).toUpperCase(), style: LK.label(10, color: LK.parchmentInk, spacing: 2.4)),
          const SizedBox(height: 4),
          Text(e.name, textAlign: TextAlign.center, style: LK.display(28, color: LK.ink).copyWith(height: 1.1)),
          if (e.roleAt(limit).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.roleAt(limit), textAlign: TextAlign.center, style: LK.body(14, color: LK.parchmentInk, style: FontStyle.italic)),
          ],
        ]),
      ),
      const SizedBox(height: 18),
      Row(children: [
        _stat('PRIMA APPARIZIONE', first),
        const SizedBox(width: 8),
        _stat('CAPITOLI', '$mentions'),
        const SizedBox(width: 8),
        _stat('RELAZIONI', '$relCount'),
      ]),
      const SizedBox(height: 0),
    ];
  }

  List<Widget> _placeHeader(Wiki w, WikiEntry e, int limit, String first, int mentions) {
    final path = placePath(w, e, limit);
    final kind = (e.extraAt('kind', limit) as String?) ?? 'luogo';
    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          e.photo != null && File(e.photo!).existsSync()
              ? SizedBox(height: 280, width: double.infinity, child: Image.file(File(e.photo!), fit: BoxFit.cover))
              : Landscape(entry: e, limit: limit, height: 280),
          if (e.photo != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)], stops: const [0.45, 1])),
              ),
            ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              tooltip: 'Usa una tua immagine',
              onPressed: () => _pickPhoto(e),
              icon: const Icon(Icons.add_photo_alternate_outlined, color: Color(0xEEFFF6E4)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: const Color(0x38FFF6E4), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x80FFF6E4))),
                child: Text(kind.toUpperCase(), style: LK.label(10, color: const Color(0xFFFFF6E4), spacing: 1.4)),
              ),
              const SizedBox(height: 6),
              Text(e.name, style: LK.display(32, color: const Color(0xFFFFF6E4)).copyWith(shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))])),
              if (path.length > 1)
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (var i = 0; i < path.length; i++) ...[
                    if (i > 0) Text('  ›  ', style: LK.body(13, color: const Color(0xCCFFF6E4))),
                    GestureDetector(
                      onTap: path[i].id.isEmpty || path[i].id == e.id ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: path[i].id))),
                      child: Text(path[i].name, style: LK.body(13, color: const Color(0xEEFFF6E4), style: FontStyle.italic)),
                    ),
                  ],
                ])
              else if (e.roleAt(limit).isNotEmpty)
                Text(e.roleAt(limit), style: LK.body(13, color: const Color(0xEEFFF6E4), style: FontStyle.italic)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        _stat('PRIMA MENZIONE', first),
        const SizedBox(width: 8),
        _stat('CAPITOLI', '$mentions'),
      ]),
    ];
  }

  List<Widget> _grimoireHeader(WikiEntry e, int limit) {
    final cat = termCategory(e, limit, 'grimorio');
    return [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(gradient: grimoireGradient, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 8))]),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          decoration: BoxDecoration(border: Border.all(color: grimoireGold), borderRadius: BorderRadius.circular(7)),
          child: Column(children: [
            Sigil(seed: e.id.hashCode),
            const SizedBox(height: 10),
            Text(cat.toUpperCase(), style: LK.label(10, color: grimoireGold, spacing: 2)),
            const SizedBox(height: 6),
            Text(e.name, textAlign: TextAlign.center, style: LK.display(28, color: const Color(0xFFF2D88A))),
            if (e.roleAt(limit).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(e.roleAt(limit), textAlign: TextAlign.center, style: LK.body(14, color: const Color(0xFFD8C9A8), style: FontStyle.italic)),
            ],
          ]),
        ),
      ),
    ];
  }

  List<Widget> _dictionaryHeader(WikiEntry e, int limit) {
    final cat = termCategory(e, limit, 'dizionario');
    final gram = (e.extraAt('gram', limit) as String?) ?? cat;
    final defs = ((e.extraAt('defs', limit) as List?) ?? const []).whereType<String>().toList();
    if (defs.isEmpty && e.roleAt(limit).isNotEmpty) defs.add(e.roleAt(limit));
    final quote = e.extraAt('quote', limit);
    return [
      Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: LK.border))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(e.name.characters.first.toUpperCase(), style: LK.display(66, color: LK.accent).copyWith(height: 0.9)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: LK.display(27)),
              Text(gram, style: LK.body(13, color: LK.muted, style: FontStyle.italic)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < defs.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text('${i + 1}.', style: LK.body(15, color: LK.accent))),
            Expanded(child: Text(defs[i], style: LK.body(15, height: 1.55))),
          ]),
        ),
      if (quote is Map && quote['t'] is String) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: LK.card, border: Border(left: BorderSide(color: LK.gold, width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('«${quote['t']}»', style: LK.body(14.5, height: 1.55, style: FontStyle.italic)),
            const SizedBox(height: 6),
            Text(_where(widget.book, WikiNote(0, '', (quote['b'] as String?) ?? '', (quote['c'] as int?) ?? 0)), style: LK.label(9, spacing: 1)),
          ]),
        ),
      ],
    ];
  }

  List<Widget> _archiveHeader(Wiki w, WikiEntry e, int limit, String first) {
    final cat = termCategory(e, limit, 'schedario');
    final col = categoryColor(cat);
    final facts = <String, String>{};
    final members = w.groupsAt(limit).entries.where((g) => g.key.toLowerCase() == e.name.toLowerCase() || e.aliases.any((a) => a.toLowerCase() == g.key.toLowerCase())).expand((g) => g.value).toSet();
    if (members.isNotEmpty) facts['MEMBRI'] = members.map((id) => w.entries[id]?.name).whereType<String>().join(', ');
    final f = e.extraAt('facts', limit);
    if (f is Map) {
      f.forEach((k, v) {
        if (k is String && v is String && !(k == 'MEMBRI' && facts.containsKey('MEMBRI'))) facts[k] = v;
      });
    }
    facts['PRIMA VOLTA'] = first;
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(color: col, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(categoryIcon(cat), size: 14, color: const Color(0xFFFFF6E4)),
            const SizedBox(width: 6),
            Text(cat.toUpperCase(), style: LK.label(10, color: const Color(0xFFFFF6E4), spacing: 1.4)),
          ]),
        ),
      ),
      ClipRRect(
        borderRadius: const BorderRadius.only(topRight: Radius.circular(10), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
        child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LK.card,
          border: Border(top: BorderSide(color: col, width: 4), left: BorderSide(color: LK.border), right: BorderSide(color: LK.border), bottom: BorderSide(color: LK.border)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.name, style: LK.display(28)),
          if (e.roleAt(limit).isNotEmpty) Text(e.roleAt(limit), style: LK.body(13.5, color: LK.muted, style: FontStyle.italic)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: LK.border))),
            child: Column(children: [
              for (final x in facts.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 92, child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(x.key, style: LK.label(9, spacing: 1)))),
                    Expanded(child: Text(x.value, style: LK.body(13.5))),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      ),
    ];
  }

  /// Sezioni dopo la descrizione: "Accaduto qui" per i luoghi, "Compare in" e "Vedi anche" per i termini.
  List<Widget> _afterDescription(Wiki w, WikiEntry e, int limit, List<WikiNote> notes) {
    final b = widget.book;
    if (e.type == 'luogo') {
      final names = [e.name, ...e.aliases.where((a) => a.length >= 4)].map((n) => n.toLowerCase()).toList();
      final visitors = w.entries.values
          .where((c) => c.type == 'personaggio' && c.notesAt(limit).any((n) => names.any(n.text.toLowerCase().contains)))
          .take(8)
          .toList();
      return [
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionLabel('Accaduto qui'),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: LK.gold, width: 2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_where(b, n), style: LK.label(9, color: LK.accent, spacing: 1)),
                    const SizedBox(height: 2),
                    Text(n.text, style: LK.body(14, height: 1.5)),
                  ]),
                ),
            ]),
          ),
        ],
        if (visitors.isNotEmpty) ...[
          const SizedBox(height: 14),
          const SectionLabel('Chi ci è stato'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in visitors)
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: b, entryId: v.id))),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
                  decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: LK.border)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [WikiAvatar(v, size: 26), const SizedBox(width: 8), Text(v.name, style: LK.body(13))]),
                ),
              ),
          ]),
        ],
      ];
    }
    if (e.type == 'termine') {
      final style = termStyle(w, e, limit);
      if (style == 'grimorio') {
        final chs = notes.map((n) => _where(b, n).toLowerCase().replaceAll('cap.', 'Cap.').replaceAll('vol.', 'Vol.')).toSet().toList();
        if (chs.isEmpty) return const [];
        return [
          const SizedBox(height: 14),
          const SectionLabel('Compare in'),
          Text(chs.join(' · '), style: LK.body(13.5, color: LK.muted, style: FontStyle.italic)),
        ];
      }
      if (style == 'dizionario') {
        final also = seeAlso(w, e, '${e.descriptionAt(limit)} ${notes.map((n) => n.text).join(' ')}', limit);
        if (also.isEmpty) return const [];
        return [
          const SizedBox(height: 14),
          const SectionLabel('Vedi anche'),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var i = 0; i < also.length; i++)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: b, entryId: also[i].id))),
                child: Text('${also[i].name}${i < also.length - 1 ? ' ·' : ''}', style: LK.body(14, color: LK.accent)),
              ),
          ]),
        ];
      }
    }
    return const [];
  }

  Widget _stat(String l, String v) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: LK.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: LK.label(8, spacing: 1)),
            const SizedBox(height: 3),
            Text(v.isEmpty ? '—' : v, style: LK.body(14)),
          ]),
        ),
      );
}

/// Anteprima rapida dal lettore: "chi era questo?"
Future<void> showEntryPeek(BuildContext context, Book book, WikiEntry e) {
  final limit = WikiStore.I.limitFor(book);
  final notes = e.notesAt(limit);
  final shown = notes.length > 3 ? notes.sublist(notes.length - 3) : notes;
  return showModalBottomSheet(
    context: context,
    backgroundColor: LK.paper,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            WikiAvatar(e, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: LK.display(22)),
                if (e.roleAt(limit).isNotEmpty) Text(e.roleAt(limit), style: LK.body(13, color: LK.muted, style: FontStyle.italic)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          if (e.manualText != null && e.manualText!.isNotEmpty) Text(e.manualText!, style: LK.body(15, height: 1.5)),
          if (e.descriptionAt(limit).isNotEmpty)
            Text(e.descriptionAt(limit), maxLines: 7, overflow: TextOverflow.ellipsis, style: LK.body(15, height: 1.5))
          else
            for (final n in shown) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(n.text, style: LK.body(15, height: 1.5))),
          if (e.myNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Le tue note: ${e.myNotes}', style: LK.body(13, color: LK.muted, style: FontStyle.italic)),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: book, entryId: e.id)));
              },
              child: Text('APRI LA SCHEDA', style: LK.label(11, color: LK.accent, spacing: 1.2)),
            ),
          ),
        ]),
      ),
    ),
  );
}

// ======================================================================
// Grafo delle relazioni
// ======================================================================

class GraphScreen extends StatefulWidget {
  final Book book;
  const GraphScreen({super.key, required this.book});
  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

/// Tipi di legame: colore sulla pergamena, colore nel cielo, nome in legenda.
const _kindInk = <String, Color>{
  'famiglia': Color(0xFF7A1E2E),
  'amicizia': Color(0xFF3E6B4A),
  'amore': Color(0xFFB0456A),
  'rivalità': Color(0xFFB0561E),
  'alleanza': Color(0xFF2F4A6A),
  'speciale': Color(0xFF9A7420),
};
const _kindSky = <String, Color>{
  'famiglia': Color(0xFFE88A98),
  'amicizia': Color(0xFF8FD8A6),
  'amore': Color(0xFFF4A3C6),
  'rivalità': Color(0xFFF2A766),
  'alleanza': Color(0xFF94B9F2),
  'speciale': Color(0xFFE2C46B),
};
const _kindName = <String, String>{
  'famiglia': 'Famiglia',
  'amicizia': 'Amici',
  'amore': 'Amore',
  'rivalità': 'Rivali',
  'alleanza': 'Alleati',
  'speciale': 'Speciali',
};

/// Un collegamento disegnato: uno solo per coppia. I gruppi hanno id "g:Nome".
class _Edge {
  final String a, b, kind;
  final String? label;
  const _Edge(this.a, this.b, this.kind, this.label);
}

class _GraphPage {
  final Map<String, Offset> pos = {};
  List<_Edge> edges = const [];
  Size area = const Size(1000, 1000);
  final tc = TransformationController();
  Size? fittedFor;
}

bool _isGroup(String id) => id.startsWith('g:');

class _GraphScreenState extends State<GraphScreen> {
  Wiki? _w;
  int _page = 0;
  final _sky = _GraphPage(), _all = _GraphPage();
  final Map<String, int> _mentions = {};
  String? _root, _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await WikiStore.I.forBook(widget.book);
    if (!mounted) return;
    _w = w;
    _sky.pos.clear();
    _all.pos.clear();
    _sky.edges = const [];
    _all.edges = const [];
    _sky.fittedFor = null;
    _all.fittedFor = null;
    _mentions.clear();
    _build(w);
    if (_sky.pos.isEmpty && _all.pos.isNotEmpty) _page = 1;
    setState(() {});
  }

  bool _analyzing = false;

  Future<void> _analyze() async {
    setState(() => _analyzing = true);
    final err = await WikiStore.I.analyzeLinksNow(widget.book);
    if (!mounted) return;
    setState(() => _analyzing = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      await _load();
    }
  }

  /// Messaggio quando i legami non ci sono ancora: si creano a fine volume.
  Widget _waiting({required bool sky}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('I legami si creano quando finisci il volume: Gemini rilegge tutte le schede insieme per essere più preciso.',
                textAlign: TextAlign.center, style: LK.body(15, color: sky ? const Color(0xFFA9A6C4) : LK.muted, style: FontStyle.italic)),
            const SizedBox(height: 16),
            _analyzing
                ? CircularProgressIndicator(color: sky ? const Color(0xFFE2C46B) : LK.accent)
                : OutlinedButton(
                    onPressed: _analyze,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: sky ? const Color(0xFFE2C46B) : LK.accent,
                      side: BorderSide(color: sky ? const Color(0xFFE2C46B) : LK.accent),
                    ),
                    child: const Text('Analizza adesso fin dove sei'),
                  ),
          ]),
        ),
      );

  // ---------------- dati ----------------

  void _build(Wiki w) {
    final limit = WikiStore.I.limitFor(widget.book);
    for (final e in w.entries.values) {
      _mentions[e.id] = e.notesAt(limit).map((n) => '${n.bookId}:${n.chapter}').toSet().length;
    }
    final rels = w.relationsAt(limit).where((r) => w.entries[r.a] != null && w.entries[r.b] != null && r.a != r.b).toList();
    final groups = w.groupsAt(limit);
    final ids = <String>{for (final r in rels) ...[r.a, r.b], for (final m in groups.values) ...m};
    if (ids.isEmpty) return;
    // Protagonista: chi ha "protagonista" nel ruolo, altrimenti chi compare di più.
    int m(String id) => _mentions[id] ?? 0;
    final prot = ids.where((id) => w.entries[id]!.roleAt(limit).toLowerCase().contains('protagonist')).toList()..sort((a, b) => m(b) - m(a));
    _root = prot.isNotEmpty ? prot.first : (ids.toList()..sort((a, b) => m(b) - m(a))).first;

    // ---- Tutti i legami ----
    _all.edges = [
      ..._pairEdges(rels),
      for (final g in groups.entries)
        for (final id in g.value) _Edge('g:${g.key}', id, 'speciale', null),
    ];
    _treeLayout(_all, {...ids, for (final g in groups.keys) 'g:$g'});

    // ---- Costellazione: il protagonista e i suoi legami ----
    final root = _root!;
    final ring1 = <String>[];
    final ring2 = <String, String>{}; // membro → gruppo
    for (final r in rels) {
      final o = r.a == root ? r.b : (r.b == root ? r.a : null);
      if (o != null && !ring1.contains(o)) ring1.add(o);
    }
    final myGroups = groups.entries.where((g) => g.value.contains(root)).toList();
    for (final g in myGroups) {
      ring1.add('g:${g.key}');
    }
    for (final g in myGroups) {
      for (final id in g.value) {
        if (id != root && !ring1.contains(id)) ring2.putIfAbsent(id, () => 'g:${g.key}');
      }
    }
    if (ring1.isEmpty) return;
    final inSky = {root, ...ring1, ...ring2.keys};
    _sky.edges = [
      ..._pairEdges(rels.where((r) => inSky.contains(r.a) && inSky.contains(r.b)).toList()),
      for (final g in myGroups)
        for (final id in g.value) _Edge('g:${g.key}', id, 'speciale', null),
    ];
    _ringLayout(_sky, root, ring1, ring2);
  }

  /// Un solo collegamento per coppia, con l'etichetta letta verso il protagonista
  /// ("Reynolds — padre di — Arthur") o dall'alto verso il basso.
  List<_Edge> _pairEdges(List<WikiRelation> rels) {
    final byPair = <String, List<WikiRelation>>{};
    for (final r in rels) {
      final k = r.a.compareTo(r.b) < 0 ? '${r.a}|${r.b}' : '${r.b}|${r.a}';
      byPair.putIfAbsent(k, () => []).add(r);
    }
    return [
      for (final list in byPair.values)
        () {
          final r = list.firstWhere((r) => r.b == _root, orElse: () => list.firstWhere((r) => r.a != _root, orElse: () => list.first));
          return _Edge(r.a, r.b, r.kind, r.label);
        }(),
    ];
  }

  /// Albero verticale: genitori sopra, coniugi e fratelli alla stessa altezza,
  /// gruppi come un'insegna sopra i membri; si allarga in orizzontale quanto serve.
  void _treeLayout(_GraphPage g, Set<String> nodes) {
    const sp = 170.0, lv = 190.0, margin = 130.0;
    final adj = <String, List<(String, int)>>{for (final n in nodes) n: []};
    void link(String a, String b, int d) {
      if (!adj.containsKey(a) || !adj.containsKey(b)) return;
      adj[a]!.add((b, d));
      adj[b]!.add((a, -d));
    }

    for (final e in g.edges) {
      if (_isGroup(e.a)) {
        link(e.a, e.b, 1);
        continue;
      }
      final l = (e.label ?? '').toLowerCase();
      bool has(List<String> ws) => ws.any(l.contains);
      if (has(['madre', 'padre', 'genitor', 'nonn'])) {
        link(e.a, e.b, 1);
      } else if (has(['figli'])) {
        link(e.a, e.b, -1);
      } else if (has(['coniug', 'marit', 'moglie', 'fratell', 'sorell', 'gemell', 'cugin', 'fidanzat', 'amant', 'sposa'])) {
        link(e.a, e.b, 0);
      } else {
        link(e.a, e.b, 1);
      }
    }
    int m(String id) => _isGroup(id) ? -1 : (_mentions[id] ?? 0);
    final level = <String, int>{};
    final comps = <List<String>>[];
    final rest = nodes.toList()..sort((a, b) => m(b) - m(a));
    if (_root != null && nodes.contains(_root)) rest.insert(0, _root!);
    for (final start in rest) {
      if (level.containsKey(start)) continue;
      final comp = <String>[start];
      level[start] = 0;
      for (var i = 0; i < comp.length; i++) {
        for (final (o, d) in adj[comp[i]]!) {
          if (level.containsKey(o)) continue;
          level[o] = level[comp[i]]! + d;
          comp.add(o);
        }
      }
      final minL = comp.map((n) => level[n]!).reduce(math.min);
      for (final n in comp) {
        level[n] = level[n]! - minL;
      }
      comps.add(comp);
    }
    // Ordine dentro ogni livello: baricentro dei vicini, qualche passata.
    final x = <String, double>{};
    var offset = margin;
    var maxLevel = 0;
    for (final comp in comps) {
      final levels = <int, List<String>>{};
      for (final n in comp) {
        levels.putIfAbsent(level[n]!, () => []).add(n);
      }
      final keys = levels.keys.toList()..sort();
      maxLevel = math.max(maxLevel, keys.last);
      void place() {
        for (final k in keys) {
          final row = levels[k]!;
          for (var i = 0; i < row.length; i++) {
            x[row[i]] = (i - (row.length - 1) / 2) * sp;
          }
        }
      }

      place();
      for (var it = 0; it < 8; it++) {
        for (final k in (it.isEven ? keys : keys.reversed)) {
          final row = levels[k]!;
          double bary(String n) {
            final ns = adj[n]!.map((t) => t.$1).where(x.containsKey).toList();
            return ns.isEmpty ? x[n]! : ns.map((o) => x[o]!).reduce((a, b) => a + b) / ns.length;
          }

          final b = {for (final n in row) n: bary(n)};
          row.sort((p, q) => b[p]!.compareTo(b[q]!));
        }
        place();
      }
      final width = levels.values.map((r) => r.length).reduce(math.max) * sp;
      for (final n in comp) {
        g.pos[n] = Offset(offset + width / 2 + x[n]!, margin + level[n]! * lv);
      }
      offset += width + 60;
    }
    g.area = Size(math.max(600, offset - 60 + margin), math.max(600, margin * 2 + maxLevel * lv + 40));
  }

  /// Costellazione: il protagonista al centro, i legami diretti intorno,
  /// i compagni di gruppo su un anello più esterno vicino all'insegna del gruppo.
  void _ringLayout(_GraphPage g, String root, List<String> ring1, Map<String, String> ring2) {
    final r1 = 260.0 + ring1.length * 6, r2 = r1 + 210;
    final size = (r2 + 190) * 2;
    final c = Offset(size / 2, size / 2);
    g.area = Size(size, size);
    g.pos[root] = c;
    final ang = <String, double>{};
    for (var i = 0; i < ring1.length; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / ring1.length;
      ang[ring1[i]] = a;
      g.pos[ring1[i]] = c + Offset(math.cos(a), math.sin(a)) * r1;
    }
    final byGroup = <String, List<String>>{};
    ring2.forEach((id, grp) => byGroup.putIfAbsent(grp, () => []).add(id));
    final slot = 2 * math.pi / math.max(1, ring1.length);
    byGroup.forEach((grp, members) {
      final base = ang[grp] ?? 0;
      final spread = math.min(slot * 0.9, members.length * 0.28);
      for (var i = 0; i < members.length; i++) {
        final a = members.length == 1 ? base : base - spread / 2 + spread * i / (members.length - 1);
        final rr = r2 + (i.isOdd ? 70 : 0);
        g.pos[members[i]] = c + Offset(math.cos(a), math.sin(a)) * rr;
      }
    });
  }

  // ---------------- vista ----------------

  /// Centra il grafo e lo adatta allo schermo.
  void _fit(_GraphPage g, Size view) {
    if (g.pos.isEmpty || g.fittedFor == view) return;
    g.fittedFor = view;
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in g.pos.values) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    final bw = (maxX - minX) + 180, bh = (maxY - minY) + 220;
    final sc = math.min(1.3, math.min(view.width / bw, view.height / bh)).clamp(0.35, 1.3).toDouble();
    // Se l'albero è più largo dello schermo parte dall'alto, centrato sul protagonista.
    final focus = (sc <= 0.35 && _root != null && g.pos[_root] != null) ? g.pos[_root]! : Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final cy = sc <= 0.35 ? minY + view.height / 2 / sc - 80 : (minY + maxY) / 2;
    g.tc.value = Matrix4.identity()
      ..translate(view.width / 2 - focus.dx * sc, view.height / 2 - cy * sc)
      ..scale(sc);
  }

  void _open(String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: id)));

  void _openGroup(String gid) {
    final e = _w?.find(gid.substring(2));
    if (e != null) _open(e.id);
  }

  Widget _viewer(_GraphPage g, Widget Function() content) => LayoutBuilder(builder: (context, c) {
        final view = Size(c.maxWidth, c.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) => _fit(g, view));
        return InteractiveViewer(
          transformationController: g.tc,
          constrained: false,
          minScale: 0.15,
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(400),
          child: SizedBox(width: g.area.width, height: g.area.height, child: content()),
        );
      });

  Widget _legend(Iterable<String> kinds, {required bool sky}) {
    final present = kinds.toSet();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: sky ? const Color(0xB314162A) : LK.paper.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sky ? const Color(0x40E2C46B) : LK.parchmentBorder),
        ),
        child: Wrap(spacing: 12, runSpacing: 4, children: [
          for (final k in _kindName.keys.where(present.contains))
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 3, color: (sky ? _kindSky : _kindInk)[k]),
              const SizedBox(width: 5),
              Text(_kindName[k]!, style: LK.body(11.5, color: sky ? const Color(0xFFCFC6A4) : LK.parchmentInk, style: FontStyle.italic)),
            ]),
        ]),
      ),
    );
  }

  Widget _banner(String gid, {required bool sky}) {
    final name = gid.substring(2);
    return GestureDetector(
      onTap: () => _openGroup(gid),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: sky ? const Color(0xE614162A) : LK.paper,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: sky ? const Color(0xFFE2C46B) : _kindInk['speciale']!, width: 1.4),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Text(name.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: LK.label(10, color: sky ? const Color(0xFFE2C46B) : _kindInk['speciale']!, spacing: 1.4)),
      ),
    );
  }

  // ---------------- Costellazione ----------------
  Widget _constellation() {
    final w = _w!;
    final maxM = math.max(1, _mentions.values.fold<int>(0, math.max));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const RadialGradient(center: Alignment(0, -0.3), radius: 1.2, colors: [Color(0xFF2A2E5A), Color(0xFF191B36), Color(0xFF0E0F1F)], stops: [0, 0.55, 1]),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _StarfieldPainter())),
          if (_sky.pos.isEmpty)
            _waiting(sky: true)
          else
            Positioned.fill(
              child: _viewer(_sky, () => Stack(children: [
                    Positioned.fill(child: CustomPaint(painter: _SkyLinePainter(_sky.pos, _sky.edges, _selected))),
                    for (final entry in _sky.pos.entries)
                      if (_isGroup(entry.key))
                        Positioned(left: entry.value.dx - 80, top: entry.value.dy - 14, width: 160, child: Center(child: _banner(entry.key, sky: true)))
                      else
                        _star(w.entries[entry.key]!, entry.value, entry.key == _root ? 1 : (_mentions[entry.key] ?? 0) / maxM),
                  ])),
            ),
          if (_sky.pos.isNotEmpty) Positioned(left: 10, right: 10, top: 10, child: _legend(_sky.edges.map((e) => e.kind), sky: true)),
          if (_selected != null && w.entries[_selected] != null) Positioned(left: 12, right: 12, bottom: 12, child: _starCard(w.entries[_selected]!)),
        ]),
      ),
    );
  }

  Widget _star(WikiEntry e, Offset p, double weight) {
    final glow = 26.0 + 46 * weight;
    final sel = e.id == _selected;
    return Positioned(
      left: p.dx - 70,
      top: p.dy - glow / 2,
      width: 140,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = sel ? null : e.id),
        child: Column(children: [
          SizedBox(
            width: glow,
            height: glow,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFFF6D6),
                  const Color(0xFFF7D27A).withValues(alpha: sel ? 1 : 0.85),
                  const Color(0x00F7D27A),
                ], stops: const [0.08, 0.35, 1]),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(e.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: LK.display(12 + 4 * weight, color: weight > 0.5 || sel ? const Color(0xFFF7E08A) : const Color(0xFFCFC6A4)).copyWith(fontStyle: FontStyle.italic)),
        ]),
      ),
    );
  }

  Widget _starCard(WikiEntry e) {
    final n = _all.edges.where((r) => r.a == e.id || r.b == e.id).length;
    final role = e.roleAt(WikiStore.I.limitFor(widget.book));
    return GestureDetector(
      onTap: () => _open(e.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xD114162A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x59E2C46B)),
        ),
        child: Row(children: [
          Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE2C46B), width: 2)),
            child: WikiAvatar(e, size: 36),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(e.name, style: LK.display(15, color: const Color(0xFFF2E6C8))),
              Text([if (role.isNotEmpty) role, '$n ${n == 1 ? 'legame' : 'legami'}'].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(11.5, color: const Color(0xFFA9A6C4), style: FontStyle.italic)),
            ]),
          ),
          Text('SCHEDA ›', style: LK.label(10, color: const Color(0xFFE2B84B), spacing: 1)),
        ]),
      ),
    );
  }

  // ---------------- Tutti i legami: albero a inchiostro ----------------
  Widget _inkTree() {
    final w = _w!;
    if (_all.pos.isEmpty) return _waiting(sky: false);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: LK.parchment,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LK.parchmentBorder, width: 1.4),
        image: const DecorationImage(image: AssetImage('assets/textures/parchment.png'), repeat: ImageRepeat.repeat, opacity: 0.9, scale: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(children: [
          Positioned.fill(
            child: _viewer(_all, () => Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _EdgePainter(_all.pos, _all.edges, LK.parchmentInk, LK.paper))),
                  for (final entry in _all.pos.entries)
                    if (_isGroup(entry.key))
                      Positioned(left: entry.value.dx - 80, top: entry.value.dy - 14, width: 160, child: Center(child: _banner(entry.key, sky: false)))
                    else
                      Positioned(
                        left: entry.value.dx - 55,
                        top: entry.value.dy - 30,
                        width: 110,
                        child: GestureDetector(
                          onTap: () => _open(entry.key),
                          child: Column(children: [
                            Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: entry.key == _root ? LK.gold : LK.accent, width: entry.key == _root ? 3 : 2)),
                              child: WikiAvatar(w.entries[entry.key]!, size: 44),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: LK.paper.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(6)),
                              child: Text(w.entries[entry.key]!.name, textAlign: TextAlign.center, maxLines: 2, style: LK.body(12)),
                            ),
                          ]),
                        ),
                      ),
                ])),
          ),
          Positioned(left: 10, right: 10, bottom: 10, child: _legend(_all.edges.map((e) => e.kind), sky: false)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BackLink(trail: 'Wiki'),
              Text(_page == 0 ? 'La costellazione' : 'Tutti i legami', style: LK.display(26)),
              const SizedBox(height: 4),
              Text(
                  _page == 0
                      ? 'Il protagonista e i suoi legami. Più una stella è luminosa, più compare nella storia.'
                      : 'Ogni personaggio e ogni legame, ad albero. Trascina e allarga con due dita; tocca un nome per la scheda.',
                  style: LK.body(13, color: LK.muted)),
              const SizedBox(height: 10),
              Center(
                child: Segmented(
                  labels: const ['Costellazione', 'Tutti i legami'],
                  selected: _page,
                  onChanged: (i) => setState(() => _page = i),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: w == null
                ? Center(child: CircularProgressIndicator(color: LK.accent))
                : IndexedStack(index: _page, children: [_constellation(), _inkTree()]),
          ),
        ]),
      ),
    );
  }
}

/// Puntini di stelle lontane sullo sfondo.
class _StarfieldPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final rnd = math.Random(7);
    final p = Paint();
    for (var i = 0; i < 160; i++) {
      p.color = Colors.white.withValues(alpha: 0.25 + rnd.nextDouble() * 0.55);
      c.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height), 0.4 + rnd.nextDouble() * 0.9, p);
    }
    final neb = Paint()
      ..shader = RadialGradient(colors: [const Color(0xFF5E3F94).withValues(alpha: 0.32), const Color(0x005E3F94)])
          .createShader(Rect.fromCircle(center: Offset(s.width * 0.3, s.height * 0.72), radius: s.width * 0.8));
    c.drawRect(Offset.zero & s, neb);
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => false;
}

void _dashed(Canvas c, Path path, Paint paint, {double on = 7, double off = 5}) {
  for (final m in path.computeMetrics()) {
    for (double t = 0; t < m.length; t += on + off) {
      c.drawPath(m.extractPath(t, math.min(t + on, m.length)), paint);
    }
  }
}

void _label(Canvas c, Path path, String text, TextStyle style, Color? bg) {
  final ms = path.computeMetrics().toList();
  if (ms.isEmpty) return;
  final t = ms.first.getTangentForOffset(ms.first.length / 2);
  if (t == null) return;
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: 120);
  final o = t.position - Offset(tp.width / 2, tp.height / 2);
  if (bg != null) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 4, o.dy - 1, tp.width + 8, tp.height + 2), const Radius.circular(5)), Paint()..color = bg);
  }
  tp.paint(c, o);
  tp.dispose();
}

/// Linee nel cielo, colorate per tipo di legame.
class _SkyLinePainter extends CustomPainter {
  final Map<String, Offset> pos;
  final List<_Edge> edges;
  final String? selected;
  _SkyLinePainter(this.pos, this.edges, this.selected);

  @override
  void paint(Canvas c, Size s) {
    for (final e in edges) {
      final a = pos[e.a], b = pos[e.b];
      if (a == null || b == null) continue;
      final hi = selected == null || e.a == selected || e.b == selected;
      final col = _kindSky[e.kind] ?? _kindSky['alleanza']!;
      final paint = Paint()
        ..color = col.withValues(alpha: hi ? 0.75 : 0.2)
        ..strokeWidth = hi ? 1.4 : 1
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
      if (e.label == null) {
        _dashed(c, path, paint, on: 4, off: 4);
      } else {
        c.drawPath(path, paint);
        _label(c, path, e.label!, LK.body(11, color: const Color(0xFFD9D4F0).withValues(alpha: hi ? 1 : 0.35), style: FontStyle.italic), const Color(0xB3191B36));
      }
    }
  }

  @override
  bool shouldRepaint(_SkyLinePainter old) => old.selected != selected || old.edges != edges;
}

/// Rami a inchiostro: curve verticali tratteggiate, colorate per tipo di legame.
class _EdgePainter extends CustomPainter {
  final Map<String, Offset> pos;
  final List<_Edge> edges;
  final Color text, bg;
  _EdgePainter(this.pos, this.edges, this.text, this.bg);

  Offset _anchor(String id) => _isGroup(id) ? pos[id]! : pos[id]! + const Offset(0, -8);

  @override
  void paint(Canvas c, Size s) {
    for (final e in edges) {
      if (pos[e.a] == null || pos[e.b] == null) continue;
      final a = _anchor(e.a), b = _anchor(e.b);
      final paint = Paint()
        ..color = (_kindInk[e.kind] ?? _kindInk['alleanza']!).withValues(alpha: LK.dark ? 0.95 : 0.85)
        ..strokeWidth = e.label == null ? 1.6 : 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(a.dx, a.dy);
      if ((a.dy - b.dy).abs() < 1) {
        path.lineTo(b.dx, b.dy);
      } else {
        final my = (a.dy + b.dy) / 2;
        path.cubicTo(a.dx, my, b.dx, my, b.dx, b.dy);
      }
      if (e.label == null) {
        c.drawPath(path, paint);
      } else {
        _dashed(c, path, paint);
        _label(c, path, e.label!, LK.body(11, color: text, style: FontStyle.italic), bg.withValues(alpha: 0.8));
      }
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}


// ======================================================================
// Elementi grafici: pergamena, sigillo di ceralacca, ritratto ovale
// ======================================================================

class ParchmentCard extends StatelessWidget {
  final Widget child;
  final String? seal;
  const ParchmentCard({super.key, required this.child, this.seal});

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: LK.parchment,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: LK.parchmentBorder, width: 1.4),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 6))],
          image: const DecorationImage(image: AssetImage('assets/textures/parchment.png'), repeat: ImageRepeat.repeat, opacity: 0.9, scale: 2),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: LK.parchmentBorder, width: 0.8)),
          child: child,
        ),
      ),
      if (seal != null && seal!.isNotEmpty) Positioned(right: 14, top: -14, child: WaxSeal(letter: seal!.characters.first.toUpperCase())),
    ]);
  }
}

class WaxSeal extends StatelessWidget {
  final String letter;
  final double size;
  const WaxSeal({super.key, required this.letter, this.size = 58});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SealPainter(),
          child: Center(
            child: Text(letter, style: LK.display(size * 0.42, color: const Color(0xFFF2C6B4)).copyWith(shadows: const [Shadow(color: Color(0x88000000), offset: Offset(0, 1), blurRadius: 1)])),
          ),
        ),
      );
}

class _SealPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2;
    final blob = Path();
    for (var i = 0; i <= 48; i++) {
      final a = i / 48 * 2 * math.pi;
      final rr = r * (0.92 + 0.08 * math.sin(a * 7) * math.cos(a * 3));
      final p = ctr + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? blob.moveTo(p.dx, p.dy) : blob.lineTo(p.dx, p.dy);
    }
    blob.close();
    c.drawShadow(blob, Colors.black, 3, false);
    c.drawPath(
      blob,
      Paint()
        ..shader = RadialGradient(colors: const [Color(0xFFC0392B), Color(0xFF8E1B14), Color(0xFF5E0E0A)], stops: const [0, 0.7, 1])
            .createShader(Rect.fromCircle(center: ctr - Offset(r * 0.25, r * 0.25), radius: r * 1.3)),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x66000000);
    c.drawCircle(ctr, r * 0.66, ring);
    c.drawCircle(ctr + const Offset(0, 1), r * 0.66, ring..color = const Color(0x33FFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OvalPortrait extends StatelessWidget {
  final Widget child;
  final double width, height;
  const OvalPortrait({super.key, required this.child, required this.width, required this.height});

  @override
  Widget build(BuildContext context) => Container(
        width: width + 10,
        height: height + 10,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.all(Radius.elliptical((width + 10) / 2, (height + 10) / 2)),
          gradient: const LinearGradient(colors: [Color(0xFFF7E08A), Color(0xFFC9A55A), Color(0xFF8A6A2A), Color(0xFFE2C46B)]),
          boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: ClipOval(child: SizedBox(width: width, height: height, child: child)),
      );
}
