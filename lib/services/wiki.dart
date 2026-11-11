import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import 'epub.dart';
import 'gemini.dart';
import 'hyphen.dart';
import 'library_store.dart';
import 'secrets.dart';

/// Posizione nella serie: volume * 100000 + capitolo. Serve per l'anti-spoiler.
int wikiPos(Book b, int chapter) => ((b.seriesIndex ?? 0) * 100000).round() + chapter;

class WikiNote {
  final int pos;
  final String text;
  final String bookId;
  final int chapter;
  const WikiNote(this.pos, this.text, this.bookId, this.chapter);
  Map<String, dynamic> toJson() => {'p': pos, 't': text, 'b': bookId, 'c': chapter};
  factory WikiNote.fromJson(Map j) => WikiNote(j['p'] as int, j['t'] as String, (j['b'] as String?) ?? '', (j['c'] as int?) ?? 0);
}

class WikiEntry {
  final String id;
  String name;
  String type; // personaggio | luogo | termine
  final Set<String> aliases;
  final List<WikiNote> notes; // informazioni emerse capitolo per capitolo
  final List<WikiNote> roles; // ruolo/descrizione breve nel tempo
  final List<WikiNote> descriptions; // scheda completa, riscritta a ogni capitolo (versioni)
  String? photo; // percorso locale
  String myNotes;
  bool manual; // creata a mano
  String? manualText;

  WikiEntry({
    required this.id,
    required this.name,
    required this.type,
    Set<String>? aliases,
    List<WikiNote>? notes,
    List<WikiNote>? roles,
    List<WikiNote>? descriptions,
    this.photo,
    this.myNotes = '',
    this.manual = false,
    this.manualText,
  })  : aliases = aliases ?? {},
        notes = notes ?? [],
        roles = roles ?? [],
        descriptions = descriptions ?? [];

  int get firstPos => manual ? -1 : (notes.isEmpty ? (roles.isEmpty ? 1 << 40 : roles.first.pos) : notes.map((n) => n.pos).reduce((a, b) => a < b ? a : b));

  bool visibleAt(int limit) => manual || firstPos <= limit;
  List<WikiNote> notesAt(int limit) => notes.where((n) => n.pos <= limit).toList()..sort((a, b) => a.pos.compareTo(b.pos));
  String roleAt(int limit) {
    final r = roles.where((n) => n.pos <= limit).toList()..sort((a, b) => a.pos.compareTo(b.pos));
    return r.isEmpty ? '' : r.last.text;
  }

  /// Scheda completa fino al limite anti-spoiler.
  String descriptionAt(int limit) {
    final d = descriptions.where((n) => n.pos <= limit).toList()..sort((a, b) => a.pos.compareTo(b.pos));
    return d.isEmpty ? '' : d.last.text;
  }

  WikiNote? get first {
    if (notes.isEmpty) return null;
    return (notes.toList()..sort((a, b) => a.pos.compareTo(b.pos))).first;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'aliases': aliases.toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'roles': roles.map((n) => n.toJson()).toList(),
        'descriptions': descriptions.map((n) => n.toJson()).toList(),
        'photo': photo,
        'myNotes': myNotes,
        'manual': manual,
        'manualText': manualText,
      };

  factory WikiEntry.fromJson(Map j) => WikiEntry(
        id: j['id'] as String,
        name: j['name'] as String,
        type: (j['type'] as String?) ?? 'personaggio',
        aliases: ((j['aliases'] as List?) ?? []).cast<String>().toSet(),
        notes: ((j['notes'] as List?) ?? []).map((n) => WikiNote.fromJson(n as Map)).toList(),
        roles: ((j['roles'] as List?) ?? []).map((n) => WikiNote.fromJson(n as Map)).toList(),
        descriptions: ((j['descriptions'] as List?) ?? []).map((n) => WikiNote.fromJson(n as Map)).toList(),
        photo: j['photo'] as String?,
        myNotes: (j['myNotes'] as String?) ?? '',
        manual: (j['manual'] as bool?) ?? false,
        manualText: j['manualText'] as String?,
      );
}

class WikiRelation {
  final String a, b, label;
  final int pos;
  const WikiRelation(this.a, this.b, this.label, this.pos);
  Map<String, dynamic> toJson() => {'a': a, 'b': b, 'l': label, 'p': pos};
  factory WikiRelation.fromJson(Map j) => WikiRelation(j['a'] as String, j['b'] as String, j['l'] as String, j['p'] as int);
}

