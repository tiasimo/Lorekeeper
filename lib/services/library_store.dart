import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import 'cover_colors.dart';
import 'epub.dart';

EpubMeta _parseMeta(Uint8List bytes) => Epub.open(bytes).meta();

class ReaderPrefs {
  String theme;
  String font;
  double size;
  double lineHeight;
  ReaderPrefs({this.theme = 'Carta', this.font = 'Lora', this.size = 18, this.lineHeight = 1.7});
}

/// Libreria: libri, scaffale, progressi e statistiche. Tutto salvato in locale.
class LibraryStore extends ChangeNotifier {
  LibraryStore._();
  static final LibraryStore I = LibraryStore._();

  late Directory _dir;
  late SharedPreferences _prefs;
  bool loaded = false;

  final List<Book> books = [];

  /// Ordine dello scaffale: "b:<idLibro>" oppure "d:<idDivisore>".
  final List<String> shelf = [];

  String readerName = '';
  final ReaderPrefs reader = ReaderPrefs();
  Map<String, int> secondsByDay = {};
  int chaptersRead = 0;

  Timer? _saveTimer;

  Future<void> load() async {
    if (loaded) return;
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory(p.join(docs.path, 'lorekeeper'));
    await Directory(p.join(_dir.path, 'books')).create(recursive: true);
    _prefs = await SharedPreferences.getInstance();

    final f = File(p.join(_dir.path, 'library.json'));
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        books
          ..clear()
          ..addAll(((j['books'] as List?) ?? []).map((b) => Book.fromJson(Map<String, dynamic>.from(b as Map))));
        shelf
          ..clear()
          ..addAll(((j['shelf'] as List?) ?? []).cast<String>());
      } catch (e) {
        debugPrint('library.json non leggibile: $e');
      }
    }
    readerName = _prefs.getString('readerName') ?? '';
    reader.theme = _prefs.getString('r.theme') ?? reader.theme;
    reader.font = _prefs.getString('r.font') ?? reader.font;
    reader.size = _prefs.getDouble('r.size') ?? reader.size;
    reader.lineHeight = _prefs.getDouble('r.line') ?? reader.lineHeight;
    chaptersRead = _prefs.getInt('stats.chapters') ?? 0;
    final s = _prefs.getString('stats.days');
    if (s != null) secondsByDay = Map<String, int>.from(jsonDecode(s) as Map);
    loaded = true;
    notifyListeners();
  }

  Book? byId(String id) {
    for (final b in books) {
      if (b.id == id) return b;
    }
    return null;
  }

  Book? get lastRead {
    final read = books.where((b) => b.lastReadAt != null).toList()
      ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    return read.isEmpty ? null : read.first;
  }

  Future<void> _saveNow() async {
    final f = File(p.join(_dir.path, 'library.json'));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({'books': books.map((b) => b.toJson()).toList(), 'shelf': shelf}));
    await tmp.rename(f.path);
  }

  void save({bool soon = false}) {
    _saveTimer?.cancel();
    if (soon) {
      _saveTimer = Timer(const Duration(seconds: 2), _saveNow);
    } else {
      _saveNow();
    }
  }

  // ---------- Import ----------

  Future<Book> importEpub(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final meta = await compute(_parseMeta, bytes);
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final dest = p.join(_dir.path, 'books', '$id.epub');
    await File(dest).writeAsBytes(bytes, flush: true);
    String? coverPath;
    if (meta.cover != null) {
      coverPath = p.join(_dir.path, 'books', '${id}_cover.${meta.coverExt}');
      await File(coverPath).writeAsBytes(meta.cover!, flush: true);
    }
    final (spine, text) = await CoverColors.fromBytes(meta.cover);
    final book = Book(
      id: id,
      title: meta.title,
      author: meta.author,
      series: meta.series,
      seriesIndex: meta.seriesIndex,
      filePath: dest,
      coverPath: coverPath,
      chapters: meta.chapters,
      spineColor: spine,
      spineTextColor: text,
      coverSpineColor: spine,
      coverSpineTextColor: text,
      addedAt: DateTime.now(),
    );
    books.add(book);
    _placeOnShelf(book);
    await _saveNow();
    notifyListeners();
    return book;
  }

  /// I volumi della stessa serie finiscono vicini, in ordine.
  void _placeOnShelf(Book book) {
    final entry = 'b:${book.id}';
    if (book.series != null) {
      int? insertAt;
      for (var i = 0; i < shelf.length; i++) {
        final other = shelf[i].startsWith('b:') ? byId(shelf[i].substring(2)) : null;
        if (other == null || other.id == book.id || other.series != book.series) continue;
        final oi = other.seriesIndex ?? 0;
        final bi = book.seriesIndex ?? 999;
        if (oi <= bi) insertAt = i + 1;
        if (oi > bi && insertAt == null) insertAt = i;
      }
      if (insertAt != null) {
        shelf.insert(insertAt, entry);
        return;
      }
    }
    shelf.add(entry);
    if (books.length == 1 && !shelf.any((s) => s.startsWith('d:'))) shelf.add('d:elendrath');
  }

  Future<void> deleteBook(Book b) async {
    books.remove(b);
    shelf.remove('b:${b.id}');
    try {
      await File(b.filePath).delete();
      if (b.coverPath != null) await File(b.coverPath!).delete();
    } catch (_) {}
    await _saveNow();
    notifyListeners();
  }

  // ---------- Scaffale ----------

  void addDivider(String id, {int? at}) {
    shelf.insert(at ?? shelf.length, 'd:$id');
    save();
    notifyListeners();
  }

  void removeShelfEntry(int index) {
    if (index < 0 || index >= shelf.length) return;
    shelf.removeAt(index);
    save();
    notifyListeners();
  }

  void moveShelfEntry(int from, int to) {
    if (from == to) return;
    final e = shelf.removeAt(from);
    shelf.insert(to.clamp(0, shelf.length), e);
    save();
    notifyListeners();
  }

  void updateBook(Book b) {
    save();
    notifyListeners();
  }

  // ---------- Lettura ----------

  void setProgress(Book b, int chapter, double offset) {
    b.lastChapter = chapter;
    b.lastOffset = offset.clamp(0.0, 1.0);
    b.lastReadAt = DateTime.now();
    save(soon: true);
  }

  void addReadingTime(int seconds) {
    if (seconds <= 0) return;
    final k = _dayKey(DateTime.now());
    secondsByDay[k] = (secondsByDay[k] ?? 0) + seconds;
    _prefs.setString('stats.days', jsonEncode(secondsByDay));
  }

  void chapterFinished() {
    chaptersRead++;
    _prefs.setInt('stats.chapters', chaptersRead);
  }

  int get streak {
    var day = DateTime.now();
    if ((secondsByDay[_dayKey(day)] ?? 0) == 0) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while ((secondsByDay[_dayKey(day)] ?? 0) > 0) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  int get secondsThisWeek {
    var total = 0;
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      total += secondsByDay[_dayKey(now.subtract(Duration(days: i)))] ?? 0;
    }
    return total;
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  // ---------- Preferenze ----------

  void setReaderName(String n) {
    readerName = n.trim();
    _prefs.setString('readerName', readerName);
    notifyListeners();
  }

  void saveReaderPrefs() {
    _prefs.setString('r.theme', reader.theme);
    _prefs.setString('r.font', reader.font);
    _prefs.setDouble('r.size', reader.size);
    _prefs.setDouble('r.line', reader.lineHeight);
    notifyListeners();
  }
}
