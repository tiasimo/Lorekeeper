import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../widgets/manga_image.dart';
import 'anilist.dart';
import 'cover_colors.dart';
import 'library_store.dart';
import 'manga_downloads.dart';
import 'reminders.dart';
import '../tv/tv_mode.dart';

/// Capitolo di un manga salvato.
class MChapter {
  final String url, name, number;
  final String? date, scanlator;
  MChapter({required this.url, required this.name, required this.number, this.date, this.scanlator});

  factory MChapter.from(DEpisode e) => MChapter(url: e.url ?? '', name: e.name ?? 'Capitolo ${e.episodeNumber}', number: e.episodeNumber, date: e.dateUpload, scanlator: e.scanlator);
  DEpisode toEpisode() => DEpisode(url: url, name: name, episodeNumber: number, dateUpload: date, scanlator: scanlator);

  Map<String, dynamic> toJson() => {'u': url, 'n': name, 'k': number, 'd': date, 's': scanlator};
  factory MChapter.fromJson(Map j) => MChapter(url: j['u'] as String, name: j['n'] as String, number: (j['k'] as String?) ?? '', date: j['d'] as String?, scanlator: j['s'] as String?);
}

/// Manga nella libreria, legato alla sorgente da cui viene.
class SavedManga {
  final String sourceId, managerId, sourceName;
  final String url;
  String title;
  String? cover, author, description;
  List<String> genres;
  List<MChapter> chapters;
  final Set<String> read; // url dei capitoli letti
  final Set<String> bookmarks = {}; // capitoli segnati
  // dorso (come per le novel)
  int? spineColor, spineTextColor, coverSpineColor, coverSpineTextColor;
  String spinePalette = 'cover', spineStyle = 'Tomo';
  double spineHeight = 1.0, spineWidth = 1.0;
  int? spineTitleColor;
  int newChapters = 0; // trovati all'ultimo aggiornamento
  final Set<String> categories = {};
  String? lastChapter; // url
  int lastPage;
  bool inLibrary;
  DateTime addedAt;
  DateTime? lastReadAt;
  // collegamento ad AniList
  int? anilistId;
  String? alStatus;
  int alProgress;
  double alScore;
  int? alTotal;

  SavedManga({
    required this.sourceId,
    required this.managerId,
    required this.sourceName,
    required this.url,
    required this.title,
    this.cover,
    this.author,
    this.description,
    List<String>? genres,
    List<MChapter>? chapters,
    Set<String>? read,
    this.lastChapter,
    this.lastPage = 0,
    this.inLibrary = false,
    DateTime? addedAt,
    this.lastReadAt,
    this.anilistId,
    this.alStatus,
    this.alProgress = 0,
    this.alScore = 0,
  })  : genres = genres ?? [],
        chapters = chapters ?? [],
        read = read ?? {},
        addedAt = addedAt ?? DateTime.now();

  String get key => '$managerId|$sourceId|$url';

  DMedia toMedia() => DMedia(title: title, url: url, cover: cover, description: description, author: author, genre: genres);

  /// Capitoli in ordine di lettura (dal primo all'ultimo).
  List<MChapter> get ordered {
    final list = [...chapters];
    double n(MChapter c) => double.tryParse(c.number) ?? double.nan;
    final numeric = list.where((c) => !n(c).isNaN).length >= list.length * 0.8;
    if (numeric) {
      list.sort((a, b) => (n(a).isNaN ? 0 : n(a)).compareTo(n(b).isNaN ? 0 : n(b)));
    } else {
      return list.reversed.toList(); // le sorgenti di solito elencano dal più recente
    }
    return list;
  }

  double get progress {
    if (chapters.isEmpty) return alTotal != null && alTotal! > 0 ? (alProgress / alTotal!).clamp(0.0, 1.0) : 0;
    return (chapters.where(isRead).length / chapters.length).clamp(0.0, 1.0);
  }

