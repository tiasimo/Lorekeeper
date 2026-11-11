import 'dart:convert';
import 'dart:io';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'library_store.dart';
import 'manga_store.dart';

/// Capitoli scaricati per la lettura offline.
class MangaDownloads extends ChangeNotifier {
  MangaDownloads._();
  static final I = MangaDownloads._();

  final List<(SavedManga, MChapter)> _queue = [];
  final Map<String, double> progress = {}; // url capitolo → 0..1 (in coda o in corso)
  bool _running = false;
  bool autoDelete = false;
  bool _prefsLoaded = false;

  Future<void> loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final sp = await SharedPreferences.getInstance();
    autoDelete = sp.getBool('manga.dl.autodel') ?? false;
  }

  Future<void> setAutoDelete(bool v) async {
    autoDelete = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('manga.dl.autodel', v);
    notifyListeners();
  }

  static String _h(String s) => s.hashCode.toUnsigned(32).toRadixString(16);

  Directory _dir(SavedManga m, MChapter c) => Directory(p.join(LibraryStore.I.dataDir, 'manga_dl', _h(m.key), _h(c.url)));

  bool isDownloaded(SavedManga m, MChapter c) => File(p.join(_dir(m, c).path, 'pages.json')).existsSync();

  bool isQueued(MChapter c) => progress.containsKey(c.url);

  int downloadedCount(SavedManga m) => m.chapters.where((c) => isDownloaded(m, c)).length;

  /// Pagine locali del capitolo (null se non scaricato).
  List<PageUrl>? localPages(SavedManga m, MChapter c) {
    final f = File(p.join(_dir(m, c).path, 'pages.json'));
    if (!f.existsSync()) return null;
    try {
      final names = (jsonDecode(f.readAsStringSync()) as List).cast<String>();
      return [for (final n in names) PageUrl(p.join(_dir(m, c).path, n))];
    } catch (_) {
      return null;
    }
  }

  void enqueue(SavedManga m, Iterable<MChapter> chapters) {
    for (final c in chapters) {
      if (isDownloaded(m, c) || progress.containsKey(c.url)) continue;
      _queue.add((m, c));
      progress[c.url] = 0;
    }
    notifyListeners();
    _run();
  }

  void cancel(MChapter c) {
    _queue.removeWhere((x) => x.$2.url == c.url);
    progress.remove(c.url);
    notifyListeners();
  }

  Future<void> delete(SavedManga m, MChapter c) async {
    final d = _dir(m, c);
    if (await d.exists()) await d.delete(recursive: true);
    notifyListeners();
  }

  Future<void> deleteAll(SavedManga m, {bool onlyRead = false}) async {
    for (final c in m.chapters) {
      if (onlyRead && !m.read.contains(c.url)) continue;
      if (isDownloaded(m, c)) await delete(m, c);
    }
  }

  void onRead(SavedManga m, MChapter c) {
    if (autoDelete && isDownloaded(m, c)) delete(m, c);
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    final client = http.Client();
    try {
      while (_queue.isNotEmpty) {
        final (m, c) = _queue.first;
        try {
          await _download(client, m, c);
        } catch (e) {
          debugPrint('Download non riuscito: $e');
        }
        if (_queue.isNotEmpty && _queue.first.$2.url == c.url) _queue.removeAt(0);
        progress.remove(c.url);
        notifyListeners();
      }
    } finally {
      client.close();
      _running = false;
    }
  }

  Future<void> _download(http.Client client, SavedManga m, MChapter c) async {
    await MangaStore.I.ensureBridge();
    final s = MangaStore.I.sourceFor(m);
    if (s == null) throw Exception('sorgente non installata');
    final pages = await s.methods.getPageList(c.toEpisode());
    final d = _dir(m, c);
    await d.create(recursive: true);
    final names = <String>[];
    for (var i = 0; i < pages.length; i++) {
      if (!progress.containsKey(c.url)) {
        await d.delete(recursive: true);
        return; // annullato
      }
      final pg = pages[i];
      List<int>? bytes;
      if (m.managerId == 'aniyomi' && m.sourceId.isNotEmpty) {
        try {
          bytes = await AnymeXRuntimeBridge.getImageBytes(m.sourceId, false, pg.url);
        } catch (_) {}
      }
      if (bytes == null) {
        final r = await client.get(Uri.parse(pg.url), headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
          ...?pg.headers,
        });
        if (r.statusCode != 200) throw Exception('pagina ${i + 1}: HTTP ${r.statusCode}');
        bytes = r.bodyBytes;
      }
      final name = '${(i + 1).toString().padLeft(4, '0')}.img';
      await File(p.join(d.path, name)).writeAsBytes(bytes);
      names.add(name);
      progress[c.url] = (i + 1) / pages.length;
      notifyListeners();
    }
    await File(p.join(d.path, 'pages.json')).writeAsString(jsonEncode(names));
  }
}
