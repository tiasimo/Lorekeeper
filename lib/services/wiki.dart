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
  /// Dettagli per luoghi e termini (scena, contenitore, categoria, citazione…), con la
  /// posizione in cui sono emersi: {chiave: {"p": pos, "v": valore}}.
  final Map<String, Map<String, dynamic>> extra;

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
    Map<String, Map<String, dynamic>>? extra,
  })  : extra = extra ?? {},
        aliases = aliases ?? {},
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

  /// Posizione dell'ultima scheda completa visibile (per mostrare le novità successive).
  int descriptionPosAt(int limit) {
    var p = -1;
    for (final d in descriptions) {
      if (d.pos <= limit && d.pos > p) p = d.pos;
    }
    return p;
  }

  dynamic extraAt(String k, int limit) {
    final x = extra[k];
    if (x == null) return null;
    return manual || (x['p'] as int? ?? 0) <= limit ? x['v'] : null;
  }

  void setExtra(String k, dynamic v, int pos, {bool keepFirst = false}) {
    if (v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty)) return;
    if (keepFirst && extra.containsKey(k)) return;
    extra[k] = {'p': pos, 'v': v};
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
        'extra': extra,
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
        extra: {
          for (final x in ((j['extra'] as Map?) ?? const {}).entries)
            if (x.value is Map) x.key as String: Map<String, dynamic>.from(x.value as Map)
        },
      );
}

class WikiRelation {
  final String a, b, label;
  final int pos;
  final String kind; // famiglia | amore | amicizia | alleanza | rivalità | speciale (gruppo)
  WikiRelation(this.a, this.b, this.label, this.pos, [String? kind]) : kind = kind ?? guessKind(label);

  /// Legami stretti: vanno nella costellazione.
  bool get close => kind == 'famiglia' || kind == 'amore' || kind == 'amicizia';

  static String guessKind(String label) {
    final l = label.toLowerCase();
    bool any(List<String> ws) => ws.any(l.contains);
    if (any(['madre', 'padre', 'figli', 'fratell', 'sorell', 'moglie', 'marit', 'coniug', 'zio', 'zia', 'nonn', 'cugin', 'nipot', 'genitor', 'famiglia', 'parente', 'gemell'])) {
      return 'famiglia';
    }
    if (any(['amant', 'fidanzat', 'innamorat', 'amore', 'sposa', 'promess', 'cotta'])) return 'amore';
    if (any(['amic', 'conoscent', 'compagno di giochi'])) return 'amicizia';
    if (any(['rival', 'nemic', 'avversar', 'antagonist', 'odia'])) return 'rivalità';
    if (any(['allea', 'compagn', 'mentore', 'maestr', 'allievo', 'allieva', 'discepol', 'protett', 'servitor', 'guardia', 'alleat', 'collega', 'contratto', 'legame'])) return 'alleanza';
    return 'alleanza';
  }

  static const kinds = ['famiglia', 'amicizia', 'amore', 'rivalità', 'alleanza'];

  Map<String, dynamic> toJson() => {'a': a, 'b': b, 'l': label, 'p': pos, 'k': kind};
  factory WikiRelation.fromJson(Map j) {
    final k = j['k'] as String?;
    return WikiRelation(j['a'] as String, j['b'] as String, j['l'] as String, j['p'] as int, k == 'altro' ? null : k);
  }
}

