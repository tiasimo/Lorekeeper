import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../widgets/spine.dart';
import 'cover_colors.dart';
import 'epub.dart';

EpubMeta _parseMeta(Uint8List bytes) => Epub.open(bytes).meta();

class ReaderPrefs {
  String theme = 'Carta';
  String font = 'Lora';
  double size = 18;
  double lineHeight = 1.7;
  String mode = 'Pagine'; // Pagine | Scorrimento
  String margins = 'Normali'; // Stretti | Normali | Larghi
  bool justify = true;
  bool hyphenate = false; // Android non disegna il trattino: di base spenta
  String animation = 'Arricciatura'; // Arricciatura | Scorrimento | Nessuna
  bool tapEdges = true;
  bool invertTaps = false;
  bool immersive = true;
  String orientation = 'Automatico'; // Automatico | Verticale | Orizzontale
  bool twoPages = true; // in orizzontale
  double brightness = 1.0; // 0.3 – 1.0 (velo scuro sopra la pagina)
  double warmth = 0.0; // 0 – 1 (filtro luce calda)
  bool volumeKeys = true;
  bool keepAwake = true;

  double get marginPx => margins == 'Stretti' ? 16 : (margins == 'Larghi' ? 40 : 26);

  Map<String, dynamic> toJson() => {
        'theme': theme, 'font': font, 'size': size, 'lineHeight': lineHeight, 'mode': mode, 'margins': margins,
        'justify': justify, 'hyphenate': hyphenate, 'animation': animation, 'tapEdges': tapEdges, 'invertTaps': invertTaps,
        'immersive': immersive, 'orientation': orientation, 'twoPages': twoPages, 'brightness': brightness, 'warmth': warmth,
        'volumeKeys': volumeKeys, 'keepAwake': keepAwake,
      };

  void fromJson(Map<String, dynamic> j) {
    T v<T>(String k, T d) => j[k] is T ? j[k] as T : d;
    double dbl(String k, double d) => j[k] is num ? (j[k] as num).toDouble() : d;
    theme = v('theme', theme);
    font = v('font', font);
    size = dbl('size', size);
    lineHeight = dbl('lineHeight', lineHeight);
    mode = v('mode', mode);
    margins = v('margins', margins);
    justify = v('justify', justify);
    hyphenate = v('hyphenate', hyphenate);
    animation = v('animation', animation);
    tapEdges = v('tapEdges', tapEdges);
    invertTaps = v('invertTaps', invertTaps);
    immersive = v('immersive', immersive);
    orientation = v('orientation', orientation);
    twoPages = v('twoPages', twoPages);
    brightness = dbl('brightness', brightness);
    warmth = dbl('warmth', warmth);
    volumeKeys = v('volumeKeys', volumeKeys);
    keepAwake = v('keepAwake', keepAwake);
  }
}

class AppPrefs {
  int goalMinutes = 20;
  bool reminder = false;
  int reminderHour = 21;
  int reminderMinute = 0;
  String spoiler = 'Pagina'; // Pagina | Capitolo | Libro
  String language = 'Inglese';
  String geminiModel = 'gemini-3.5-flash-lite';
  String shelfSort = 'Manuale'; // Manuale | Serie | Titolo | Ultimo letto
  String shelfFilter = 'Tutti'; // Tutti | In corso | Da leggere | Finiti
  String dividers = 'Scelti da me'; // Scelti da me | Automatici
  String shelfBg = 'Carta'; // sfondo degli scaffali delle novel
  String mangaShelfBg = 'Carta'; // sfondo degli scaffali dei manga
  bool seasonal = true; // decorazioni delle feste sugli scaffali
  /// Personalizzazione di ogni scaffale: chiave → {bg, wood, deco}
  Map<String, Map<String, dynamic>> shelfLooks = {};
  int section = 0; // 0 novel, 1 manga (ultima sezione aperta)
  String? birthday; // "MM-GG", per la decorazione del compleanno
  String? installedOn; // "AAAA-MM-GG", per l'anniversario dell'app
  bool ambient = false; // suoni d'ambiente durante la lettura
  String ambientSound = 'Automatico';
  double ambientVolume = 0.5;
  String? weatherCity; // città per il meteo della finestra
  double? weatherLat, weatherLon;
  bool cat = true; // il gatto della libreria

