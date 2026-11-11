import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'library_store.dart';

/// Segnalibro: punto del libro con una nota facoltativa.
class Bookmark {
  final String id;
  final int chapter;
  final double frac;
  final String excerpt; // prime parole della pagina
  String note;
  final DateTime created;
  Bookmark({required this.id, required this.chapter, required this.frac, required this.excerpt, this.note = '', DateTime? created}) : created = created ?? DateTime.now();

  Map<String, dynamic> toJson() => {'id': id, 'c': chapter, 'f': frac, 'x': excerpt, 'n': note, 't': created.millisecondsSinceEpoch};
  factory Bookmark.fromJson(Map j) => Bookmark(
        id: j['id'] as String,
        chapter: j['c'] as int,
        frac: (j['f'] as num).toDouble(),
        excerpt: (j['x'] as String?) ?? '',
        note: (j['n'] as String?) ?? '',
        created: DateTime.fromMillisecondsSinceEpoch((j['t'] as int?) ?? 0),
      );
}

/// Frase evidenziata (testo semplice, senza trattini morbidi) con colore e nota.
class Highlight {
  final String id;
  final int chapter;
  final double frac;
  final String text;
  int color; // indice in [Annotations.colors]
  String note;
  bool favorite; // citazione preferita
  final DateTime created;
  Highlight({required this.id, required this.chapter, required this.frac, required this.text, this.color = 0, this.note = '', this.favorite = false, DateTime? created})
      : created = created ?? DateTime.now();

  Map<String, dynamic> toJson() => {'id': id, 'c': chapter, 'f': frac, 'x': text, 'k': color, 'n': note, 'fav': favorite, 't': created.millisecondsSinceEpoch};
  factory Highlight.fromJson(Map j) => Highlight(
        id: j['id'] as String,
        chapter: j['c'] as int,
        frac: (j['f'] as num).toDouble(),
        text: j['x'] as String,
        color: (j['k'] as int?) ?? 0,
        note: (j['n'] as String?) ?? '',
        favorite: (j['fav'] as bool?) ?? false,
        created: DateTime.fromMillisecondsSinceEpoch((j['t'] as int?) ?? 0),
      );
}

class BookNotes {
  final List<Bookmark> bookmarks = [];
  final List<Highlight> highlights = [];
  int rating = 0; // 0 = nessun voto, 1–5 stelle
  String review = '';
  DateTime? finishedAt;

  Map<String, dynamic> toJson() => {
        'bm': bookmarks.map((b) => b.toJson()).toList(),
        'hl': highlights.map((h) => h.toJson()).toList(),
        'rating': rating,
        'review': review,
        'done': finishedAt?.millisecondsSinceEpoch,
      };

  factory BookNotes.fromJson(Map j) {
    final n = BookNotes();
    n.bookmarks.addAll(((j['bm'] as List?) ?? []).map((x) => Bookmark.fromJson(x as Map)));
    n.highlights.addAll(((j['hl'] as List?) ?? []).map((x) => Highlight.fromJson(x as Map)));
    n.rating = (j['rating'] as int?) ?? 0;
    n.review = (j['review'] as String?) ?? '';
    final d = j['done'] as int?;
    if (d != null) n.finishedAt = DateTime.fromMillisecondsSinceEpoch(d);
    return n;
  }
}

/// Segnalibri, evidenziazioni, note e recensioni: un file JSON per libro.
class Annotations extends ChangeNotifier {
  Annotations._();
  static final I = Annotations._();

  /// Colori degli evidenziatori (giallo, verde, azzurro, rosa).
  static const colors = [0xFFF6D365, 0xFF9ED9A0, 0xFF9CC9F0, 0xFFF2A7C3];
  static const colorNames = ['Giallo', 'Verde', 'Azzurro', 'Rosa'];

  final Map<String, BookNotes> _cache = {};

  String _file(String bookId) => p.join(LibraryStore.I.dataDir, 'notes_$bookId.json');

  BookNotes of(String bookId) {
    final c = _cache[bookId];
    if (c != null) return c;
    BookNotes n;
    try {
      final f = File(_file(bookId));
      n = f.existsSync() ? BookNotes.fromJson(jsonDecode(f.readAsStringSync()) as Map) : BookNotes();
    } catch (_) {
      n = BookNotes();
    }
    return _cache[bookId] = n;
  }

  Future<void> save(String bookId) async {
    final n = _cache[bookId];
    if (n == null) return;
    await File(_file(bookId)).writeAsString(jsonEncode(n.toJson()));
    notifyListeners();
  }

  /// Tutti i libri che hanno qualcosa salvato (per citazioni e recensioni).
  List<(String, BookNotes)> all() {
    final out = <(String, BookNotes)>[];
    for (final b in LibraryStore.I.books) {
      final n = of(b.id);
      if (n.bookmarks.isNotEmpty || n.highlights.isNotEmpty || n.rating > 0 || n.review.isNotEmpty) out.add((b.id, n));
    }
    return out;
  }

  void clearCache() {
    _cache.clear();
    notifyListeners();
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