class Wiki {
  final String key;
  final String title;
  final Map<String, WikiEntry> entries = {};
  final List<WikiRelation> relations = [];
  /// Appartenenza a gruppi (squadre, gilde, casate…): a = id del personaggio, b = nome del gruppo.
  final List<WikiRelation> groups = [];
  /// Posizioni (fine volume) in cui Gemini ha analizzato tutti i legami in una volta.
  final Set<int> linkSnapshots = {};
  final Set<String> processed = {}; // "idLibro:capitolo"
  final Map<String, String> summaries = {}; // "idLibro:capitolo" → riassunto
  final Set<String> pendingRewrite = {}; // voci con novità da integrare nella scheda completa

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
    from.extra.forEach((k, v) => into.extra.putIfAbsent(k, () => v));
    if (from.myNotes.isNotEmpty) into.myNotes = [into.myNotes, from.myNotes].where((x) => x.isNotEmpty).join('\n');
    entries.remove(from.id);
    for (var i = 0; i < relations.length; i++) {
      final r = relations[i];
      if (r.a == from.id || r.b == from.id) {
        relations[i] = WikiRelation(r.a == from.id ? into.id : r.a, r.b == from.id ? into.id : r.b, r.label, r.pos, r.kind);
      }
    }
    relations.removeWhere((r) => r.a == r.b);
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      if (g.a == from.id) groups[i] = WikiRelation(into.id, g.b, g.label, g.pos, 'speciale');
    }
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

  /// Ultima analisi dei legami visibile fino a [limit] (null = dati vecchi, capitolo per capitolo).
  int? snapshotAt(int limit) {
    int? best;
    for (final p in linkSnapshots) {
      if (p <= limit && (best == null || p > best)) best = p;
    }
    return best;
  }

  List<WikiRelation> relationsAt(int limit) {
    final snap = snapshotAt(limit);
    return relations.where((r) => snap != null ? r.pos == snap : r.pos <= limit).toList();
  }

  /// Gruppi visibili fino a [limit]: nome → membri. Oltre a quelli indicati da Gemini,
  /// riconosce i gruppi citati nei ruoli dei personaggi (es. "mago dei Twin Horns").
  Map<String, Set<String>> groupsAt(int limit) {
    final out = <String, Set<String>>{};
    final snap = snapshotAt(limit);
    for (final g in groups.where((g) => snap != null ? g.pos == snap : g.pos <= limit)) {
      if (entries[g.a] == null) continue;
      out.putIfAbsent(g.b, () => {}).add(g.a);
    }
    if (snap != null) {
      out.removeWhere((_, m) => m.length < 2);
      return out;
    }
    final chars = entries.values.where((e) => e.type == 'personaggio').toList();
    for (final t in entries.values.where((e) => e.type != 'personaggio' && e.name.length >= 4)) {
      if (t.notesAt(limit).isEmpty && !t.manual) continue;
      final names = [t.name, ...t.aliases.where((a) => a.length >= 4)].map((n) => n.toLowerCase()).toList();
      final members = <String>{};
      for (final c in chars) {
        final role = c.roleAt(limit).toLowerCase();
        if (role.isNotEmpty && names.any(role.contains)) members.add(c.id);
      }
      if (members.length < 2) continue;
      final key = out.keys.firstWhere((k) => names.contains(k.toLowerCase()), orElse: () => t.name);
      out.putIfAbsent(key, () => {}).addAll(members);
    }
    out.removeWhere((_, m) => m.length < 2);
    return out;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'entries': entries.values.map((e) => e.toJson()).toList(),
        'relations': relations.map((r) => r.toJson()).toList(),
        'groups': groups.map((r) => r.toJson()).toList(),
        'snaps': linkSnapshots.toList(),
        'processed': processed.toList(),
        'summaries': summaries,
        'pending': pendingRewrite.toList(),
      };

  factory Wiki.fromJson(Map j) {
    final w = Wiki(j['key'] as String, (j['title'] as String?) ?? '');
    for (final e in (j['entries'] as List? ?? [])) {
      final x = WikiEntry.fromJson(e as Map);
      w.entries[x.id] = x;
    }
    w.relations.addAll((j['relations'] as List? ?? []).map((r) => WikiRelation.fromJson(r as Map)));
    w.linkSnapshots.addAll((j['snaps'] as List? ?? []).cast<int>());
    w.groups.addAll((j['groups'] as List? ?? []).map((r) => WikiRelation.fromJson(r as Map)));
    w.processed.addAll((j['processed'] as List? ?? []).cast<String>());
    w.summaries.addAll(Map<String, String>.from((j['summaries'] as Map?) ?? {}));
    w.pendingRewrite.addAll((j['pending'] as List? ?? []).cast<String>());
    return w;
  }
}

