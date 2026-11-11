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
          banner = 'Gemini sta leggendo i capitoli… ${st.done}/${st.total}';
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
                    itemBuilder: (_) => [PopupMenuItem(value: 'rebuild', child: Text('Rigenera wiki', style: LK.body(14)))],
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
          for (final e in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: LK.card,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: b, entryId: e.id))),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.line)),
                    child: Row(children: [
                      WikiAvatar(e),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.name, style: LK.display(16)),
                          if (e.roleAt(limit).isNotEmpty || e.manual)
                            Text(e.manual ? (e.manualText ?? '') : e.roleAt(limit),
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.body(13, color: LK.muted)),
                          Text(e.manual ? 'AGGIUNTA DA TE' : _where(b, e.first), style: LK.label(9, spacing: 1)),
                        ]),
                      ),
                      Icon(Icons.chevron_right, color: LK.border),
                    ]),
                  ),
                ),
              ),
            ),
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
              _stat('PRIMA APPARIZIONE', e.manual ? '—' : _where(b, e.first).toLowerCase().replaceAll('cap.', 'Cap.').replaceAll('vol.', 'Vol.')),
              const SizedBox(width: 8),
              _stat('CAPITOLI', '$mentions'),
              const SizedBox(width: 8),
              _stat('RELAZIONI', '${rels.length}'),
            ]),
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
            if (notes.isNotEmpty && e.descriptionAt(limit).isNotEmpty)
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

/// Colori dei tipi di legame (pagina "Tutti i legami").
const _kindColors = <String, Color>{
  'famiglia': Color(0xFF7A1E2E),
  'amore': Color(0xFFB0456A),
  'amicizia': Color(0xFF3E6B4A),
  'alleanza': Color(0xFF2F4A6A),
  'rivalità': Color(0xFFB0561E),
  'altro': Color(0xFF6B4A2E),
};

class _GraphPage {
  final Map<String, Offset> pos = {};
  List<WikiRelation> rels = const [];
  final tc = TransformationController();
  Size? fittedFor;
}

class _GraphScreenState extends State<GraphScreen> {
  static const _area = 1400.0;
  Wiki? _w;
  int _page = 0;
  final _sky = _GraphPage(), _all = _GraphPage();
  final Map<String, int> _mentions = {};
  String? _selected;

  @override
  void initState() {
    super.initState();
    WikiStore.I.forBook(widget.book).then((w) {
      if (!mounted) return;
      _w = w;
      final limit = WikiStore.I.limitFor(widget.book);
      final rels = w.relationsAt(limit).where((r) => w.entries[r.a] != null && w.entries[r.b] != null).toList();
      for (final e in w.entries.values) {
        _mentions[e.id] = e.notesAt(limit).map((n) => '${n.bookId}:${n.chapter}').toSet().length;
      }
      _sky.rels = rels.where((r) => r.close).toList();
      _all.rels = rels;
      _layout(_sky);
      _layout(_all);
      if (_sky.pos.isEmpty && _all.pos.isNotEmpty) _page = 1;
      setState(() {});
    });
  }

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
    final bw = (maxX - minX) + 180, bh = (maxY - minY) + 200;
    final sc = math.min(1.4, math.min(view.width / bw, view.height / bh));
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    g.tc.value = Matrix4.identity()
      ..translate(view.width / 2 - cx * sc, view.height / 2 - cy * sc)
      ..scale(sc);
  }

  /// Disposizione a molle (Fruchterman–Reingold).
  void _layout(_GraphPage g) {
    final ids = <String>{for (final r in g.rels) ...[r.a, r.b]}.toList();
    final n = ids.length;
    if (n == 0) return;
    final rnd = math.Random(42);
    final pos = {for (var i = 0; i < n; i++) ids[i]: Offset(_area / 2 + math.cos(i * 2 * math.pi / n) * 400 + rnd.nextDouble(), _area / 2 + math.sin(i * 2 * math.pi / n) * 400)};
    final k = math.sqrt(_area * _area / n) * 0.55;
    var temp = _area / 8;
    for (var it = 0; it < 250; it++) {
      final disp = {for (final id in ids) id: Offset.zero};
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final d = pos[ids[i]]! - pos[ids[j]]!;
          final dist = math.max(d.distance, 0.01);
          final f = d / dist * (k * k / dist);
          disp[ids[i]] = disp[ids[i]]! + f;
          disp[ids[j]] = disp[ids[j]]! - f;
        }
      }
      for (final r in g.rels) {
        if (!pos.containsKey(r.a) || !pos.containsKey(r.b)) continue;
        final d = pos[r.a]! - pos[r.b]!;
        final dist = math.max(d.distance, 0.01);
        final f = d / dist * (dist * dist / k);
        disp[r.a] = disp[r.a]! - f;
        disp[r.b] = disp[r.b]! + f;
      }
      for (final id in ids) {
        final d = disp[id]!;
        final len = math.max(d.distance, 0.01);
        var np = pos[id]! + d / len * math.min(len, temp);
        np = np + (const Offset(_area / 2, _area / 2) - np) * 0.01;
        pos[id] = Offset(np.dx.clamp(90, _area - 90), np.dy.clamp(90, _area - 90));
      }
      temp *= 0.97;
    }
    g.pos
      ..clear()
      ..addAll(pos);
  }

  void _open(String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: id)));

  Widget _viewer(_GraphPage g, Widget Function() content) => LayoutBuilder(builder: (context, c) {
        final view = Size(c.maxWidth, c.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) => _fit(g, view));
        return InteractiveViewer(
          transformationController: g.tc,
          constrained: false,
          minScale: 0.2,
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(400),
          child: SizedBox(width: _area, height: _area, child: content()),
        );
      });

  Widget _empty(String text, {Color? color}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(text, textAlign: TextAlign.center, style: LK.body(15, color: color ?? LK.muted, style: FontStyle.italic)),
        ),
      );

  // ---------------- Costellazione: famiglia, amori, amicizie ----------------
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
            _empty('Ancora nessun legame di famiglia, amore o amicizia: compariranno man mano che leggi.', color: const Color(0xFFA9A6C4))
          else
            Positioned.fill(
              child: _viewer(_sky, () => Stack(children: [
                    Positioned.fill(child: CustomPaint(painter: _SkyLinePainter(_sky.pos, _sky.rels, _selected))),
                    for (final entry in _sky.pos.entries) _star(w.entries[entry.key]!, entry.value, (_mentions[entry.key] ?? 0) / maxM),
                  ])),
            ),
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
    final n = _all.rels.where((r) => r.a == e.id || r.b == e.id).length;
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
    if (_all.pos.isEmpty) return _empty('Nessuna relazione ancora: compariranno man mano che leggi.');
    final kinds = _all.rels.map((r) => r.kind).toSet();
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
                  Positioned.fill(child: CustomPaint(painter: _EdgePainter(_all.pos, _all.rels, LK.parchmentInk))),
                  for (final entry in _all.pos.entries)
                    Positioned(
                      left: entry.value.dx - 50,
                      top: entry.value.dy - 30,
                      width: 100,
                      child: GestureDetector(
                        onTap: () => _open(entry.key),
                        child: Column(children: [
                          Container(
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: LK.accent, width: 2)),
                            child: WikiAvatar(w.entries[entry.key]!, size: 44),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: LK.paper.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
                            child: Text(w.entries[entry.key]!.name, textAlign: TextAlign.center, maxLines: 2, style: LK.body(12)),
                          ),
                        ]),
                      ),
                    ),
                ])),
          ),
          // Legenda dei colori
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: LK.paper.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(8), border: Border.all(color: LK.parchmentBorder)),
                child: Wrap(spacing: 12, runSpacing: 4, children: [
                  for (final k in _kindColors.keys.where(kinds.contains))
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 14, height: 3, color: _kindColors[k]),
                      const SizedBox(width: 5),
                      Text(k, style: LK.body(11.5, color: LK.parchmentInk, style: FontStyle.italic)),
                    ]),
                ]),
              ),
            ),
          ),
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
                      ? 'Famiglia, amori e amicizie. Più una stella è luminosa, più compare nella storia.'
                      : 'Ogni personaggio e ogni legame. Trascina e allarga con due dita; tocca un nome per la scheda.',
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