class Wiki {
  final String key;
  final String title;
  final Map<String, WikiEntry> entries = {};
  final List<WikiRelation> relations = [];
  final Set<String> processed = {}; // "idLibro:capitolo"
  final Map<String, String> summaries = {}; // "idLibro:capitolo" → riassunto

  Wiki(this.key, this.title);

  static String slug(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return t.isEmpty ? 'x' : t;
  }

  static Set<String> _tokens(String s) =>
      s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((t) => t.length >= 2).toSet();

  /// Cerca una voce già presente: stesso nome o alias, oppure nome contenuto
  /// nell'altro ("Arthur" ↔ "Arthur Leywin") quando il candidato è uno solo.
  WikiEntry? find(String name, {String? type}) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final e in entries.values) {
      if (e.name.toLowerCase() == n || e.aliases.any((a) => a.toLowerCase() == n)) return e;
    }
    final tn = _tokens(n);
    if (tn.isEmpty) return null;
    final cands = <WikiEntry>[];
    for (final e in entries.values) {
      if (type != null && e.type != type) continue;
      for (final other in [e.name, ...e.aliases]) {
        final te = _tokens(other);
        if (te.isEmpty) continue;
        if (te.containsAll(tn) || tn.containsAll(te)) {
          cands.add(e);
          break;
        }
      }
    }
    return cands.length == 1 ? cands.first : null;
  }

  /// Unisce [from] dentro [into]: note, ruoli, schede, alias e relazioni.
  void mergeInto(WikiEntry from, WikiEntry into) {
    if (from.id == into.id) return;
    if (_tokens(from.name).length > _tokens(into.name).length) {
      into.aliases.add(into.name);
      into.name = from.name;
    } else {
      into.aliases.add(from.name);
    }
    into.aliases.addAll(from.aliases);
    into.aliases.removeWhere((a) => a.toLowerCase() == into.name.toLowerCase());
    into.notes.addAll(from.notes);
    into.roles.addAll(from.roles);
    if (into.descriptions.isEmpty) into.descriptions.addAll(from.descriptions);
    into.photo ??= from.photo;
    if (from.myNotes.isNotEmpty) into.myNotes = [into.myNotes, from.myNotes].where((x) => x.isNotEmpty).join('\n');
    entries.remove(from.id);
    for (var i = 0; i < relations.length; i++) {
      final r = relations[i];
      if (r.a == from.id || r.b == from.id) {
        relations[i] = WikiRelation(r.a == from.id ? into.id : r.a, r.b == from.id ? into.id : r.b, r.label, r.pos);
      }
    }
    relations.removeWhere((r) => r.a == r.b);
  }

  /// Unisce automaticamente i doppioni evidenti dello stesso tipo.
  bool mergeDuplicates() {
    var changed = false;
    var again = true;
    while (again) {
      again = false;
      final list = entries.values.where((e) => !e.manual).toList();
      outer:
      for (final a in list) {
        final ta = _tokens(a.name);
        if (ta.isEmpty) continue;
        final cands = list.where((b) {
          if (b.id == a.id || b.type != a.type) return false;
          final tb = _tokens(b.name);
          return tb.length > ta.length && tb.containsAll(ta);
        }).toList();
        if (cands.length == 1) {
          mergeInto(a, cands.first);
          changed = true;
          again = true;
          break outer;
        }
      }
    }
    return changed;
  }

  List<WikiRelation> relationsAt(int limit) => relations.where((r) => r.pos <= limit).toList();

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'entries': entries.values.map((e) => e.toJson()).toList(),
        'relations': relations.map((r) => r.toJson()).toList(),
        'processed': processed.toList(),
        'summaries': summaries,
      };

  factory Wiki.fromJson(Map j) {
    final w = Wiki(j['key'] as String, (j['title'] as String?) ?? '');
    for (final e in (j['entries'] as List? ?? [])) {
      final x = WikiEntry.fromJson(e as Map);
      w.entries[x.id] = x;
    }
    w.relations.addAll((j['relations'] as List? ?? []).map((r) => WikiRelation.fromJson(r as Map)));
    w.processed.addAll((j['processed'] as List? ?? []).cast<String>());
    w.summaries.addAll(Map<String, String>.from((j['summaries'] as Map?) ?? {}));
    return w;
  }
}

