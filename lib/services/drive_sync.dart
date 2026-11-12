import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'anime_store.dart';
import 'anilist.dart';
import 'backup.dart';
import 'crash_log.dart';
import 'manga_store.dart';
import '../tv/tv_mode.dart';
import 'library_store.dart';

/// Sincronizzazione tra dispositivi tramite la cartella privata dell'app su Google Drive
/// (appDataFolder: invisibile in Drive, accessibile solo a Lorekeeper).
class DriveSync extends ChangeNotifier {
  DriveSync._();
  static final I = DriveSync._();

  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _dataName = 'lorekeeper-sync.zip';
  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  final _gs = GoogleSignIn(scopes: const [_scope]);
  GoogleSignInAccount? _acc;
  bool busy = false;
  String? status, error;
  DateTime? lastSync;

  String? get email => _acc?.email;
  bool get enabled => _enabled;
  bool _enabled = false;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// All'avvio: se attiva, ricollega l'account in silenzio e scarica le novità.
  Future<void> init() async {
    final prefs = await _prefs;
    _enabled = prefs.getBool('sync.on') ?? false;
    final at = prefs.getInt('sync.at');
    if (at != null) lastSync = DateTime.fromMillisecondsSinceEpoch(at);
    if (!_enabled) return;
    try {
      _acc = await _gs.signInSilently();
    } catch (_) {}
    notifyListeners();
    if (_acc != null) await sync(quiet: true);
  }

  Future<bool> connect() async {
    error = null;
    try {
      _acc = await _gs.signIn();
    } on PlatformException catch (e) {
      error = e.code == 'sign_in_failed' && '${e.message}'.contains('10')
          ? 'Google non riconosce l\'app: serve configurare il client OAuth Android (vedi istruzioni).'
          : 'Accesso non riuscito: ${e.message ?? e.code}';
    } catch (e) {
      error = 'Accesso non riuscito: $e';
    }
    if (_acc == null) {
      notifyListeners();
      return false;
    }
    _enabled = true;
    (await _prefs).setBool('sync.on', true);
    notifyListeners();
    await sync();
    return error == null;
  }

  Future<void> disconnect() async {
    try {
      await _gs.signOut();
    } catch (_) {}
    _acc = null;
    _enabled = false;
    (await _prefs).setBool('sync.on', false);
    notifyListeners();
  }

  /// Segna che qui ci sono modifiche da caricare.
  Future<void> markDirty() async => (await _prefs).setInt('sync.dirty', DateTime.now().millisecondsSinceEpoch);

  Future<Map<String, String>> _headers() async {
    _acc ??= await _gs.signInSilently();
    if (_acc == null) throw Exception('Account Google non collegato');
    return await _acc!.authHeaders;
  }