/// Linee dorate tra le stelle, con il nome del legame.
class _SkyLinePainter extends CustomPainter {
  final Map<String, Offset> pos;
  final List<WikiRelation> rels;
  final String? selected;
  _SkyLinePainter(this.pos, this.rels, this.selected);

  @override
  void paint(Canvas c, Size s) {
    final drawn = <String>{};
    for (final r in rels) {
      final a = pos[r.a], b = pos[r.b];
      if (a == null || b == null) continue;
      final hi = selected == null || r.a == selected || r.b == selected;
      final paint = Paint()
        ..color = const Color(0xFFE2C46B).withValues(alpha: hi ? 0.6 : 0.18)
        ..strokeWidth = hi ? 1.3 : 1;
      c.drawLine(a, b, paint);
      final key = '${r.a}|${r.b}';
      if (drawn.contains(key)) continue;
      drawn.add(key);
      final tp = TextPainter(
        text: TextSpan(text: r.label, style: LK.body(11, color: const Color(0xFFB9B4D8).withValues(alpha: hi ? 1 : 0.35), style: FontStyle.italic)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 110);
      tp.paint(c, (a + b) / 2 - Offset(tp.width / 2, tp.height + 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_SkyLinePainter old) => old.selected != selected || old.rels != rels;
}

/// Linee a inchiostro tratteggiate, colorate per tipo di legame.
class _EdgePainter extends CustomPainter {
  final Map<String, Offset> pos;
  final List<WikiRelation> rels;
  final Color text;
  _EdgePainter(this.pos, this.rels, this.text);

  @override
  void paint(Canvas c, Size s) {
    final drawn = <String>{};
    for (final r in rels) {
      final a = pos[r.a], b = pos[r.b];
      if (a == null || b == null) continue;
      final paint = Paint()
        ..color = (_kindColors[r.kind] ?? _kindColors['altro']!).withValues(alpha: LK.dark ? 0.9 : 0.8)
        ..strokeWidth = r.close ? 2 : 1.5
        ..strokeCap = StrokeCap.round;
      final ca = a + const Offset(0, -8), cb = b + const Offset(0, -8);
      final d = cb - ca;
      final len = d.distance;
      if (len < 1) continue;
      final dir = d / len;
      for (double t = 0; t < len; t += 11) {
        final e = math.min(t + 6, len);
        c.drawLine(ca + dir * t, ca + dir * e, paint);
      }
      final key = '${r.a}|${r.b}';
      if (drawn.contains(key)) continue;
      drawn.add(key);
      final tp = TextPainter(
        text: TextSpan(text: r.label, style: LK.body(11, color: text, style: FontStyle.italic)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 110);
      final mid = (ca + cb) / 2 - Offset(tp.width / 2, tp.height / 2);
      tp.paint(c, mid);
      tp.dispose();
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