  /// Manga importato da AniList a cui non è ancora stata scelta una sorgente.
  bool get pending => sourceId.isEmpty;

  /// Ultimo capitolo letto (in app o su AniList).
  int get readUpTo {
    var n = alProgress;
    for (final c in chapters) {
      if (read.contains(c.url)) {
        final k = chapterNumber(c);
        if (k > n) n = k;
      }
    }
    return n;
  }

  bool isRead(MChapter c) => read.contains(c.url) || (alProgress > 0 && chapterNumber(c) <= alProgress);

  /// Capitoli che mancano: quelli dopo l'ultimo letto.
  int get unread {
    if (chapters.isEmpty) return alTotal != null && alTotal! > alProgress ? alTotal! - alProgress : 0;
    final upTo = readUpTo;
    final nums = <int>{};
    for (final c in chapters) {
      if (read.contains(c.url)) continue;
      final n = chapterNumber(c);
      if (n > upTo) nums.add(n);
    }
    return nums.length;
  }

  /// Segna come letti in app i capitoli già letti su AniList.
  void syncReadFromAniList() {
    if (alProgress <= 0) return;
    for (final c in chapters) {
      if (chapterNumber(c) <= alProgress) read.add(c.url);
    }
  }

  String? spineTitle; // titolo corto sul dorso

  /// Dorso casuale (colore e stile diversi per ogni manga), poi modificabile.
  void randomSpine() {
    final h = key.hashCode.abs();
    final pal = SpinePalette.presets[h % SpinePalette.presets.length];
    spinePalette = pal.name;
    spineColor = pal.bg;
    spineTextColor = pal.text;
    spineStyle = SpinePalette.styles[(h ~/ 7) % SpinePalette.styles.length];
    spineHeight = 0.9 + (h % 5) * 0.04;
    spineWidth = 0.9 + ((h ~/ 3) % 5) * 0.06;
  }

  /// Scaffale: 0 in corso, 1 da leggere, 2 completati.
  int get shelf {
    switch (alStatus) {
      case 'COMPLETED':
        return unread > 0 && lastReadAt != null && newChapters > 0 ? 0 : 2;
      case 'PLANNING':
        return lastReadAt == null ? 1 : 0;
      case 'CURRENT':
      case 'REPEATING':
      case 'PAUSED':
        return 0;
    }
    if (lastReadAt == null && read.isEmpty && alProgress == 0) return 1;
    if (chapters.isNotEmpty && unread == 0) return 2;
    return 0;
  }

  /// Libro "finto" per riusare dorso, animazione ed editor delle novel.
  Book? _book;
  Book get spineBook {
    final b = _book ??= Book(
      id: 'manga-${key.hashCode.toUnsigned(32)}',
      title: title,
      author: author ?? '',
      filePath: '',
      coverPath: cover != null && cover!.startsWith('/') ? cover : null,
      chapters: const [],
      spineColor: spineColor ?? 0xFF7A1E2E,
      spineTextColor: spineTextColor ?? 0xFFE8C977,
      coverSpineColor: coverSpineColor ?? spineColor ?? 0xFF7A1E2E,
      coverSpineTextColor: coverSpineTextColor ?? spineTextColor ?? 0xFFE8C977,
      addedAt: addedAt,
    );
    b
      ..title = spineTitle ?? title
      ..spineColor = spineColor ?? b.spineColor
      ..spineTextColor = spineTextColor ?? b.spineTextColor
      ..coverSpineColor = coverSpineColor ?? b.coverSpineColor
      ..coverSpineTextColor = coverSpineTextColor ?? b.coverSpineTextColor
      ..spinePalette = spinePalette
      ..spineStyle = spineStyle
      ..spineHeight = spineHeight
      ..spineWidth = spineWidth
      ..spineTitleColor = spineTitleColor
      ..lastReadAt = lastReadAt;
    return b;
  }