class WikiStatus {
  final bool running;
  final int done;
  final int total;
  final String? error;
  const WikiStatus({this.running = false, this.done = 0, this.total = 0, this.error});
}

/// Gestione delle wiki: una per serie (o per libro se non fa parte di una serie).
class WikiStore extends ChangeNotifier {
  WikiStore._();
  static final WikiStore I = WikiStore._();

  final Map<String, Wiki> _cache = {};
  final Map<String, WikiStatus> status = {};
  final Set<String> _running = {};
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static String keyFor(Book b) => b.series != null && b.series!.trim().isNotEmpty ? 's_${Wiki.slug(b.series!)}' : 'b_${b.id}';

  Directory get _dir => Directory(p.join(LibraryStore.I.dataDir, 'wiki'));

  Future<Wiki> forBook(Book b) async {
    final key = keyFor(b);
    final c = _cache[key];
    if (c != null) return c;
    await _dir.create(recursive: true);
    final f = File(p.join(_dir.path, '$key.json'));
    Wiki w;
    if (await f.exists()) {
      try {
        w = Wiki.fromJson(jsonDecode(await f.readAsString()) as Map);
      } catch (_) {
        w = Wiki(key, b.series ?? b.title);
      }
    } else {
      w = Wiki(key, b.series ?? b.title);
    }
    _cache[key] = w;
    if (w.mergeDuplicates()) await save(w);
    return w;
  }

  Wiki? cached(Book b) => _cache[keyFor(b)];

