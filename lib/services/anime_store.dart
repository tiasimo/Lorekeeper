import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/manga_image.dart';
import 'anilist.dart';
import '../tv/tv_mode.dart';
import 'cover_colors.dart';
import 'drive_sync.dart';
import 'library_store.dart';
import 'manga_store.dart';
import 'reminders.dart';

/// Un anime nella videoteca, legato alla sorgente da cui viene.
class SavedAnime {
  final String sourceId, managerId, sourceName;
  final String url;
  String title;
  String? cover, description;
  List<String> genres;
  List<MChapter> episodes;
  final Set<String> watched; // url degli episodi visti
  final Map<String, int> positions; // url → secondi già guardati
  String? lastEpisode; // url
  int newEpisodes = 0;
  bool inLibrary;
  DateTime addedAt;
  DateTime? lastWatchedAt;
  // AniList
  int? anilistId, malId;
  String? alStatus;
  int alProgress;
  double alScore;
  int? alTotal;
  String? banner; // immagine larga di AniList
  String? mediaStatus; // stato della serie su AniList: FINISHED, RELEASING…
  int? nextAirAt, nextAirEp; // prossimo episodio in onda (secondi dall'epoca, numero)
  String? localStatus; // stato scelto a mano quando AniList non c'è (stessi valori di alStatus)
  // colore della custodia (preso dalla copertina)
  int? caseColor;
  String caseStyle = 'Blu-ray'; // Blu-ray | 4K | Steelbook

  SavedAnime({
    required this.sourceId,
    required this.managerId,
    required this.sourceName,
    required this.url,
    required this.title,
    this.cover,
    this.description,
    List<String>? genres,
    List<MChapter>? episodes,
    Set<String>? watched,
    Map<String, int>? positions,
    this.lastEpisode,
    this.inLibrary = false,
    DateTime? addedAt,
    this.lastWatchedAt,
    this.anilistId,
    this.malId,
    this.alStatus,
    this.alProgress = 0,
    this.alScore = 0,
    this.alTotal,
  })  : genres = genres ?? [],
        episodes = episodes ?? [],
        watched = watched ?? {},
        positions = positions ?? {},
        addedAt = addedAt ?? DateTime.now();

  String get key => '$managerId|$sourceId|$url';

  /// Importato da AniList: la sorgente si sceglie alla prima apertura.
  bool get pending => sourceId.isEmpty;

  DMedia toMedia() => DMedia(title: title, url: url, cover: cover, description: description, genre: genres);

  /// Episodi in ordine (dal primo all'ultimo).
  List<MChapter> get ordered {
    final list = [...episodes];
    double n(MChapter c) => double.tryParse(c.number) ?? double.nan;
    if (list.where((c) => !n(c).isNaN).length >= list.length * 0.8) {
      list.sort((a, b) => (n(a).isNaN ? 0 : n(a)).compareTo(n(b).isNaN ? 0 : n(b)));
    } else {
      return list.reversed.toList();
    }
    return list;
  }

  int numberOf(MChapter c) {
    final n = double.tryParse(c.number);
    if (n != null && n > 0) return n.floor();
    return ordered.indexWhere((e) => e.url == c.url) + 1;
  }

  /// Fin dove sei arrivato (anche con quello che risulta su AniList).
  int get watchedUpTo {
    final local = episodes.where((c) => watched.contains(c.url)).map(numberOf).fold<int>(0, math.max);
    return math.max(local, alProgress);
  }

  bool isWatched(MChapter c) => watched.contains(c.url) || numberOf(c) <= alProgress;

  int get total => episodes.isNotEmpty ? episodes.length : (alTotal ?? 0);
  int get unwatched => math.max(0, total - watchedUpTo);

  /// Il prossimo episodio da guardare.
  MChapter? get next {
    final o = ordered;
    if (o.isEmpty) return null;
    final cur = o.where((c) => c.url == lastEpisode).firstOrNull;
    if (cur != null && !isWatched(cur)) return cur;
    return o.where((c) => !isWatched(c)).firstOrNull ?? o.last;
  }

  /// Lo stato nella lista: quello di AniList, altrimenti quello scelto a mano.
  String? get listStatus => alStatus ?? localStatus;

