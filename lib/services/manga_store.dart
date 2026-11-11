import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'anilist.dart';
import 'library_store.dart';

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

  double get progress => chapters.isEmpty ? 0 : read.length / chapters.length;

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
      )..alTotal = j['alT'] as int?;

  /// Numero del capitolo per AniList (che conta i capitoli letti).
  int chapterNumber(MChapter c) {
    final n = double.tryParse(c.number);
    if (n != null && n > 0) return n.floor();
    final i = ordered.indexWhere((x) => x.url == c.url);
    return i < 0 ? 0 : i + 1;
  }
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

  List<SavedManga> get library => _all.values.where((m) => m.inLibrary).toList()
    ..sort((a, b) => (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));

  File get _file => File(p.join(LibraryStore.I.dataDir, 'manga.json'));

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

  Future<void> _initBridge() async {
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

  /// Il manga salvato corrispondente (o uno nuovo, non ancora in libreria).
  SavedManga entry(Source s, DMedia media) {
    final mid = s.managerId ?? s.extensionType;
    final key = '$mid|${s.id}|${media.url}';
    return _all[key] ??= SavedManga(
      sourceId: s.id ?? '',
      managerId: mid,
      sourceName: s.name ?? '',
      url: media.url ?? '',
      title: media.title ?? '',
      cover: media.cover,
    );
  }

  /// Aggiorna dettagli e capitoli dalla sorgente.
  Future<SavedManga> refresh(Source s, SavedManga m) async {
    final d = await s.methods.getDetail(m.toMedia());
    m.title = (d.title?.isNotEmpty ?? false) ? d.title! : m.title;
    m.cover = (d.cover?.isNotEmpty ?? false) ? d.cover : m.cover;
    m.author = d.author ?? m.author;
    m.description = d.description ?? m.description;
    if (d.genre != null && d.genre!.isNotEmpty) m.genres = d.genre!;
    if (d.episodes != null && d.episodes!.isNotEmpty) m.chapters = d.episodes!.map(MChapter.from).toList();
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
    if (read && !was) _syncProgress(m, m.chapterNumber(c));
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

  void setProgress(SavedManga m, MChapter c, int page) {
    m.lastChapter = c.url;
    m.lastPage = page;
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