  Future<List<Map<String, dynamic>>> _list(String q) async {
    final uri = Uri.parse('$_api?spaces=appDataFolder&pageSize=1000&fields=files(id,name,size,appProperties)&q=${Uri.encodeQueryComponent(q)}');
    final r = await http.get(uri, headers: await _headers());
    if (r.statusCode != 200) throw Exception('Drive ${r.statusCode}: ${r.body}');
    return ((jsonDecode(r.body) as Map)['files'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> _put(String name, List<int> bytes, {String? id, Map<String, String>? props, String mime = 'application/octet-stream'}) async {
    final boundary = 'lk${math.Random().nextInt(1 << 32)}';
    final meta = <String, dynamic>{if (id == null) 'name': name, if (id == null) 'parents': ['appDataFolder'], if (props != null) 'appProperties': props};
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode(meta)}\r\n'))
      ..add(utf8.encode('--$boundary\r\nContent-Type: $mime\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final uri = Uri.parse(id == null ? '$_upload?uploadType=multipart' : '$_upload/$id?uploadType=multipart');
    final h = {...await _headers(), 'Content-Type': 'multipart/related; boundary=$boundary'};
    final r = id == null ? await http.post(uri, headers: h, body: body.takeBytes()) : await http.patch(uri, headers: h, body: body.takeBytes());
    if (r.statusCode >= 300) throw Exception('Drive ${r.statusCode}: ${r.body}');
  }

  Future<List<int>> _get(String id) async {
    final r = await http.get(Uri.parse('$_api/$id?alt=media'), headers: await _headers());
    if (r.statusCode != 200) throw Exception('Drive ${r.statusCode}');
    return r.bodyBytes;
  }

  void _set(String? s) {
    status = s;
    notifyListeners();
  }

  /// Confronta locale e remoto: scarica se il remoto è più recente, altrimenti carica.
  Future<void> sync({bool quiet = false, bool forcePush = false}) async {
    if (busy || !_enabled) return;
    busy = true;
    error = null;
    _set('Controllo Drive…');
    try {
      final prefs = await _prefs;
      final last = prefs.getInt('sync.at') ?? 0;
      final dirty = prefs.getInt('sync.dirty') ?? 0;
      final remote = await _list("name = '$_dataName'");
      final remoteAt = remote.isEmpty ? 0 : int.tryParse('${remote.first['appProperties']?['at']}') ?? 0;
      final remoteNewer = remoteAt > last;
      if (tvMode) {
        await _syncTv(prefs, remote, remoteAt, dirty > last || forcePush);
      } else if (remoteNewer && !forcePush && dirty <= remoteAt) {
        _set('Scarico i dati dall\'altro dispositivo…');
        final bytes = await _get(remote.first['id'] as String);
        final f = File(p.join(Directory.systemTemp.path, _dataName));
        await f.writeAsBytes(bytes);
        await Backup.restore(f.path);
        final extra = Backup.lastExtra;
        if (extra != null) unawaited(_applyExtras(extra));
        await AnimeStore.I.reload();
        await MangaStore.I.reload();
        await prefs.setInt('sync.at', remoteAt);
        await prefs.remove('sync.dirty');
        await _pullBooks();
      } else if (dirty > last || remote.isEmpty || forcePush) {
        _set('Carico i dati su Drive…');
        final now = DateTime.now().millisecondsSinceEpoch;
        final f = await Backup.export(extra: await _extras());
        await _put(_dataName, await f.readAsBytes(), id: remote.isEmpty ? null : remote.first['id'] as String, props: {'at': '$now'}, mime: 'application/zip');
        await prefs.setInt('sync.at', now);
        await prefs.remove('sync.dirty');
        await _pushBooks();
      } else {
        await _pullBooks();
      }
      lastSync = DateTime.now();
    } catch (e) {
      error = 'Sincronizzazione non riuscita: $e';
      CrashLog.add(error!);
      if (quiet) debugPrint(error);
    } finally {
      busy = false;
      _set(null);
    }
  }

  /// Esito dell'ultima sincronizzazione sulla TV (quanti anime e manga sono arrivati).
  String? tvSummary;

  /// TV: scarica sempre il backup del telefono e lo unisce (anime, manga, AniList, estensioni);
  /// poi, se sulla TV è cambiato qualcosa, rimanda indietro solo gli anime.
  Future<void> _syncTv(SharedPreferences prefs, List<Map<String, dynamic>> remote, int remoteAt, bool push) async {
    if (remote.isEmpty) {
      error = 'Su Drive non c\'è ancora niente: apri l\'app sul telefono, collega Drive e sincronizza.';
      return;
    }
    _set('Scarico anime e manga dal telefono…');
    final id = remote.first['id'] as String;
    final bytes = await _get(id);
    final f = File(p.join(Directory.systemTemp.path, _dataName));
    await f.writeAsBytes(bytes);
    final found = await Backup.restoreParts(f.path, files: Backup.tvFiles, prefKeys: Backup.tvPrefs);
    final extra = Backup.lastExtra;
    if (extra != null) unawaited(_applyExtras(extra));
    await AnimeStore.I.reload();
    await MangaStore.I.reload();
    await _importAniList();
    var at = remoteAt;
    if (push) {
      _set('Carico gli anime della TV su Drive…');
      at = DateTime.now().millisecondsSinceEpoch;
      final out = await Backup.patchParts(bytes, files: Backup.animeFiles, prefKeys: Backup.animePrefs);
      await _put(_dataName, out, id: id, props: {'at': '$at'}, mime: 'application/zip');
    }
    await prefs.setInt('sync.at', at);
    await prefs.remove('sync.dirty');
    final d = DateTime.fromMillisecondsSinceEpoch(remoteAt);
    tvSummary = '${AnimeStore.I.library.length} anime e ${MangaStore.I.library.length} manga sulla TV. '
        'Backup del telefono del ${d.day}/${d.month} alle ${d.hour}:${d.minute.toString().padLeft(2, '0')}'
        '${found.contains('anime.json') ? '' : ' (senza anime: apri l\'app sul telefono così li ricarica)'}.';
  }

  /// Sulla TV la videoteca si riempie anche con la lista AniList.
  Future<void> _importAniList() async {
    try {
      for (var i = 0; i < 10 && !AniList.I.loggedIn; i++) {
        await Future.delayed(const Duration(seconds: 1));
        await AniList.I.load();
      }
      if (!AniList.I.loggedIn) return;
      AnimeStore.I.importAniList(await AniList.I.myList(type: 'ANIME'));
    } catch (_) {}
  }

  // ---------- estensioni e AniList tra dispositivi ----------

  static const _types = {'manga': ItemType.manga, 'anime': ItemType.anime};

  /// Cosa portare sull'altro dispositivo: repository, sorgenti installate e accesso AniList.
  Future<Map<String, dynamic>> _extras() async {
    final out = <String, dynamic>{};
    await AniList.I.load();
    if (AniList.I.token != null) out['anilist'] = AniList.I.token;
    try {
      final st = MangaStore.I;
      if (!st.bridgeReady) await st.ensureBridge().timeout(const Duration(seconds: 25)).catchError((_) {});
      if (st.bridgeReady) {
        final ext = st.ext;
        out['repos'] = [
          for (final t in _types.entries)
            for (final mid in MangaStore.managers.keys)
              for (final r in ext.getReposRx(t.value, mid).value) {'t': t.key, 'mid': mid, 'url': r.url},
        ];
        out['installed'] = [
          for (final s in ext.installedMangaExtensions) {'t': 'manga', 'mid': '${s.managerId ?? s.extensionType}', 'id': s.id},
          for (final s in ext.installedAnimeExtensions) {'t': 'anime', 'mid': '${s.managerId ?? s.extensionType}', 'id': s.id},
        ];
      }
    } catch (_) {}
    return out;
  }

  /// Applica quello che arriva dall'altro dispositivo (senza toccare quello che c'è già).
  Future<void> _applyExtras(Map<String, dynamic> extra) async {
    final token = extra['anilist'] as String?;
    try {
      await AniList.I.load();
      if (token != null && !AniList.I.loggedIn) await AniList.I.adoptToken(token);
    } catch (_) {}
    final repos = (extra['repos'] as List?)?.cast<Map>() ?? const [];
    final inst = (extra['installed'] as List?)?.cast<Map>() ?? const [];
    if (repos.isEmpty && inst.isEmpty) return;
    try {
      final st = MangaStore.I;
      await st.ensureBridge();
      final ext = st.ext;
      var added = false;
      for (final r in repos) {
        final type = _types[r['t']];
        final mid = r['mid'] as String?, url = r['url'] as String?;
        if (type == null || mid == null || url == null) continue;
        if (ext.getReposRx(type, mid).value.any((x) => x.url == url)) continue;
        try {
          await ext.addRepo(url, type, mid);
          added = true;
        } catch (_) {}
      }
      if (inst.any((e) => e['mid'] == 'aniyomi') && !st.mihonReady) {
        try {
          await st.setupMihon();
        } catch (_) {}
      }
      if (added) await ext.refreshExtensions(refreshAvailableSource: true);
      for (final e in inst) {
        final anime = e['t'] == 'anime';
        final have = (anime ? ext.installedAnimeExtensions : ext.installedMangaExtensions).any((s) => s.id == e['id'] && '${s.managerId ?? s.extensionType}' == e['mid']);
        if (have) continue;
        final avail = (anime ? ext.availableAnimeExtensions : ext.availableMangaExtensions).where((s) => s.id == e['id'] && '${s.managerId ?? s.extensionType}' == e['mid']).toList();
        if (avail.isEmpty) continue;
        try {
          _set('Installo ${avail.first.name}…');
          await avail.first.install();
        } catch (_) {}
      }
      _set(null);
    } catch (_) {}
  }

  /// Gli EPUB vengono caricati una sola volta ciascuno.
  Future<void> _pushBooks() async {
    final have = {for (final f in await _list("name contains 'epub_'")) f['name'] as String};
    for (final b in LibraryStore.I.books) {
      final name = 'epub_${b.id}.epub';
      final f = File(b.filePath);
      if (have.contains(name) || !f.existsSync()) continue;
      _set('Carico «${b.title}»…');
      await _put(name, await f.readAsBytes(), mime: 'application/epub+zip');
    }
  }

  /// Scarica gli EPUB che su questo dispositivo mancano.
  Future<void> _pullBooks() async {
    final missing = LibraryStore.I.books.where((b) => !File(b.filePath).existsSync()).toList();
    if (missing.isEmpty) return;
    final files = {for (final f in await _list("name contains 'epub_'")) f['name'] as String: f['id'] as String};
    var got = 0;
    for (final b in missing) {
      final id = files['epub_${b.id}.epub'];
      if (id == null) continue;
      _set('Scarico «${b.title}»…');
      final f = File(b.filePath);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(await _get(id));
      got++;
    }
    if (got > 0) await LibraryStore.I.reload();
  }
}