  /// Sezione sulla TV: 0 sul lettore, 1 prossimamente, 2 collezione, 3 abbandonati.
  /// Senza uno stato esplicito un anime non finisce mai da solo in collezione.
  int get section {
    switch (listStatus) {
      case 'COMPLETED':
        return 2;
      case 'DROPPED':
        return 3;
      case 'PLANNING':
        return 1;
      case 'CURRENT':
      case 'REPEATING':
      case 'PAUSED':
        return 0;
    }
    return watchedUpTo == 0 && lastWatchedAt == null ? 1 : 0;
  }

  /// Il primo episodio non ancora visto (null se li hai visti tutti).
  MChapter? get firstUnwatched {
    final o = ordered;
    final cur = o.where((c) => c.url == lastEpisode).firstOrNull;
    if (cur != null && !isWatched(cur)) return cur;
    return o.where((c) => !isWatched(c)).firstOrNull;
  }

  /// Quando esce il prossimo episodio (null se non è in onda o la data è passata).
  DateTime? get nextAir {
    if (nextAirAt == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(nextAirAt! * 1000);
    return d.isAfter(DateTime.now()) ? d : null;
  }

  /// 0 in corso, 1 da guardare, 2 completati (lo stato AniList ha la precedenza).
  int get shelf {
    switch (alStatus) {
      case 'COMPLETED':
        return 2;
      case 'PLANNING':
        return 1;
      case 'CURRENT':
      case 'REPEATING':
        return 0;
    }
    if (total > 0 && watchedUpTo >= total) return 2;
    if (watchedUpTo == 0 && lastWatchedAt == null) return 1;
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'sid': sourceId, 'mid': managerId, 'sn': sourceName, 'u': url, 't': title, 'c': cover, 'd': description, 'g': genres,
        'e': episodes.map((e) => e.toJson()).toList(), 'w': watched.toList(), 'pos': positions, 'le': lastEpisode, 'ne': newEpisodes,
        'lib': inLibrary, 'add': addedAt.millisecondsSinceEpoch, 'lw': lastWatchedAt?.millisecondsSinceEpoch,
        'al': anilistId, 'mal': malId, 'als': alStatus, 'alp': alProgress, 'alsc': alScore, 'alt': alTotal, 'cc': caseColor, 'cs': caseStyle,
        if (banner != null) 'bn': banner, if (mediaStatus != null) 'alms': mediaStatus, if (nextAirAt != null) 'nxa': nextAirAt, if (nextAirEp != null) 'nxe': nextAirEp,
        if (localStatus != null) 'ls': localStatus,
      };

  factory SavedAnime.fromJson(Map j) => SavedAnime(
        sourceId: j['sid'] as String? ?? '',
        managerId: j['mid'] as String? ?? '',
        sourceName: j['sn'] as String? ?? '',
        url: j['u'] as String? ?? '',
        title: j['t'] as String? ?? '',
        cover: j['c'] as String?,
        description: j['d'] as String?,
        genres: ((j['g'] as List?) ?? const []).cast<String>(),
        episodes: ((j['e'] as List?) ?? const []).map((e) => MChapter.fromJson(e as Map)).toList(),
        watched: ((j['w'] as List?) ?? const []).cast<String>().toSet(),
        positions: Map<String, int>.from((j['pos'] as Map?) ?? const {}),
        lastEpisode: j['le'] as String?,
        inLibrary: j['lib'] as bool? ?? false,
        addedAt: DateTime.fromMillisecondsSinceEpoch(j['add'] as int? ?? 0),
        lastWatchedAt: j['lw'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['lw'] as int),
        anilistId: j['al'] as int?,
        malId: j['mal'] as int?,
        alStatus: j['als'] as String?,
        alProgress: j['alp'] as int? ?? 0,
        alScore: (j['alsc'] as num?)?.toDouble() ?? 0,
        alTotal: j['alt'] as int?,
      )
        ..newEpisodes = j['ne'] as int? ?? 0
        ..caseColor = j['cc'] as int?
        ..caseStyle = j['cs'] as String? ?? 'Blu-ray'
        ..banner = j['bn'] as String?
        ..mediaStatus = j['alms'] as String?
        ..nextAirAt = j['nxa'] as int?
        ..nextAirEp = j['nxe'] as int?
        ..localStatus = j['ls'] as String?;
}

/// Sezione Anime: estensioni anime (Mangayomi e Aniyomi) con lo stesso motore dei manga,
/// la videoteca, AniList e il controllo dei nuovi episodi.
class AnimeStore extends ChangeNotifier {
  AnimeStore._();
  static final I = AnimeStore._();