  Future<void> save(Wiki w) async {
    await _dir.create(recursive: true);
    final f = File(p.join(_dir.path, '${w.key}.json'));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(w.toJson()));
    await tmp.rename(f.path);
    notifyListeners();
  }

  String photoDir() => _dir.path;

  /// Limite anti-spoiler per il libro, in base all'impostazione scelta.
  int limitFor(Book b) {
    final mode = LibraryStore.I.app.spoiler;
    final vol = ((b.seriesIndex ?? 0) * 100000).round();
    if (mode == 'Libro') return vol + 99999;
    final c = b.lastChapter;
    if (mode == 'Capitolo') return vol + c;
    return b.lastOffset >= 0.9 ? vol + c : vol + c - 1;
  }

  /// Capitolo fino al quale serve estrarre per questo libro.
  int targetChapter(Book b) => LibraryStore.I.app.spoiler == 'Libro' ? b.chapters.length - 1 : b.lastChapter;

  int pending(Wiki w, Book b, int upTo) {
    var n = 0;
    for (var i = 0; i <= upTo && i < b.chapters.length; i++) {
      if (!w.processed.contains('${b.id}:$i')) n++;
    }
    return n;
  }

  /// Estrae in sottofondo i capitoli mancanti fino a [upTo] (compreso).
  Future<void> ensure(Book b, {int? upTo, bool silent = true}) async {
    final key = keyFor(b);
    if (_running.contains(key)) return;
    final k = await Secrets.geminiKey();
    if (k == null || k.isEmpty) {
      if (!silent) {
        status[key] = const WikiStatus(error: 'Aggiungi la chiave API di Gemini in Impostazioni per creare la wiki.');
        notifyListeners();
      }
      return;
    }
    final w = await forBook(b);
    final last = (upTo ?? targetChapter(b)).clamp(0, b.chapters.length - 1);
    final todo = <int>[
      for (var i = 0; i <= last; i++)
        if (!w.processed.contains('${b.id}:$i')) i
    ];
    if (todo.isEmpty) return;
    _running.add(key);
    final epub = await _open(b);
    if (epub == null) {
      _running.remove(key);
      status[key] = const WikiStatus(error: 'Non riesco ad aprire il libro.');
      notifyListeners();
      return;
    }
    var done = 0;
    status[key] = WikiStatus(running: true, done: 0, total: todo.length);
    notifyListeners();
    try {
      for (final i in todo) {
        final text = epub
            .chapterParas(b.chapters[i])
            .where((p) => p.image == null)
            .map((p) => p.plain.replaceAll(Hyphen.soft, ''))
            .join('\n');
        if (text.trim().length < 200) {
          w.processed.add('${b.id}:$i');
        } else {
          await _extract(w, b, i, text);
        }
        done++;
        _reattach(w);
        status[key] = WikiStatus(running: true, done: done, total: todo.length);
        await save(w);
      }
      status[key] = WikiStatus(done: done, total: todo.length);
    } on GeminiError catch (e) {
      status[key] = WikiStatus(done: done, total: todo.length, error: e.message);
    } catch (e) {
      status[key] = WikiStatus(done: done, total: todo.length, error: 'Errore durante la creazione della wiki: $e');
    } finally {
      _running.remove(key);
      notifyListeners();
    }
  }

  Future<Epub?> _open(Book b) async {
    try {
      return Epub.open(await File(b.filePath).readAsBytes());
    } catch (_) {
      return null;
    }
  }

  bool isRunning(Book b) => _running.contains(keyFor(b));

  Future<void> _throttle() async {
    final wait = const Duration(milliseconds: 4500) - DateTime.now().difference(_lastCall);
    if (wait > Duration.zero) await Future.delayed(wait);
    _lastCall = DateTime.now();
  }

  Future<void> _extract(Wiki w, Book b, int chapter, String text) async {
    await _throttle();
    final clipped = text.length > 60000 ? text.substring(0, 60000) : text;
    final known = w.entries.values
        .where((e) => !e.manual)
        .take(250)
        .map((e) => '${e.id} | ${e.name}${e.aliases.isEmpty ? '' : ' (${e.aliases.take(4).join(', ')})'} | ${e.type}')
        .join('\n');
    final prompt = '''
Sei l'archivista della wiki di un lettore. Leggi il capitolo qui sotto (dal libro «${b.title}», capitolo «${b.chapters[chapter].title}») e rispondi SOLO con JSON in questo formato:
{"summary": "...", "entries": [{"id": "...", "name": "...", "aliases": ["..."], "type": "personaggio|luogo|termine", "role": "...", "note": "..."}], "relations": [{"a": "...", "b": "...", "label": "..."}]}

VOCI GIÀ NELLA WIKI (id | nome (altri nomi) | tipo):
${known.isEmpty ? '(nessuna)' : known}

Regole:
- PRIMA di creare una voce controlla sempre l'elenco qui sopra: se il personaggio, il luogo o il termine è già presente, anche con un nome diverso, più corto o più lungo (es. "Arthur" e "Arthur Leywin"), usa il suo "id" e NON crearne uno nuovo. Per le voci nuove scrivi "id": "nuovo".
- Usa solo informazioni presenti in QUESTO capitolo. Non anticipare mai eventi futuri e non usare conoscenze esterne sull'opera.
- "entries": personaggi con un ruolo nella storia, luoghi e termini importanti (magie, organizzazioni, oggetti, razze). Niente comparse senza nome.
- "name": il nome più completo usato nel testo; "aliases": soprannomi, nomi brevi o titoli usati nel testo.
- "role": massimo 6 parole (es. "protagonista, ex re reincarnato").
- "note": tutto ciò che si scopre di nuovo su quella voce in questo capitolo, in italiano, in modo dettagliato (fino a 5 frasi).
- "relations": legami tra personaggi emersi in questo capitolo (label breve, es. "madre di", "alleato di"). In "a" e "b" usa l'id se esiste, altrimenti il nome.
- "summary": 2 frasi in italiano su cosa succede nel capitolo.

CAPITOLO:
$clipped''';
    final raw = await Gemini.ask(prompt, maxTokens: 4000, temperature: 0.2, json: true);
    final data = _parseJson(raw);
    final pos = wikiPos(b, chapter);
    final touched = <String>{};
    if (data != null) {
      final summary = (data['summary'] as String?)?.trim();
      if (summary != null && summary.isNotEmpty) w.summaries['${b.id}:$chapter'] = summary;
      for (final item in (data['entries'] as List? ?? const [])) {
        if (item is! Map) continue;
        final name = (item['name'] as String?)?.trim() ?? '';
        if (name.isEmpty || name.length > 60) continue;
        var type = (item['type'] as String?)?.toLowerCase().trim() ?? 'personaggio';
        if (!const ['personaggio', 'luogo', 'termine'].contains(type)) type = 'termine';
        final aliases = ((item['aliases'] as List?) ?? const []).whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty && s.length < 40).toList();
        final givenId = (item['id'] as String?)?.trim();
        WikiEntry? found = givenId != null && givenId != 'nuovo' ? w.entries[givenId] : null;
        found ??= w.find(name, type: type);
        for (final a in aliases) {
          found ??= w.find(a, type: type);
        }
        final WikiEntry e;
        if (found != null) {
          e = found;
          // se ora conosciamo il nome completo, lo uso come nome principale
          if (Wiki._tokens(name).length > Wiki._tokens(e.name).length && Wiki._tokens(name).containsAll(Wiki._tokens(e.name))) {
            e.aliases.add(e.name);
            e.name = name;
          }
        } else {
          var id = Wiki.slug(name);
          while (w.entries.containsKey(id)) {
            id = '$id-x';
          }
          e = WikiEntry(id: id, name: name, type: type);
          w.entries[id] = e;
        }
        final lower = e.name.toLowerCase();
        e.aliases.addAll(aliases.where((a) => a.toLowerCase() != lower));
        if (name.toLowerCase() != lower) e.aliases.add(name);
        final note = (item['note'] as String?)?.trim() ?? '';
        if (note.isNotEmpty) {
          e.notes.add(WikiNote(pos, note, b.id, chapter));
          touched.add(e.id);
        }
        final role = (item['role'] as String?)?.trim() ?? '';
        if (role.isNotEmpty && (e.roles.isEmpty || e.roles.last.text != role)) e.roles.add(WikiNote(pos, role, b.id, chapter));
      }
      WikiEntry? byRef(String? ref) => ref == null ? null : (w.entries[ref.trim()] ?? w.find(ref));
      for (final r in (data['relations'] as List? ?? const [])) {
        if (r is! Map) continue;
        final a = byRef(r['a'] as String?), c = byRef(r['b'] as String?);
        final label = (r['label'] as String?)?.trim() ?? '';
        if (a == null || c == null || a.id == c.id || label.isEmpty) continue;
        final dup = w.relations.any((x) => ((x.a == a.id && x.b == c.id) || (x.a == c.id && x.b == a.id)) && x.label == label);
        if (!dup) w.relations.add(WikiRelation(a.id, c.id, label, pos));
      }
      w.mergeDuplicates();
      touched.removeWhere((id) => !w.entries.containsKey(id));
      await _rewrite(w, b, chapter, touched.toList());
    }
    w.processed.add('${b.id}:$chapter');
  }

  /// Riscrive la scheda completa delle voci aggiornate: rilegge la versione
  /// precedente e ci integra le novità del capitolo.
  Future<void> _rewrite(Wiki w, Book b, int chapter, List<String> ids) async {
    final pos = wikiPos(b, chapter);
    for (var start = 0; start < ids.length; start += 8) {
      final group = ids.sublist(start, (start + 8).clamp(0, ids.length));
      final items = StringBuffer();
      for (final id in group) {
        final e = w.entries[id]!;
        final prev = e.descriptionAt(pos - 1);
        final news = e.notes.where((n) => n.pos == pos).map((n) => n.text).join(' ');
        final old = prev.isNotEmpty ? prev : e.notes.where((n) => n.pos < pos).map((n) => n.text).join(' ');
        items.writeln('### id: $id · ${e.name} (${e.type})');
        items.writeln('SCHEDA ATTUALE: ${old.isEmpty ? '(vuota)' : old}');
        items.writeln('NOVITÀ DEL CAPITOLO: $news');
        items.writeln();
      }
      await _throttle();
      final prompt = '''
Aggiorna le schede della wiki di un lettore del libro «${b.title}». Per ogni voce rileggi la SCHEDA ATTUALE e integra le NOVITÀ DEL CAPITOLO, riscrivendo una scheda completa e ordinata in italiano.
- Mantieni tutte le informazioni già presenti, correggile se le novità le precisano, non perdere dettagli.
- Organizza in paragrafi brevi (per i personaggi: chi è, aspetto e carattere, abilità, storia finora, legami; per luoghi e termini: cos'è, caratteristiche, cosa è successo lì o perché è importante).
- Può essere lunga quanto serve (anche più paragrafi), ma senza ripetizioni.
- Non aggiungere nulla che non sia nella scheda o nelle novità: niente spoiler e niente conoscenze esterne.
- Testo semplice, senza markdown, con paragrafi separati da una riga vuota.
Rispondi SOLO con JSON: {"schede": {"id": "testo della scheda", ...}}

$items''';
      try {
        final raw = await Gemini.ask(prompt, maxTokens: 8000, temperature: 0.3, json: true);
        final data = _parseJson(raw);
        final map = (data?['schede'] as Map?) ?? const {};
        for (final id in group) {
          final t = (map[id] as String?)?.trim();
          if (t != null && t.isNotEmpty) w.entries[id]!.descriptions.add(WikiNote(pos, t, b.id, chapter));
        }
      } on GeminiError {
        rethrow;
      } catch (e) {
        debugPrint('Schede non aggiornate: $e');
      }
    }
  }

  /// Ricrea la wiki da zero (tiene foto, note personali e voci create a mano).
  Future<void> rebuild(Book b) async {
    final w = await forBook(b);
    final keep = <String, WikiEntry>{};
    for (final e in w.entries.values) {
      if (e.manual) {
        keep[e.id] = e;
      } else if (e.photo != null || e.myNotes.isNotEmpty) {
        keep['__${e.name.toLowerCase()}'] = e;
      }
    }
    w.entries
      ..clear()
      ..addEntries(keep.entries.where((k) => !k.key.startsWith('__')));
    w.relations.clear();
    w.processed.clear();
    w.summaries.clear();
    _kept[w.key] = {for (final k in keep.entries.where((k) => k.key.startsWith('__'))) k.key.substring(2): k.value};
    await save(w);
    await ensure(b, silent: false);
  }

  /// Foto e note da riattaccare alle voci ricreate dopo "Rigenera".
  final Map<String, Map<String, WikiEntry>> _kept = {};

  void _reattach(Wiki w) {
    final kept = _kept[w.key];
    if (kept == null || kept.isEmpty) return;
    for (final e in w.entries.values) {
      final old = kept.remove(e.name.toLowerCase()) ?? (() {
        for (final a in e.aliases) {
          final x = kept.remove(a.toLowerCase());
          if (x != null) return x;
        }
        return null;
      })();
      if (old != null) {
        e.photo ??= old.photo;
        if (old.myNotes.isNotEmpty) e.myNotes = old.myNotes;
      }
    }
  }

  static Map<String, dynamic>? _parseJson(String raw) {
    var t = raw.trim();
    t = t.replaceAll(RegExp(r'^```(json)?', multiLine: false), '').replaceAll(RegExp(r'```$'), '').trim();
    final a = t.indexOf('{'), z = t.lastIndexOf('}');
    if (a < 0 || z <= a) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(t.substring(a, z + 1)) as Map);
    } catch (e) {
      debugPrint('JSON wiki non valido: $e');
      return null;
    }
  }

  // ---------- modifiche dell'utente ----------

  Future<WikiEntry> addManual(Book b, String name, String type, String text) async {
    final w = await forBook(b);
    var id = Wiki.slug(name);
    while (w.entries.containsKey(id)) {
      id = '$id-x';
    }
    final e = WikiEntry(id: id, name: name.trim(), type: type, manual: true, manualText: text.trim());
    w.entries[id] = e;
    await save(w);
    return e;
  }

  Future<void> deleteEntry(Book b, WikiEntry e) async {
    final w = await forBook(b);
    w.entries.remove(e.id);
    w.relations.removeWhere((r) => r.a == e.id || r.b == e.id);
    await save(w);
  }

  // ---------- riassunto dei capitoli precedenti ----------

  Future<String?> recap(Book b) async {
    final w = await forBook(b);
    final upto = b.lastChapter;
    final parts = <String>[];
    for (var i = (upto - 4).clamp(0, upto); i <= upto; i++) {
      if (i == upto && b.lastOffset < 0.5) continue;
      final s = w.summaries['${b.id}:$i'];
      if (s != null) parts.add('${b.chapters[i].title}: $s');
    }
    if (parts.isEmpty) return null;
    try {
      return await Gemini.ask(
        'Riassumi per un lettore che riprende il libro «${b.title}» dopo una pausa, in massimo 4 frasi brevi in italiano, '
        'cosa è successo di recente. Usa solo queste informazioni, senza aggiungere nulla e senza markdown:\n${parts.join('\n')}',
        maxTokens: 300,
      );
    } catch (_) {
      return parts.length <= 2 ? parts.join('\n\n') : parts.sublist(parts.length - 2).join('\n\n');
    }
  }
}