  void applySpine(Book b) {
    spineColor = b.spineColor;
    spineTextColor = b.spineTextColor;
    spinePalette = b.spinePalette;
    spineStyle = b.spineStyle;
    spineHeight = b.spineHeight;
    spineWidth = b.spineWidth;
    spineTitleColor = b.spineTitleColor;
    final t = b.title.trim();
    spineTitle = t.isEmpty || t == title ? null : t;
  }

  Map<String, dynamic> toJson() => {
        'sid': sourceId,
        'mid': managerId,
        'sn': sourceName,
        'url': url,
        'title': title,
        'cover': cover,
        'author': author,
        'desc': description,
        'genres': genres,
        'ch': chapters.map((c) => c.toJson()).toList(),
        'read': read.toList(),
        'last': lastChapter,
        'page': lastPage,
        'lib': inLibrary,
        'added': addedAt.millisecondsSinceEpoch,
        'readAt': lastReadAt?.millisecondsSinceEpoch,
        'al': anilistId,
        'alSt': alStatus,
        'alP': alProgress,
        'alS': alScore,
        'alT': alTotal,
        'bm': bookmarks.toList(),
        'sc': spineColor,
        'stc': spineTextColor,
        'csc': coverSpineColor,
        'cstc': coverSpineTextColor,
        'sp': spinePalette,
        'ss': spineStyle,
        'sh': spineHeight,
        'sw': spineWidth,
        'stit': spineTitleColor,
        'new': newChapters,
        'cat': categories.toList(),
        'stt': spineTitle,
      };

  factory SavedManga.fromJson(Map j) => SavedManga(
        sourceId: j['sid'] as String,
        managerId: j['mid'] as String,
        sourceName: (j['sn'] as String?) ?? '',
        url: j['url'] as String,
        title: (j['title'] as String?) ?? '',
        cover: j['cover'] as String?,
        author: j['author'] as String?,
        description: j['desc'] as String?,
        genres: ((j['genres'] as List?) ?? []).cast<String>(),
        chapters: ((j['ch'] as List?) ?? []).map((c) => MChapter.fromJson(c as Map)).toList(),
        read: ((j['read'] as List?) ?? []).cast<String>().toSet(),
        lastChapter: j['last'] as String?,
        lastPage: (j['page'] as int?) ?? 0,
        inLibrary: (j['lib'] as bool?) ?? false,
        addedAt: DateTime.fromMillisecondsSinceEpoch((j['added'] as int?) ?? 0),
        lastReadAt: j['readAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['readAt'] as int),
        anilistId: j['al'] as int?,
        alStatus: j['alSt'] as String?,
        alProgress: (j['alP'] as int?) ?? 0,
        alScore: ((j['alS'] as num?) ?? 0).toDouble(),
      )
        ..alTotal = j['alT'] as int?
        ..bookmarks.addAll(((j['bm'] as List?) ?? []).cast<String>())
        ..spineColor = j['sc'] as int?
        ..spineTextColor = j['stc'] as int?
        ..coverSpineColor = j['csc'] as int?
        ..coverSpineTextColor = j['cstc'] as int?
        ..spinePalette = (j['sp'] as String?) ?? 'cover'
        ..spineStyle = (j['ss'] as String?) ?? 'Tomo'
        ..spineHeight = ((j['sh'] as num?) ?? 1).toDouble()
        ..spineWidth = ((j['sw'] as num?) ?? 1).toDouble()
        ..spineTitleColor = j['stit'] as int?
        ..newChapters = (j['new'] as int?) ?? 0
        ..categories.addAll(((j['cat'] as List?) ?? []).cast<String>())
        ..spineTitle = j['stt'] as String?;

  /// Numero del capitolo per AniList (che conta i capitoli letti).
  int chapterNumber(MChapter c) {
    final n = double.tryParse(c.number);
    if (n != null && n > 0) return n.floor();
    final i = ordered.indexWhere((x) => x.url == c.url);
    return i < 0 ? 0 : i + 1;
  }
}

/// Voce della cronologia o delle novità.
class MangaEvent {
  final String mangaKey, chapterUrl, chapterName;
  final DateTime at;
  MangaEvent(this.mangaKey, this.chapterUrl, this.chapterName, this.at);
  Map<String, dynamic> toJson() => {'m': mangaKey, 'c': chapterUrl, 'n': chapterName, 't': at.millisecondsSinceEpoch};
  factory MangaEvent.fromJson(Map j) => MangaEvent(j['m'] as String, j['c'] as String, (j['n'] as String?) ?? '', DateTime.fromMillisecondsSinceEpoch(j['t'] as int));
}

/// Sezione Manga: estensioni (Mangayomi e Mihon/Aniyomi) tramite il runtime di AnymeX,
/// più la libreria dei manga salvati.
class MangaStore extends ChangeNotifier {
  MangaStore._();
  static final I = MangaStore._();

