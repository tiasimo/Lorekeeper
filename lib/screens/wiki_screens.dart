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
            if (e.descriptionAt(limit).isNotEmpty)
              Text(e.descriptionAt(limit), style: LK.body(15.5, height: 1.65))
            else if (notes.isEmpty && (e.manualText == null || e.manualText!.isEmpty))
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

class _GraphScreenState extends State<GraphScreen> {
  static const _area = 1400.0;
  Wiki? _w;
  final Map<String, Offset> _pos = {};
  List<WikiRelation> _rels = const [];
  final _tc = TransformationController();
  Size? _fittedFor;

  /// Centra il grafo e lo adatta allo schermo.
  void _fit(Size view) {
    if (_pos.isEmpty || _fittedFor == view) return;
    _fittedFor = view;
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in _pos.values) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    final bw = (maxX - minX) + 160, bh = (maxY - minY) + 160;
    final sc = math.min(1.4, math.min(view.width / bw, view.height / bh));
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    _tc.value = Matrix4.identity()
      ..translate(view.width / 2 - cx * sc, view.height / 2 - cy * sc)
      ..scale(sc);
  }

  @override
  void initState() {
    super.initState();
    WikiStore.I.forBook(widget.book).then((w) {
      if (!mounted) return;
      _w = w;
      _layout();
      setState(() {});
    });
  }

  /// Disposizione a molle (Fruchterman–Reingold).
  void _layout() {
    final w = _w!;
    final limit = WikiStore.I.limitFor(widget.book);
    _rels = w.relationsAt(limit);
    final ids = <String>{for (final r in _rels) ...[r.a, r.b]}.where((id) => w.entries[id] != null).toList();
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
      for (final r in _rels) {
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
        // leggera attrazione verso il centro
        np = np + (const Offset(_area / 2, _area / 2) - np) * 0.01;
        pos[id] = Offset(np.dx.clamp(80, _area - 80), np.dy.clamp(80, _area - 80));
      }
      temp *= 0.97;
    }
    _pos
      ..clear()
      ..addAll(pos);
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
              Text('Grafo delle relazioni', style: LK.display(26)),
              const SizedBox(height: 4),
              Text('Trascina e allarga con due dita. Tocca un nome per aprire la scheda.', style: LK.body(13, color: LK.muted)),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: w == null
                ? Center(child: CircularProgressIndicator(color: LK.accent))
                : _pos.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Text('Nessuna relazione ancora: compariranno man mano che leggi.',
                              textAlign: TextAlign.center, style: LK.body(15, color: LK.muted, style: FontStyle.italic)),
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        decoration: BoxDecoration(
                          color: LK.parchment,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: LK.parchmentBorder, width: 1.4),
                          image: const DecorationImage(image: AssetImage('assets/textures/parchment.png'), repeat: ImageRepeat.repeat, opacity: 0.9, scale: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: LayoutBuilder(builder: (context, c) {
                            final view = Size(c.maxWidth, c.maxHeight);
                            WidgetsBinding.instance.addPostFrameCallback((_) => _fit(view));
                            return InteractiveViewer(
                        transformationController: _tc,
                        constrained: false,
                        minScale: 0.2,
                        maxScale: 2.5,
                        boundaryMargin: const EdgeInsets.all(400),
                        child: SizedBox(
                          width: _area,
                          height: _area,
                          child: Stack(children: [
                            Positioned.fill(child: CustomPaint(painter: _EdgePainter(_pos, _rels, LK.dark ? const Color(0xFFB59A72) : const Color(0xFF6B4A2E), LK.parchmentInk))),
                            for (final entry in _pos.entries)
                              Positioned(
                                left: entry.value.dx - 50,
                                top: entry.value.dy - 30,
                                width: 100,
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: entry.key))),
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
                          ]),
                        ),
                      );
                          }),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final Map<String, Offset> pos;
  final List<WikiRelation> rels;
  final Color line, text;
  _EdgePainter(this.pos, this.rels, this.line, this.text);

  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final drawn = <String>{};
    for (final r in rels) {
      final a = pos[r.a], b = pos[r.b];
      if (a == null || b == null) continue;
      final ca = a + const Offset(0, -8), cb = b + const Offset(0, -8);
      // linea a inchiostro tratteggiata, come su una vecchia mappa
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