  Map<String, dynamic> toJson() => {
        'goalMinutes': goalMinutes, 'reminder': reminder, 'reminderHour': reminderHour, 'reminderMinute': reminderMinute,
        'spoiler': spoiler, 'language': language, 'geminiModel': geminiModel, 'shelfSort': shelfSort, 'shelfFilter': shelfFilter,
        'dividers': dividers,
        'shelfBg': shelfBg,
        'mangaShelfBg': mangaShelfBg,
        'seasonal': seasonal,
        'shelfLooks': shelfLooks,
        'section': section,
        'birthday': birthday,
        'installedOn': installedOn,
        'ambient': ambient,
        'ambientSound': ambientSound,
        'ambientVolume': ambientVolume,
        'weatherCity': weatherCity,
        'weatherLat': weatherLat,
        'weatherLon': weatherLon,
        'cat': cat,
      };

  void fromJson(Map<String, dynamic> j) {
    T v<T>(String k, T d) => j[k] is T ? j[k] as T : d;
    goalMinutes = v('goalMinutes', goalMinutes);
    reminder = v('reminder', reminder);
    reminderHour = v('reminderHour', reminderHour);
    reminderMinute = v('reminderMinute', reminderMinute);
    spoiler = v('spoiler', spoiler);
    language = v('language', language);
    geminiModel = v('geminiModel', geminiModel);
    shelfSort = v('shelfSort', shelfSort);
    shelfFilter = v('shelfFilter', shelfFilter);
    dividers = v('dividers', dividers);
    shelfBg = v('shelfBg', shelfBg);
    mangaShelfBg = v('mangaShelfBg', mangaShelfBg);
    seasonal = v('seasonal', seasonal);
    section = v('section', section);
    birthday = j['birthday'] as String?;
    installedOn = j['installedOn'] as String?;
    ambient = v('ambient', ambient);
    ambientSound = v('ambientSound', ambientSound);
    ambientVolume = (j['ambientVolume'] as num?)?.toDouble() ?? ambientVolume;
    weatherCity = j['weatherCity'] as String?;
    weatherLat = (j['weatherLat'] as num?)?.toDouble();
    weatherLon = (j['weatherLon'] as num?)?.toDouble();
    cat = v('cat', cat);
    final sl = j['shelfLooks'];
    if (sl is Map) {
      shelfLooks = {for (final e in sl.entries) if (e.value is Map) e.key as String: Map<String, dynamic>.from(e.value as Map)};
    }
  }

  /// Sfondo di uno scaffale (il suo, oppure quello generale).
  String bgFor(String key, {bool manga = false}) => (shelfLooks[key]?['bg'] as String?) ?? (manga ? mangaShelfBg : shelfBg);

  /// Legno di uno scaffale (scelto, oppure uno diverso per ogni scaffale).
  Wood woodFor(String key, [Wood? fallback]) {
    final name = shelfLooks[key]?['wood'] as String?;
    for (final w in Wood.all) {
      if (w.name == name) return w;
    }
    return fallback ?? Wood.forKey(key);
  }

  bool decoFor(String key) => seasonal && ((shelfLooks[key]?['deco'] as bool?) ?? true);
}

/// Libreria: libri, scaffale, progressi e statistiche. Tutto salvato in locale.
class LibraryStore extends ChangeNotifier {
  LibraryStore._();
  static final LibraryStore I = LibraryStore._();

  late Directory _dir;
  String get dataDir => _dir.path;
  late SharedPreferences _prefs;
  bool loaded = false;

  final List<Book> books = [];

  /// Ordine dello scaffale: "b:<idLibro>" oppure "d:<idDivisore>".
  final List<String> shelf = [];

  String readerName = '';

  /// Aspetto dell'app: Giorno, Notte o Sistema.
  String appTheme = 'Sistema';
  final ReaderPrefs reader = ReaderPrefs();
  final AppPrefs app = AppPrefs();