  final Map<String, SavedAnime> _all = {};
  bool _loaded = false;
  final List<MangaEvent> history = []; // episodi guardati di recente

  ExtensionManager get ext => MangaStore.I.ext;
  Future<void> ensureBridge() => MangaStore.I.ensureBridge();

  File get _file => File(p.join(LibraryStore.I.dataDir, 'anime.json'));

  List<SavedAnime> get library => _all.values.where((a) => a.inLibrary).toList()
    ..sort((a, b) => (b.lastWatchedAt ?? b.addedAt).compareTo(a.lastWatchedAt ?? a.addedAt));

  SavedAnime? byKey(String k) => _all[k];

  /// Rilegge tutto da disco (es. dopo una sincronizzazione).
  Future<void> reload() async {
    _loaded = false;
    _all.clear();
    history.clear();
    await load();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (await _file.exists()) {
        for (final j in jsonDecode(await _file.readAsString()) as List) {
          final a = SavedAnime.fromJson(j as Map);
          _all[a.key] = a;
        }
      }
      final sp = await SharedPreferences.getInstance();
      final h = sp.getString('anime.history');
      if (h != null) history.addAll((jsonDecode(h) as List).map((e) => MangaEvent.fromJson(e as Map)));
    } catch (_) {}
    // le copertine della videoteca non si cancellano mai dalla cache
    MangaImages.protectedSources['anime'] = () => {
          for (final a in _all.values)
            if (a.inLibrary && (a.cover ?? '').isNotEmpty) a.cover!,
        };
    notifyListeners();
  }