  static const managers = {'mangayomi': 'Mangayomi', 'aniyomi': 'Mihon / Tachiyomi'};

  final Map<String, SavedManga> _all = {};
  bool _loaded = false;
  Future<void>? _bridge;
  String? bridgeError;

  final List<MangaEvent> history = [];
  final List<MangaEvent> updates = [];
  final List<String> categoryNames = [];

  SavedManga? byKey(String k) => _all[k];

  File _f(String n) => File(p.join(LibraryStore.I.dataDir, n));

  void _saveEvents() {
    _f('manga_history.json').writeAsString(jsonEncode(history.map((e) => e.toJson()).toList()));
    _f('manga_updates.json').writeAsString(jsonEncode(updates.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadEvents() async {
    try {
      final h = _f('manga_history.json');
      if (await h.exists()) history.addAll((jsonDecode(await h.readAsString()) as List).map((e) => MangaEvent.fromJson(e as Map)));
      final u = _f('manga_updates.json');
      if (await u.exists()) updates.addAll((jsonDecode(await u.readAsString()) as List).map((e) => MangaEvent.fromJson(e as Map)));
      final prefs = await SharedPreferences.getInstance();
      categoryNames.addAll(prefs.getStringList('manga.categories') ?? const []);
    } catch (_) {}
  }

  Future<void> saveCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('manga.categories', categoryNames);
    notifyListeners();
  }

  void removeHistory(MangaEvent e) {
    history.remove(e);
    _saveEvents();
    notifyListeners();
  }

  void clearHistory() {
    history.clear();
    _saveEvents();
    notifyListeners();
  }

  /// Sposta un manga su un'altra sorgente tenendo letti, segnalibri, AniList, dorso e categorie.
  Future<SavedManga> migrate(SavedManga from, Source to, DMedia media) async {
    final dest = entry(to, media);
    await refresh(to, dest);
    final readNums = from.chapters.where((c) => from.read.contains(c.url)).map(from.chapterNumber).toSet();
    final bmNums = from.chapters.where((c) => from.bookmarks.contains(c.url)).map(from.chapterNumber).toSet();
    for (final c in dest.chapters) {
      final n = dest.chapterNumber(c);
      if (readNums.contains(n)) dest.read.add(c.url);
      if (bmNums.contains(n)) dest.bookmarks.add(c.url);
    }
    final lastNum = from.chapters.where((c) => c.url == from.lastChapter).map(from.chapterNumber).firstOrNull;
    if (lastNum != null) {
      dest.lastChapter = dest.chapters.where((c) => dest.chapterNumber(c) == lastNum).map((c) => c.url).firstOrNull;
      dest.lastPage = from.lastPage;
    }
    dest
      ..inLibrary = true
      ..addedAt = from.addedAt
      ..lastReadAt = from.lastReadAt
      ..anilistId = from.anilistId
      ..alStatus = from.alStatus
      ..alProgress = from.alProgress
      ..alScore = from.alScore
      ..alTotal = from.alTotal
      ..spineColor = from.spineColor
      ..spineTextColor = from.spineTextColor
      ..coverSpineColor = from.coverSpineColor
      ..coverSpineTextColor = from.coverSpineTextColor
      ..spinePalette = from.spinePalette
      ..spineStyle = from.spineStyle
      ..spineHeight = from.spineHeight
      ..spineWidth = from.spineWidth
      ..spineTitleColor = from.spineTitleColor;
    dest.categories.addAll(from.categories);
    from.inLibrary = false;
    save();
    return dest;
  }

  List<SavedManga> get library => _all.values.where((m) => m.inLibrary).toList()
    ..sort((a, b) => (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));

  File get _file => File(p.join(LibraryStore.I.dataDir, 'manga.json'));

  /// Rilegge tutto da disco (es. dopo una sincronizzazione).
  Future<void> reload() async {
    _loaded = false;
    _all.clear();
    history.clear();
    updates.clear();
    await load();
    notifyListeners();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (await _file.exists()) {
        final j = jsonDecode(await _file.readAsString()) as List;
        for (final m in j) {
          final sm = SavedManga.fromJson(m as Map);
          _all[sm.key] = sm;
        }
      }
    } catch (_) {}
    await _loadEvents();
    await MangaDownloads.I.loadPrefs();
    final sp = await SharedPreferences.getInstance();
    if (!(sp.getBool('manga.randomSpine') ?? false)) {
      for (final m in _all.values) {
        if (m.spinePalette == 'cover') m.randomSpine();
      }
      await sp.setBool('manga.randomSpine', true);
      save();
    }
    MangaImages.protectedSources['manga'] = () => {
          for (final m in _all.values)
            if (m.inLibrary && (m.cover ?? '').isNotEmpty) m.cover!,
        };
    // le copertine della libreria pronte su disco (in coda, dopo il resto)
    if (!tvMode) Future.delayed(const Duration(seconds: 4), () {
      for (final m in library) {
        if ((m.cover ?? '').isNotEmpty) MangaImages.prefetch([m.cover!], sourceId: m.sourceId, managerId: m.managerId);
      }
    });
    notifyListeners();
  }

  Timer? _saveTimer;
  void save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      // tengo solo i manga in libreria o letti almeno una volta
      final keep = _all.values.where((m) => m.inLibrary || m.lastReadAt != null).map((m) => m.toJson()).toList();
      await _file.writeAsString(jsonEncode(keep));
    });
    notifyListeners();
  }

  /// Avvia il motore delle estensioni (una volta sola).
  Future<void> ensureBridge() => _bridge ??= _initBridge();

  /// Il motore delle estensioni è già partito (senza avviarlo).
  bool get bridgeReady => _bridge != null && bridgeError == null;

  /// Ultimi messaggi del motore delle estensioni (per capire perché una sorgente non va).
  static final List<String> bridgeLogs = [];

  /// L'ultimo errore registrato che contiene [what] (es. 'getVideoList').
  static String? lastLog(String what) {
    for (var i = bridgeLogs.length - 1; i >= 0 && i >= bridgeLogs.length - 60; i--) {
      if (bridgeLogs[i].contains(what)) return bridgeLogs[i];
    }
    return null;
  }

  Future<void> _initBridge() async {
    AnymeXExtensionBridge.onLog = (log, show) {
      bridgeLogs.add(log.length > 1500 ? log.substring(0, 1500) : log);
      if (bridgeLogs.length > 200) bridgeLogs.removeRange(0, bridgeLogs.length - 200);
      debugPrint(log);
    };
    try {
      await AnymeXExtensionBridge.init(
        projectName: 'Lorekeeper',
        getDirectory: AnymeXExtensionBridge.defaultGetDirectory(appFolderName: 'estensioni'),
      );
      Get.find<ExtensionManager>();
      bridgeError = null;
    } catch (e) {
      bridgeError = '$e';
      _bridge = null;
      rethrow;
    }
  }

  ExtensionManager get ext => Get.find<ExtensionManager>();

  Source? sourceFor(SavedManga m) {
    for (final s in ext.installedMangaExtensions) {
      if (s.id == m.sourceId && (s.managerId ?? s.extensionType) == m.managerId) return s;
    }
    for (final s in ext.installedMangaExtensions) {
      if (s.id == m.sourceId) return s;
    }
    return null;
  }

  /// Mette in libreria tutta la lista AniList (tranne gli abbandonati). La sorgente si sceglie alla prima apertura.
  int importAniList(List<AlEntry> list) {
    var added = 0;
    final linked = {for (final m in _all.values.where((m) => m.inLibrary && m.anilistId != null)) m.anilistId!: m};
    for (final e in list) {
      final have = linked[e.media.id];
      if (have != null) {
        // aggiorno stato, progressi e voto da AniList
        have
          ..alStatus = e.status
          ..alProgress = e.progress > have.alProgress ? e.progress : have.alProgress
          ..alScore = e.score
          ..alTotal = e.media.chapters ?? have.alTotal;
        have.syncReadFromAniList();
        continue;
      }
      if (e.status == 'DROPPED') continue;
      final key = 'anilist||${e.media.id}';
      final m = _all[key] ??= (SavedManga(sourceId: '', managerId: 'anilist', sourceName: 'AniList', url: '${e.media.id}', title: e.media.title, cover: e.media.cover)..randomSpine());
      m
        ..anilistId = e.media.id
        ..alStatus = e.status
        ..alProgress = e.progress
        ..alScore = e.score
        ..alTotal = e.media.chapters;
      if (!m.inLibrary) {
        m.inLibrary = true;
        added++;
      }
    }
    save();
    return added;
  }

  /// Collega a una sorgente un manga importato da AniList: tiene stato, dorso e categorie.
  Future<SavedManga> attachSource(SavedManga from, Source to, DMedia media) async {
    final dest = entry(to, media);
    dest
      ..inLibrary = true
      ..addedAt = from.addedAt
      ..anilistId = from.anilistId
      ..alStatus = from.alStatus
      ..alProgress = from.alProgress
      ..alScore = from.alScore
      ..alTotal = from.alTotal
      ..spineColor = from.spineColor ?? dest.spineColor
      ..spineTextColor = from.spineTextColor ?? dest.spineTextColor
      ..coverSpineColor = from.coverSpineColor ?? dest.coverSpineColor
      ..coverSpineTextColor = from.coverSpineTextColor ?? dest.coverSpineTextColor
      ..spinePalette = from.spinePalette
      ..spineStyle = from.spineStyle
      ..spineHeight = from.spineHeight
      ..spineWidth = from.spineWidth
      ..spineTitleColor = from.spineTitleColor
      ..spineTitle = from.spineTitle;
    dest.categories.addAll(from.categories);
    // la copertina di AniList resta se la sorgente non ne ha una
    dest.cover ??= from.cover;
    _all.remove(from.key);
    save();
    await refresh(to, dest);
    return dest;
  }

  /// Il manga salvato corrispondente (o uno nuovo, non ancora in libreria).
  SavedManga entry(Source s, DMedia media) {
    final mid = s.managerId ?? s.extensionType;
    final key = '$mid|${s.id}|${media.url}';
    return _all[key] ??= (SavedManga(
      sourceId: s.id ?? '',
      managerId: mid,
      sourceName: s.name ?? '',
      url: media.url ?? '',
      title: media.title ?? '',
      cover: media.cover,
    )..randomSpine());
  }

  /// Aggiorna dettagli e capitoli dalla sorgente.
  Future<SavedManga> refresh(Source s, SavedManga m) async {
    final d = await s.methods.getDetail(m.toMedia());
    m.title = (d.title?.isNotEmpty ?? false) ? d.title! : m.title;
    // la copertina di AniList (server veloce, misura giusta) ha la precedenza
    if ((d.cover?.isNotEmpty ?? false) && !(m.cover ?? '').contains('anilist.co')) m.cover = d.cover;
    m.author = d.author ?? m.author;
    m.description = d.description ?? m.description;
    if (d.genre != null && d.genre!.isNotEmpty) m.genres = d.genre!;
    if (d.episodes != null && d.episodes!.isNotEmpty) m.chapters = d.episodes!.map(MChapter.from).toList();
    m.syncReadFromAniList();
    save();
    return m;
  }

  void toggleLibrary(SavedManga m) {
    m.inLibrary = !m.inLibrary;
    if (m.inLibrary) m.addedAt = DateTime.now();
    save();
  }

  void markRead(SavedManga m, MChapter c, {bool read = true}) {
    final was = m.read.contains(c.url);
    read ? m.read.add(c.url) : m.read.remove(c.url);
    save();
    if (read && !was) {
      _syncProgress(m, m.chapterNumber(c));
      LibraryStore.I.mangaChapterFinished();
      MangaDownloads.I.onRead(m, c);
    }
  }

  /// Aggiorna AniList quando finisci un capitolo (solo se vai avanti).
  Future<void> _syncProgress(SavedManga m, int chapter) async {
    final id = m.anilistId;
    final al = AniList.I;
    if (id == null || !al.loggedIn || chapter <= m.alProgress) return;
    final total = int.tryParse('${m.alTotal ?? ''}');
    var status = m.alStatus;
    if (status == null || status == 'PLANNING' || status == 'PAUSED' || status == 'DROPPED') status = 'CURRENT';
    if (total != null && total > 0 && chapter >= total && status != 'REPEATING') status = 'COMPLETED';
    try {
      await al.save(id, progress: chapter, status: status);
      m.alProgress = chapter;
      m.alStatus = status;
      save();
    } catch (e) {
      syncError = '$e';
      notifyListeners();
    }
  }

  String? syncError;

  /// Collega il manga a una voce di AniList e allinea stato, progressi e voto.
  Future<void> linkAniList(SavedManga m, AlMedia media) async {
    m.anilistId = media.id;
    m.alTotal = media.chapters;
    final e = await AniList.I.entry(media.id);
    if (e != null) {
      m.alStatus = e.status;
      m.alProgress = e.progress;
      m.alScore = e.score;
      m.syncReadFromAniList();
    } else {
      m.alStatus = null;
      m.alProgress = 0;
      m.alScore = 0;
    }
    // se in app hai letto di più, porto avanti AniList
    final readMax = m.chapters.where((c) => m.read.contains(c.url)).map(m.chapterNumber).fold<int>(0, (a, b) => b > a ? b : a);
    save();
    if (readMax > m.alProgress) await _syncProgress(m, readMax);
  }

  void unlinkAniList(SavedManga m) {
    m.anilistId = null;
    m.alStatus = null;
    m.alProgress = 0;
    m.alScore = 0;
    save();
  }

  Future<void> setAniList(SavedManga m, {String? status, double? score, int? progress}) async {
    final id = m.anilistId;
    if (id == null) return;
    await AniList.I.save(id, status: status, score: score, progress: progress);
    if (status != null) m.alStatus = status;
    if (score != null) m.alScore = score;
    if (progress != null) m.alProgress = progress;
    save();
  }

  /// Colori del dorso presi dalla copertina (la prima volta).
  final Set<String> _coloring = {};
  Future<void> ensureSpine(SavedManga m) async {
    if (m.coverSpineColor != null || (m.cover ?? '').isEmpty || _coloring.contains(m.key)) return;
    _coloring.add(m.key);
    try {
      final bytes = await MangaImages.get(m.cover!, sourceId: m.sourceId, managerId: m.managerId);
      final (bg, tx) = await CoverColors.fromBytes(bytes);
      m.coverSpineColor = bg;
      m.coverSpineTextColor = tx;
      if (m.spinePalette == 'cover') {
        m.spineColor = bg;
        m.spineTextColor = tx;
      }
      save();
    } catch (_) {
    } finally {
      _coloring.remove(m.key);
    }
  }

  // ---------- aggiornamento dei capitoli ----------
  bool refreshing = false;
  int refreshDone = 0, refreshTotal = 0;

  /// Controlla i nuovi capitoli di tutti i manga in libreria. Restituisce quanti ne ha trovati.
  Future<int> refreshLibrary() async {
    if (refreshing) return 0;
    await load();
    // prima riallineo stato e progressi da AniList (e aggiungo i manga nuovi della lista)
    await AniList.I.load();
    if (AniList.I.loggedIn) {
      try {
        importAniList(await AniList.I.myList());
      } catch (_) {}
    }
    final list = library.where((m) => !m.pending).toList();
    if (list.isEmpty) return 0;
    await ensureBridge();
    refreshing = true;
    refreshDone = 0;
    refreshTotal = list.length;
    notifyListeners();
    var found = 0;
    var i = 0;
    Future<void> worker() async {
      while (i < list.length) {
        final m = list[i++];
        final s = sourceFor(m);
        if (s != null) {
          final before = m.chapters.map((c) => c.url).toSet();
          try {
            await refresh(s, m);
            final freshList = m.chapters.where((c) => !before.contains(c.url) && !m.read.contains(c.url)).toList();
            final fresh = freshList.length;
            if (before.isNotEmpty) {
              final now = DateTime.now();
              for (final c in freshList.take(50)) {
                updates.insert(0, MangaEvent(m.key, c.url, c.name, now));
              }
              if (updates.length > 400) updates.removeRange(400, updates.length);
            }
            if (before.isNotEmpty && fresh > 0) {
              m.newChapters += fresh;
              found += fresh;
            }
          } catch (_) {}
        }
        refreshDone++;
        notifyListeners();
      }
    }

    await Future.wait([worker(), worker(), worker()]);
    refreshing = false;
    if (found > 0) {
      final names = list.where((m) => m.newChapters > 0).map((m) => '${m.title} (+${m.newChapters})').take(4).join(', ');
      Reminders.newChapters(found, names);
    }
    _saveEvents();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('manga.lastRefresh', DateTime.now().millisecondsSinceEpoch);
    save();
    return found;
  }

  /// Aggiornamento automatico: al massimo ogni 12 ore, all'apertura dell'app.
  Future<int> refreshIfDue() async {
    await load();
    await AniList.I.load();
    if (library.isEmpty && !AniList.I.loggedIn) return 0;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('manga.lastRefresh') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < 12 * 3600 * 1000) return 0;
    return refreshLibrary();
  }

  void setProgress(SavedManga m, MChapter c, int page) {
    if (history.isEmpty || history.first.chapterUrl != c.url) {
      history.removeWhere((e) => e.chapterUrl == c.url);
      history.insert(0, MangaEvent(m.key, c.url, c.name, DateTime.now()));
      if (history.length > 300) history.removeRange(300, history.length);
      _saveEvents();
    } else {
      history[0] = MangaEvent(m.key, c.url, c.name, DateTime.now());
    }
    m.lastChapter = c.url;
    m.lastPage = page;
    m.newChapters = 0;
    m.lastReadAt = DateTime.now();
    save();
  }

  /// Supporto alle estensioni Mihon/Tachiyomi (APK): scarica il runtime di AnymeX.
  bool get mihonReady {
    try {
      return AnymeXRuntimeBridge.controller.isReady.value;
    } catch (_) {
      return false;
    }
  }

  Future<void> setupMihon() async {
    await ensureBridge();
    await AnymeXRuntimeBridge.setupRuntime();
    await AnymeXRuntimeBridge.checkAndInitialize();
    await ext.onRuntimeBridgeInitialization(force: true);
    notifyListeners();
  }
}