  /// Velocità di lettura stimata (caratteri al secondo).
  double charsPerSecond = 0;
  Map<String, int> secondsByDay = {};
  Map<String, int> chaptersByDay = {};
  Map<String, int> mangaSecondsByDay = {};
  Map<String, int> mangaChaptersByDay = {};
  Map<String, int> finishedBooks = {}; // id libro → data di fine (ms)
  int chaptersRead = 0;

  Timer? _saveTimer;

  /// Rilegge tutto da disco (dopo il ripristino di un backup).
  Future<void> reload() async {
    loaded = false;
    await load();
  }

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
    reader.mode = _prefs.getString('r.mode') ?? reader.mode;
    final rj = _prefs.getString('reader.prefs');
    if (rj != null) reader.fromJson(Map<String, dynamic>.from(jsonDecode(rj) as Map));
    if (!(_prefs.getBool('fix.hyphen') ?? false)) {
      reader.hyphenate = false;
      _prefs.setBool('fix.hyphen', true);
    }
    final aj = _prefs.getString('app.prefs');
    if (aj != null) app.fromJson(Map<String, dynamic>.from(jsonDecode(aj) as Map));
    charsPerSecond = _prefs.getDouble('speed.cps') ?? 0;
    chaptersRead = _prefs.getInt('stats.chapters') ?? 0;
    final s = _prefs.getString('stats.days');
    if (s != null) secondsByDay = Map<String, int>.from(jsonDecode(s) as Map);
    final ms = _prefs.getString('stats.mdays');
    if (ms != null) mangaSecondsByDay = Map<String, int>.from(jsonDecode(ms) as Map);
    final mc = _prefs.getString('stats.mchdays');
    if (mc != null) mangaChaptersByDay = Map<String, int>.from(jsonDecode(mc) as Map);
    final cd = _prefs.getString('stats.chdays');
    if (cd != null) chaptersByDay = Map<String, int>.from(jsonDecode(cd) as Map);
    final fb = _prefs.getString('stats.finished');
    if (fb != null) finishedBooks = Map<String, int>.from(jsonDecode(fb) as Map);
    _sagaStyles();
    if (app.installedOn == null) {
      final d = DateTime.now();
      app.installedOn = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      _prefs.setString('app.prefs', jsonEncode(app.toJson()));
    }
    loaded = true;
    notifyListeners();
    _migrate();
  }

  /// Stile del dorso uguale per tutta la saga (una volta sola per le librerie esistenti).
  void _sagaStyles() {
    if (_prefs.getBool('fix.sagaStyle') ?? false) return;
    final bySeries = <String, List<Book>>{};
    for (final b in books) {
      if (b.series != null) bySeries.putIfAbsent(b.series!, () => []).add(b);
    }
    for (final e in bySeries.entries) {
      if (e.value.every((b) => b.spineStyle == 'Tomo')) {
        final st = styleForSeries(e.key);
        for (final b in e.value) {
          b.spineStyle = st;
        }
      }
    }
    _prefs.setBool('fix.sagaStyle', true);
    save();
  }

  static String styleForSeries(String series) => SpinePalette.styles[series.toLowerCase().hashCode.abs() % SpinePalette.styles.length];

  /// Applica lo stile del dorso a tutti i volumi della stessa saga.
  void applySagaStyle(Book from) {
    if (from.series == null) return;
    for (final b in books) {
      if (b.series == from.series) b.spineStyle = from.spineStyle;
    }
    save();
    notifyListeners();
  }

  /// Libri importati con la versione 0.1: rifà l'indice raggruppando i capitoli.
  Future<void> _migrate() async {
    var changed = false;
    for (final b in books.where((b) => b.format < 3).toList()) {
      try {
        final bytes = await File(b.filePath).readAsBytes();
        final meta = await compute(_parseMeta, bytes);
        final oldHref = b.chapters.isEmpty ? null : b.chapters[b.lastChapter.clamp(0, b.chapters.length - 1)].href;
        b.chapters = meta.chapters;
        b.chapterChars = null;
        b.format = 3;
        if (b.title.contains('&')) b.title = meta.title;
        if (b.author.contains('&')) b.author = meta.author;
        final idx = oldHref == null ? -1 : b.chapters.indexWhere((c) => c.hrefs.contains(oldHref));
        b.lastChapter = idx < 0 ? 0 : idx;
        if (idx < 0) b.lastOffset = 0;
        changed = true;
      } catch (e) {
        debugPrint('Migrazione fallita per ${b.title}: $e');
      }
    }
    if (changed) {
      await _saveNow();
      notifyListeners();
    }
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
    // Libro ripristinato da un backup senza il file: rimetto l'EPUB al suo posto
    // e tengo progressi, wiki, note e statistiche.
    for (final old in books) {
      if (old.title == meta.title && old.author == meta.author && !File(old.filePath).existsSync()) {
        await File(old.filePath).parent.create(recursive: true);
        await File(old.filePath).writeAsBytes(bytes, flush: true);
        if (meta.cover != null) {
          old.coverPath ??= p.join(_dir.path, 'books', '${old.id}_cover.${meta.coverExt}');
          await File(old.coverPath!).writeAsBytes(meta.cover!, flush: true);
        }
        await _saveNow();
        notifyListeners();
        return old;
      }
    }
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final dest = p.join(_dir.path, 'books', '$id.epub');
    await File(dest).writeAsBytes(bytes, flush: true);
    String? coverPath;
    if (meta.cover != null) {
      coverPath = p.join(_dir.path, 'books', '${id}_cover.${meta.coverExt}');
      await File(coverPath).writeAsBytes(meta.cover!, flush: true);
    }
    final (spine, text) = await CoverColors.fromBytes(meta.cover);
    // stile del dorso: quello della saga, oppure uno nuovo
    String style;
    if (meta.series != null) {
      final sib = books.where((b) => b.series == meta.series).firstOrNull;
      style = sib?.spineStyle ?? styleForSeries(meta.series!);
    } else {
      style = SpinePalette.styles[id.hashCode.abs() % SpinePalette.styles.length];
    }
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
      spineStyle: style,
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

  static const singleShelf = '_single';

  /// Chiave dello scaffale di un libro: la serie, oppure lo scaffale finale dei volumi singoli.
  String groupOfBook(Book b) => (b.series == null || b.series!.trim().isEmpty) ? singleShelf : 's:${b.series!.trim().toLowerCase()}';

  /// Scaffali nell'ordine della libreria: (chiave, nome serie o null, voci "b:"/"d:").
  /// I divisori appartengono allo scaffale del libro che li precede.
  List<(String, String?, List<String>)> shelfGroups() {
    final order = <String>[];
    final titles = <String, String?>{};
    final items = <String, List<String>>{};
    String? cur;
    for (final e in shelf) {
      String key;
      if (e.startsWith('b:')) {
        final b = byId(e.substring(2));
        if (b == null) continue;
        key = groupOfBook(b);
        titles[key] ??= key == singleShelf ? null : b.series!.trim();
      } else {
        key = cur ?? singleShelf;
      }
      cur = key;
      if (!items.containsKey(key)) {
        items[key] = [];
        order.add(key);
      }
      items[key]!.add(e);
    }
    order.remove(singleShelf);
    if (items.containsKey(singleShelf)) order.add(singleShelf);
    return [
      for (final k in order)
        if (items[k]!.any((e) => e.startsWith('b:'))) (k, titles[k], items[k]!)
    ];
  }

  void addDividerToShelf(String key, String dividerId) {
    var last = -1;
    String? cur;
    for (var i = 0; i < shelf.length; i++) {
      final e = shelf[i];
      String k;
      if (e.startsWith('b:')) {
        final b = byId(e.substring(2));
        k = b == null ? (cur ?? singleShelf) : groupOfBook(b);
      } else {
        k = cur ?? singleShelf;
      }
      cur = k;
      if (k == key) last = i;
    }
    shelf.insert(last < 0 ? shelf.length : last + 1, 'd:$dividerId');
    save();
    notifyListeners();
  }

  /// Mette un oggetto decorativo in fondo a uno scaffale.
  void addObjectToShelf(String key, String name) {
    var last = -1;
    String? cur;
    for (var i = 0; i < shelf.length; i++) {
      final e = shelf[i];
      String k;
      if (e.startsWith('b:')) {
        final b = byId(e.substring(2));
        k = b == null ? (cur ?? singleShelf) : groupOfBook(b);
      } else {
        k = cur ?? singleShelf;
      }
      cur = k;
      if (k == key) last = i;
    }
    shelf.insert(last < 0 ? shelf.length : last + 1, 'o:$name');
    save();
    notifyListeners();
  }

  /// Sposta una voce di un posto a sinistra/destra restando nel suo scaffale.
  void moveInShelf(String entry, int dir) {
    final groups = shelfGroups();
    for (final g in groups) {
      final i = g.$3.indexOf(entry);
      if (i < 0) continue;
      final j = i + dir;
      if (j < 0 || j >= g.$3.length) return;
      final a = shelf.indexOf(entry), b = shelf.indexOf(g.$3[j]);
      if (a < 0 || b < 0) return;
      shelf[a] = g.$3[j];
      shelf[b] = entry;
      save();
      notifyListeners();
      return;
    }
  }

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
    if (b.chapters.isNotEmpty && chapter >= b.chapters.length - 1 && offset >= 0.97) markFinished(b);
    save(soon: true);
  }

  void addReadingTime(int seconds) {
    if (seconds <= 0) return;
    final k = _dayKey(DateTime.now());
    secondsByDay[k] = (secondsByDay[k] ?? 0) + seconds;
    _prefs.setString('stats.days', jsonEncode(secondsByDay));
  }

  /// Tempo e capitoli dei manga (statistiche separate dalle novel).
  void addMangaTime(int seconds) {
    if (seconds <= 0) return;
    final k = _dayKey(DateTime.now());
    mangaSecondsByDay[k] = (mangaSecondsByDay[k] ?? 0) + seconds;
    _prefs.setString('stats.mdays', jsonEncode(mangaSecondsByDay));
  }

  void mangaChapterFinished() {
    final k = _dayKey(DateTime.now());
    mangaChaptersByDay[k] = (mangaChaptersByDay[k] ?? 0) + 1;
    _prefs.setString('stats.mchdays', jsonEncode(mangaChaptersByDay));
  }

  void chapterFinished() {
    chaptersRead++;
    _prefs.setInt('stats.chapters', chaptersRead);
    final k = _dayKey(DateTime.now());
    chaptersByDay[k] = (chaptersByDay[k] ?? 0) + 1;
    _prefs.setString('stats.chdays', jsonEncode(chaptersByDay));
  }

  /// Segna il libro come finito (una volta sola) per il calendario e le statistiche.
  void markFinished(Book b) {
    if (finishedBooks.containsKey(b.id)) return;
    finishedBooks[b.id] = DateTime.now().millisecondsSinceEpoch;
    _prefs.setString('stats.finished', jsonEncode(finishedBooks));
    notifyListeners();
  }

  static String dayKey(DateTime d) => _dayKey(d);

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

  void saveAppPrefs() {
    _prefs.setString('app.prefs', jsonEncode(app.toJson()));
    notifyListeners();
  }

  /// Aggiorna la velocità di lettura con il tempo passato su una pagina.
  void recordPage(int chars, double seconds) {
    if (chars < 200 || seconds < 4 || seconds > 600) return;
    final cps = chars / seconds;
    if (cps < 3 || cps > 80) return;
    charsPerSecond = charsPerSecond == 0 ? cps : charsPerSecond * 0.85 + cps * 0.15;
    _prefs.setDouble('speed.cps', charsPerSecond);
  }

  int get secondsToday => secondsByDay[_dayKey(DateTime.now())] ?? 0;

  void setChapterChars(Book b, List<int> chars) {
    b.chapterChars = chars;
    save(soon: true);
  }

  void setAppTheme(String t) {
    appTheme = t;
    _prefs.setString('appTheme', t);
    notifyListeners();
  }

  void saveReaderPrefs() {
    _prefs.setString('r.theme', reader.theme);
    _prefs.setString('r.font', reader.font);
    _prefs.setDouble('r.size', reader.size);
    _prefs.setDouble('r.line', reader.lineHeight);
    _prefs.setString('r.mode', reader.mode);
    _prefs.setString('reader.prefs', jsonEncode(reader.toJson()));
    notifyListeners();
  }
}