  Timer? _saveTimer;
  void save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      final keep = _all.values.where((a) => a.inLibrary || a.lastWatchedAt != null).map((a) => a.toJson()).toList();
      await _file.writeAsString(jsonEncode(keep));
      if (tvMode && DriveSync.I.enabled) await DriveSync.I.markDirty();
    });
    notifyListeners();
  }

  Source? sourceFor(SavedAnime a) {
    final list = ext.installedAnimeExtensions;
    for (final s in list) {
      if (s.id == a.sourceId && (s.managerId ?? s.extensionType) == a.managerId) return s;
    }
    for (final s in list) {
      if (s.id == a.sourceId) return s;
    }
    return null;
  }

  SavedAnime entry(Source s, DMedia media) {
    final mid = s.managerId ?? s.extensionType;
    final key = '$mid|${s.id}|${media.url}';
    return _all[key] ??= SavedAnime(sourceId: s.id ?? '', managerId: '$mid', sourceName: s.name ?? '', url: media.url ?? '', title: media.title ?? '', cover: media.cover);
  }

  Future<SavedAnime> refresh(Source s, SavedAnime a) async {
    final d = await s.methods.getDetail(a.toMedia());
    if (d.title?.isNotEmpty ?? false) a.title = d.title!;
    if ((d.cover?.isNotEmpty ?? false) && !(a.cover ?? '').contains('anilist.co')) a.cover = d.cover;
    a.description = d.description ?? a.description;
    if (d.genre != null && d.genre!.isNotEmpty) a.genres = d.genre!;
    if (d.episodes != null && d.episodes!.isNotEmpty) {
      a.episodes = d.episodes!.map((e) => MChapter(url: e.url ?? '', name: e.name ?? 'Episodio ${e.episodeNumber}', number: e.episodeNumber, date: e.dateUpload)).toList();
    }
    save();
    return a;
  }

  void toggleLibrary(SavedAnime a) {
    a.inLibrary = !a.inLibrary;
    if (a.inLibrary) a.addedAt = DateTime.now();
    save();
  }

  /// Salva il punto in cui sei arrivato in un episodio.
  void setPosition(SavedAnime a, MChapter c, int seconds) {
    if (tvMode) {
      // sulla TV iniziare un episodio mette il disco «sul lettore»
      if (!a.inLibrary) {
        a.inLibrary = true;
        a.addedAt = DateTime.now();
      }
      final st = a.listStatus;
      if (st == 'PLANNING' || st == 'PAUSED' || st == 'DROPPED' || (st == null && a.anilistId != null)) setStatus(a, 'CURRENT');
    }
    a.positions[c.url] = seconds;
    a.lastEpisode = c.url;
    a.lastWatchedAt = DateTime.now();
    a.newEpisodes = 0;
    if (history.isEmpty || history.first.chapterUrl != c.url) {
      history.removeWhere((e) => e.chapterUrl == c.url);
      history.insert(0, MangaEvent(a.key, c.url, c.name, DateTime.now()));
      if (history.length > 200) history.removeRange(200, history.length);
      _saveHistory();
    }
    save();
  }

  Future<void> _saveHistory() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('anime.history', jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  void markWatched(SavedAnime a, MChapter c, {bool watched = true}) {
    final was = a.watched.contains(c.url);
    watched ? a.watched.add(c.url) : a.watched.remove(c.url);
    if (watched) a.positions.remove(c.url);
    save();
    if (watched && !was) {
      LibraryStore.I.animeEpisodeFinished();
      _syncProgress(a, a.numberOf(c));
    }
  }

  String? syncError;

  Future<void> _syncProgress(SavedAnime a, int ep) async {
    final id = a.anilistId;
    final al = AniList.I;
    if (id == null || !al.loggedIn || ep <= a.alProgress) return;
    var status = a.alStatus;
    if (status == null || status == 'PLANNING' || status == 'PAUSED' || status == 'DROPPED') status = 'CURRENT';
    final total = a.alTotal;
    if (total != null && total > 0 && ep >= total && status != 'REPEATING') status = 'COMPLETED';
    try {
      await al.save(id, progress: ep, status: status);
      a.alProgress = ep;
      a.alStatus = status;
      a.localStatus = status;
      save();
    } catch (e) {
      syncError = '$e';
      notifyListeners();
    }
  }

  /// Sposta un anime in una sezione (CURRENT, PLANNING, COMPLETED, PAUSED, DROPPED) e lo dice ad AniList.
  Future<void> setStatus(SavedAnime a, String status) async {
    if (!a.inLibrary) {
      a.inLibrary = true;
      a.addedAt = DateTime.now();
    }
    a.localStatus = status;
    final id = a.anilistId;
    if (id != null) a.alStatus = status;
    save();
    if (id == null || !AniList.I.loggedIn) return;
    try {
      await AniList.I.save(id, status: status);
      syncError = null;
    } catch (e) {
      syncError = '$e';
      notifyListeners();
    }
  }

  /// Toglie un anime dalla lista (anche da quella di AniList, se è collegato).
  Future<void> removeFromList(SavedAnime a) async {
    a.inLibrary = false;
    a.localStatus = null;
    final id = a.anilistId;
    if (id != null && AniList.I.loggedIn) {
      try {
        await AniList.I.remove(id);
        a.alStatus = null;
        a.alProgress = 0;
      } catch (e) {
        syncError = '$e';
      }
    }
    save();
  }

  void _applyMedia(SavedAnime a, AlMedia m) {
    a
      ..malId = m.idMal ?? a.malId
      ..alTotal = m.episodes ?? a.alTotal
      ..banner = m.banner ?? a.banner
      ..mediaStatus = m.status ?? a.mediaStatus
      ..nextAirAt = m.nextAiringAt
      ..nextAirEp = m.nextAiringEp;
  }

  Future<void> linkAniList(SavedAnime a, AlMedia media) async {
    a
      ..anilistId = media.id
      ..malId = media.idMal
      ..alTotal = media.episodes;
    _applyMedia(a, media);
    final e = await AniList.I.entry(media.id);
    a
      ..alStatus = e?.status
      ..alProgress = e?.progress ?? 0
      ..alScore = e?.score ?? 0;
    save();
    final local = a.episodes.where((c) => a.watched.contains(c.url)).map(a.numberOf).fold<int>(0, math.max);
    if (local > a.alProgress) await _syncProgress(a, local);
  }

  Future<void> setAniList(SavedAnime a, {String? status, double? score}) async {
    final id = a.anilistId;
    if (id == null) return;
    await AniList.I.save(id, status: status, score: score);
    if (status != null) a.alStatus = status;
    if (score != null) a.alScore = score;
    save();
  }

  /// Mette in videoteca la lista anime di AniList (tranne gli abbandonati).
  int importAniList(List<AlEntry> list) {
    var added = 0;
    final linked = {for (final a in _all.values.where((a) => a.inLibrary && a.anilistId != null)) a.anilistId!: a};
    for (final e in list) {
      final have = linked[e.media.id];
      if (have != null) {
        have
          ..alStatus = e.status
          ..alProgress = math.max(e.progress, have.alProgress)
          ..alScore = e.score;
        _applyMedia(have, e.media);
        continue;
      }
      // sulla TV anche gli abbandonati hanno il loro ripiano
      if (e.status == 'DROPPED' && !tvMode) continue;
      final key = 'anilist||${e.media.id}';
      final a = _all[key] ??= SavedAnime(sourceId: '', managerId: 'anilist', sourceName: 'AniList', url: '${e.media.id}', title: e.media.title, cover: e.media.cover);
      a
        ..anilistId = e.media.id
        ..malId = e.media.idMal
        ..alStatus = e.status
        ..alProgress = e.progress
        ..alScore = e.score
        ..alTotal = e.media.episodes;
      _applyMedia(a, e.media);
      if (!a.inLibrary) {
        a.inLibrary = true;
        added++;
      }
    }
    save();
    return added;
  }

  /// Collega a una sorgente un anime importato da AniList.
  Future<SavedAnime> attachSource(SavedAnime from, Source to, DMedia media) async {
    final dest = entry(to, media);
    dest
      ..inLibrary = true
      ..addedAt = from.addedAt
      ..anilistId = from.anilistId
      ..malId = from.malId
      ..alStatus = from.alStatus
      ..alProgress = from.alProgress
      ..alScore = from.alScore
      ..alTotal = from.alTotal
      ..banner = from.banner
      ..mediaStatus = from.mediaStatus
      ..nextAirAt = from.nextAirAt
      ..nextAirEp = from.nextAirEp
      ..localStatus = from.localStatus
      ..caseColor = from.caseColor ?? dest.caseColor
      ..caseStyle = from.caseStyle;
    dest.cover ??= from.cover;
    if (from.key != dest.key) _all.remove(from.key);
    save();
    await refresh(to, dest);
    return dest;
  }

  /// Colore della custodia preso dalla copertina (una volta).
  final Set<String> _coloring = {};
  Future<void> ensureColor(SavedAnime a) async {
    if (a.caseColor != null || (a.cover ?? '').isEmpty || _coloring.contains(a.key)) return;
    _coloring.add(a.key);
    try {
      final bytes = await MangaImages.get(a.cover!, sourceId: a.sourceId, managerId: a.managerId);
      final (bg, _) = await CoverColors.fromBytes(bytes);
      a.caseColor = bg;
      save();
    } catch (_) {
    } finally {
      _coloring.remove(a.key);
    }
  }

  // ---------- nuovi episodi ----------
  bool refreshing = false;

  Future<int> refreshLibrary() async {
    if (refreshing) return 0;
    await load();
    await AniList.I.load();
    if (AniList.I.loggedIn) {
      try {
        importAniList(await AniList.I.myList(type: 'ANIME'));
      } catch (_) {}
    }
    // sulla TV si controllano solo i dischi sul lettore, uno alla volta
    final list = library.where((a) => !a.pending && (!tvMode || a.section == 0)).toList();
    if (list.isEmpty) return 0;
    await ensureBridge();
    refreshing = true;
    notifyListeners();
    var found = 0, i = 0;
    Future<void> worker() async {
      while (i < list.length) {
        final a = list[i++];
        final s = sourceFor(a);
        if (s == null) continue;
        final before = a.episodes.map((c) => c.url).toSet();
        try {
          await refresh(s, a);
          final fresh = a.episodes.where((c) => !before.contains(c.url) && !a.isWatched(c)).length;
          if (before.isNotEmpty && fresh > 0) {
            a.newEpisodes += fresh;
            found += fresh;
          }
        } catch (_) {}
      }
    }

    await Future.wait(tvMode ? [worker()] : [worker(), worker(), worker()]);
    refreshing = false;
    if (found > 0) {
      final names = list.where((a) => a.newEpisodes > 0).map((a) => '${a.title} (+${a.newEpisodes})').take(4).join(', ');
      Reminders.newChapters(found, names, anime: true);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('anime.lastRefresh', DateTime.now().millisecondsSinceEpoch);
    save();
    return found;
  }

  Future<int> refreshIfDue() async {
    await load();
    final sp = await SharedPreferences.getInstance();
    final last = sp.getInt('anime.lastRefresh') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < 12 * 3600 * 1000) return 0;
    return refreshLibrary();
  }
}