class WikiStatus {
  final bool running;
  final int done;
  final int total;
  final String? error;
  final String? phase;
  const WikiStatus({this.running = false, this.done = 0, this.total = 0, this.error, this.phase});
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
        // A volume concluso Gemini analizza tutti i legami in una volta sola.
        if (i == b.chapters.length - 1) {
          status[key] = WikiStatus(running: true, done: done, total: todo.length, phase: 'Analizzo i legami del volume…');
          notifyListeners();
          await _analyzeLinks(w, b, i);
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

  final Set<String> _filling = {};

  /// Completa i dettagli grafici (scena dei luoghi, categoria dei termini…) delle voci
  /// create prima che esistessero: una sola richiesta a Gemini, in silenzio.
  Future<bool> fillDetails(Book b) async {
    final key = keyFor(b);
    if (_running.contains(key) || _filling.contains(key)) return false;
    final k = await Secrets.geminiKey();
    if (k == null || k.isEmpty) return false;
    final w = await forBook(b);
    final limit = limitFor(b);
    final todo = w.entries.values
        .where((e) => !e.manual && e.visibleAt(limit) && ((e.type == 'luogo' && !e.extra.containsKey('scene')) || (e.type == 'termine' && !e.extra.containsKey('category'))))
        .take(40)
        .toList();
    if (todo.isEmpty) return false;
    _filling.add(key);
    try {
      await _throttle();
      final list = todo.map((e) {
        final d = e.descriptionAt(limit);
        final t = d.isNotEmpty ? d : e.notesAt(limit).map((n) => n.text).join(' ');
        return '${e.id} | ${e.type} | ${e.name} | ${e.roleAt(limit)} | ${t.length > 500 ? t.substring(0, 500) : t}';
      }).join('\n');
      final prompt = """
Per ogni voce della wiki qui sotto (id | tipo | nome | ruolo | descrizione) rispondi SOLO con JSON: {"voci": {"id": {...}}}.
Per i luoghi: {"kind": tipo in una parola, "inside": luogo più grande che lo contiene (se noto), "scene": {"setting": uno tra villaggio, città, castello, palazzo, accademia, foresta, montagna, mare, lago, deserto, pianura, grotta, rovine, neve, palude, cielo, "time": uno tra alba, giorno, tramonto, notte}}.
Per i termini: {"category": una tra magia, organizzazione, oggetto, razza, titolo, concetto, "gram": riga in stile dizionario (es. "s. m. · ruolo magico"), "defs": da 1 a 3 significati brevi, "facts": solo per le organizzazioni, chiavi brevi in maiuscolo}.
Usa solo le informazioni date, in italiano.

$list""";
      final raw = await Gemini.ask(prompt, maxTokens: 6000, temperature: 0.2, json: true);
      final data = _parseJson(raw);
      final voci = (data?['voci'] as Map?) ?? const {};
      String? str(Object? v) => v is String && v.trim().isNotEmpty && v.trim().length < 240 ? v.trim() : null;
      for (final e in todo) {
        final item = voci[e.id];
        final pos = e.firstPos;
        if (item is! Map) {
          e.setExtra(e.type == 'luogo' ? 'scene' : 'category', e.type == 'luogo' ? {'setting': null} : 'concetto', pos);
          continue;
        }
        if (e.type == 'luogo') {
          e.setExtra('kind', str(item['kind'])?.toLowerCase(), pos);
          e.setExtra('inside', str(item['inside']), pos);
          final sc = item['scene'];
          e.setExtra('scene', sc is Map ? {'setting': str(sc['setting'])?.toLowerCase(), 'time': str(sc['time'])?.toLowerCase()} : {'setting': null}, pos);
        } else {
          e.setExtra('category', str(item['category'])?.toLowerCase() ?? 'concetto', pos);
          e.setExtra('gram', str(item['gram']), pos);
          e.setExtra('defs', (item['defs'] as List?)?.map(str).whereType<String>().take(3).toList(), pos);
          final f = item['facts'];
          if (f is Map) {
            e.setExtra('facts', {for (final x in f.entries) if (x.key is String && str(x.value) != null) (x.key as String).toUpperCase(): str(x.value)}, pos);
          }
        }
      }
      await save(w);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _filling.remove(key);
    }
  }

  /// Analisi dei legami subito, fino al capitolo in cui sei (senza aspettare la fine del volume).
  Future<String?> analyzeLinksNow(Book b) async {
    final key = keyFor(b);
    if (_running.contains(key)) return 'La wiki si sta già aggiornando: riprova tra poco.';
    final k = await Secrets.geminiKey();
    if (k == null || k.isEmpty) return 'Aggiungi la chiave API di Gemini in Impostazioni.';
    final w = await forBook(b);
    var ch = targetChapter(b).clamp(0, b.chapters.length - 1);
    while (ch > 0 && !w.processed.contains('${b.id}:$ch')) {
      ch--;
    }
    _running.add(key);
    status[key] = const WikiStatus(running: true, phase: 'Analizzo i legami…');
    notifyListeners();
    try {
      await _analyzeLinks(w, b, ch);
      await save(w);
      status[key] = const WikiStatus();
      return null;
    } on GeminiError catch (e) {
      status[key] = WikiStatus(error: e.message);
      return e.message;
    } catch (e) {
      status[key] = WikiStatus(error: 'Errore durante l\'analisi dei legami: $e');
      return 'Errore durante l\'analisi dei legami.';
    } finally {
      _running.remove(key);
      notifyListeners();
    }
  }

  /// Rilegge tutte le schede dei personaggi e i riassunti del volume e ricostruisce
  /// legami (famiglia, amici, amore, rivali, alleati) e gruppi.
  Future<void> _analyzeLinks(Wiki w, Book b, int chapter) async {
    final pos = wikiPos(b, chapter);
    int m(WikiEntry e) => e.notesAt(pos).map((n) => '${n.bookId}:${n.chapter}').toSet().length;
    final chars = w.entries.values.where((e) => e.type == 'personaggio' && (e.manual || e.notesAt(pos).isNotEmpty)).toList()..sort((x, y) => m(y) - m(x));
    if (chars.length < 2) return;
    final per = (110000 / chars.length).clamp(250, 1400).round();
    String clip(String t) => t.length > per ? '${t.substring(0, per)}…' : t;
    final sheets = StringBuffer();
    for (final e in chars) {
      final d = e.descriptionAt(pos);
      final text = d.isNotEmpty ? d : e.notesAt(pos).map((n) => n.text).join(' ');
      sheets.writeln('${e.id} | ${e.name}${e.aliases.isEmpty ? '' : ' (${e.aliases.take(4).join(', ')})'} | ${e.roleAt(pos)}');
      sheets.writeln('   ${clip(text).replaceAll('\n', ' ')}');
    }
    final others = w.entries.values
        .where((e) => e.type != 'personaggio' && e.notesAt(pos).isNotEmpty)
        .take(120)
        .map((e) => '${e.name} | ${e.type} | ${e.roleAt(pos)}')
        .join('\n');
    final plot = [
      for (var i = 0; i <= chapter; i++)
        if (w.summaries['${b.id}:$i'] != null) 'Cap. ${i + 1}: ${w.summaries['${b.id}:$i']}'
    ].join('\n');
    await _throttle();
    final prompt = '''
Sei l'archivista della wiki di un lettore del libro «${b.title}». Hai le schede di tutti i personaggi e la trama del volume fino al capitolo ${chapter + 1}. Ricostruisci la rete COMPLETA dei legami e rispondi SOLO con JSON:
{"relations": [{"a": "id", "b": "id", "label": "...", "kind": "famiglia|amicizia|amore|rivalità|alleanza"}], "groups": [{"name": "...", "members": ["id"]}]}

Regole:
- Includi tutti i legami significativi tra QUALSIASI coppia di personaggi, non solo con il protagonista.
- Una sola relazione per coppia, la più importante. "label" è breve e si legge "a <label> b" (es. "madre di", "migliore amico di", "maestro di", "rivale di").
- "kind": famiglia (parenti, coniugi), amicizia, amore (innamorati, fidanzati), rivalità (rivali, nemici), alleanza (compagni, mentori, alleati, colleghi).
- "groups": squadre, gilde, casate, ordini, scuole, eserciti di cui fanno parte almeno due personaggi; "members" con gli id.
- Usa solo le informazioni qui sotto: niente conoscenze esterne sull'opera, niente eventi successivi.
- In "a", "b" e "members" usa esattamente gli id dell'elenco.

PERSONAGGI (id | nome (altri nomi) | ruolo, poi la scheda):
$sheets
ALTRE VOCI (nome | tipo | ruolo):
${others.isEmpty ? '(nessuna)' : others}

TRAMA DEL VOLUME:
${plot.isEmpty ? '(non disponibile)' : plot}''';
    final raw = await Gemini.ask(prompt, maxTokens: 8000, temperature: 0.2, json: true);
    final data = _parseJson(raw);
    if (data == null) throw GeminiError('Gemini ha risposto in modo non valido: riprova.');
    WikiEntry? byRef(String? ref) => ref == null ? null : (w.entries[ref.trim()] ?? w.find(ref));
    final rels = <WikiRelation>[];
    for (final r in (data['relations'] as List? ?? const [])) {
      if (r is! Map) continue;
      final a = byRef(r['a'] as String?), c = byRef(r['b'] as String?);
      final label = (r['label'] as String?)?.trim() ?? '';
      if (a == null || c == null || a.id == c.id || label.isEmpty) continue;
      if (rels.any((x) => (x.a == a.id && x.b == c.id) || (x.a == c.id && x.b == a.id))) continue;
      var kind = (r['kind'] as String?)?.toLowerCase().trim();
      if (!WikiRelation.kinds.contains(kind)) kind = null;
      rels.add(WikiRelation(a.id, c.id, label, pos, kind));
    }
    final grs = <WikiRelation>[];
    for (final g in (data['groups'] as List? ?? const [])) {
      if (g is! Map) continue;
      var name = (g['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      name = w.find(name)?.name ?? name;
      for (final mm in (g['members'] as List? ?? const [])) {
        final e = mm is String ? byRef(mm) : null;
        if (e == null || e.type != 'personaggio') continue;
        if (grs.any((x) => x.a == e.id && x.b == name)) continue;
        grs.add(WikiRelation(e.id, name, name, pos, 'speciale'));
      }
    }
    if (rels.isEmpty && grs.isEmpty) return;
    w.relations
      ..removeWhere((r) => r.pos == pos)
      ..addAll(rels);
    w.groups
      ..removeWhere((r) => r.pos == pos)
      ..addAll(grs);
    w.linkSnapshots.add(pos);
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
{"summary": "...", "entries": [{"id": "...", "name": "...", "aliases": ["..."], "type": "personaggio|luogo|termine", "role": "...", "note": "...", "kind": "...", "inside": "...", "scene": {"setting": "...", "time": "..."}, "category": "...", "gram": "...", "defs": ["..."], "quote": "...", "facts": {"...": "..."}}]}

VOCI GIÀ NELLA WIKI (id | nome (altri nomi) | tipo):
${known.isEmpty ? '(nessuna)' : known}

Regole:
- PRIMA di creare una voce controlla sempre l'elenco qui sopra: se il personaggio, il luogo o il termine è già presente, anche con un nome diverso, più corto o più lungo (es. "Arthur" e "Arthur Leywin"), usa il suo "id" e NON crearne uno nuovo. Per le voci nuove scrivi "id": "nuovo".
- Usa solo informazioni presenti in QUESTO capitolo. Non anticipare mai eventi futuri e non usare conoscenze esterne sull'opera.
- "entries": personaggi con un ruolo nella storia, luoghi e termini importanti (magie, organizzazioni, oggetti, razze). Niente comparse senza nome.
- "name": il nome più completo usato nel testo; "aliases": soprannomi, nomi brevi o titoli usati nel testo.
- "role": massimo 6 parole (es. "protagonista, ex re reincarnato").
- "note": tutto ciò che si scopre di nuovo su quella voce in questo capitolo, in italiano, in modo dettagliato (fino a 5 frasi).
- Solo per i LUOGHI: "kind" = tipo di luogo in una parola (villaggio, città, capitale, regno, continente, foresta, montagna, castello, palazzo, accademia, mare, lago, isola, deserto, grotta, rovine, pianura, dungeon…); "inside" = nome del luogo più grande che lo contiene, se il testo lo dice; "scene" = come appare, con "setting" tra villaggio, città, castello, palazzo, accademia, foresta, montagna, mare, lago, deserto, pianura, grotta, rovine, neve, palude, cielo e "time" tra alba, giorno, tramonto, notte (il momento in cui compare nel capitolo).
- Solo per i TERMINI: "category" tra magia (incantesimi, poteri, tecniche, concetti magici), organizzazione (gruppi, squadre, gilde, casate, ordini, eserciti, nazioni), oggetto, razza, titolo, concetto; "gram" = riga in stile dizionario (es. "s. m. · ruolo magico"); "defs" = da 1 a 3 significati brevi; "quote" = UNA frase copiata esattamente dal capitolo in cui compare il termine (max 200 caratteri); "facts" solo per le organizzazioni, con chiavi brevi in maiuscolo (es. "BASE": "Città di Xyrus", "CAPO": "...").
- Ometti i campi che non c'entrano o che il testo non dice.
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
        String? str(Object? v) => v is String && v.trim().isNotEmpty && v.trim().length < 240 ? v.trim() : null;
        if (e.type == 'luogo') {
          e.setExtra('kind', str(item['kind'])?.toLowerCase(), pos);
          e.setExtra('inside', str(item['inside']), pos);
          final sc = item['scene'];
          if (sc is Map) e.setExtra('scene', {'setting': str(sc['setting'])?.toLowerCase(), 'time': str(sc['time'])?.toLowerCase()}, pos, keepFirst: true);
        } else if (e.type == 'termine') {
          e.setExtra('category', str(item['category'])?.toLowerCase(), pos);
          e.setExtra('gram', str(item['gram']), pos);
          final defs = (item['defs'] as List?)?.map(str).whereType<String>().take(3).toList();
          e.setExtra('defs', defs, pos);
          final q = str(item['quote']);
          if (q != null) e.setExtra('quote', {'t': q, 'b': b.id, 'c': chapter}, pos, keepFirst: true);
          final f = item['facts'];
          if (f is Map) {
            final old = Map<String, dynamic>.from((e.extra['facts']?['v'] as Map?) ?? const {});
            f.forEach((k, v) {
              final vv = str(v);
              if (k is String && vv != null) old[k.toUpperCase()] = vv;
            });
            e.setExtra('facts', old, pos);
          }
        }
      }
      WikiEntry? byRef(String? ref) => ref == null ? null : (w.entries[ref.trim()] ?? w.find(ref));
      for (final r in (data['relations'] as List? ?? const [])) {
        if (r is! Map) continue;
        final a = byRef(r['a'] as String?), c = byRef(r['b'] as String?);
        final label = (r['label'] as String?)?.trim() ?? '';
        if (a == null || c == null || a.id == c.id || label.isEmpty) continue;
        final dup = w.relations.any((x) => ((x.a == a.id && x.b == c.id) || (x.a == c.id && x.b == a.id)) && x.label == label);
        var kind = (r['kind'] as String?)?.toLowerCase().trim();
        if (!WikiRelation.kinds.contains(kind)) kind = null;
        final inverse = w.relations.any((x) => x.a == c.id && x.b == a.id);
        if (!dup && !inverse) w.relations.add(WikiRelation(a.id, c.id, label, pos, kind));
      }
      for (final g in (data['groups'] as List? ?? const [])) {
        if (g is! Map) continue;
        var name = (g['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        name = w.find(name)?.name ?? name;
        for (final m in (g['members'] as List? ?? const [])) {
          final e = m is String ? byRef(m) : null;
          if (e == null || e.type != 'personaggio') continue;
          if (w.groups.any((x) => x.a == e.id && x.b.toLowerCase() == name.toLowerCase())) continue;
          w.groups.add(WikiRelation(e.id, name, name, pos, 'speciale'));
        }
      }
      w.mergeDuplicates();
      w.pendingRewrite.addAll(touched);
      w.pendingRewrite.removeWhere((id) => !w.entries.containsKey(id));
      // La scheda completa si riscrive ogni 10 capitoli e alla fine del volume.
      if ((chapter + 1) % 10 == 0 || chapter == b.chapters.length - 1) {
        await _rewrite(w, b, chapter, w.pendingRewrite.toList());
        w.pendingRewrite.clear();
      }
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
        final since = e.descriptionPosAt(pos - 1);
        final news = e.notes.where((n) => n.pos > since && n.pos <= pos).map((n) => n.text).join(' ');
        final old = prev;
        items.writeln('### id: $id · ${e.name} (${e.type})');
        items.writeln('SCHEDA ATTUALE: ${old.isEmpty ? '(vuota)' : old}');
        items.writeln('NOVITÀ DEGLI ULTIMI CAPITOLI: $news');
        items.writeln();
      }
      await _throttle();
      final prompt = '''
Aggiorna le schede della wiki di un lettore del libro «${b.title}». Per ogni voce rileggi la SCHEDA ATTUALE e integra le NOVITÀ DEGLI ULTIMI CAPITOLI, riscrivendo una scheda completa e ordinata in italiano.
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
    w.groups.clear();
    w.linkSnapshots.clear();
    w.processed.clear();
    w.summaries.clear();
    w.pendingRewrite.clear();
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
    w.groups.removeWhere((r) => r.a == e.id);
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
