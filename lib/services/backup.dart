import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'annotations.dart';
import 'library_store.dart';
import 'wiki.dart';

/// Copia di sicurezza di libreria, progressi, wiki, note e statistiche (senza gli EPUB).
class Backup {
  static const _prefKeys = ['stats.days', 'stats.chdays', 'stats.mdays', 'stats.mchdays', 'manga.reader', 'manga.categories', 'stats.finished', 'stats.chapters', 'app.prefs', 'reader.prefs', 'speed.cps', 'readerName', 'app.theme', 'stats.adays', 'stats.aepdays', 'anime.history', 'anilist.user', 'anilist.name', 'anilist.avatar', 'anilist.client', 'manga.imgBridge'];

  /// Crea il file .zip da condividere (Drive, email…).
  /// Dati in più passati solo dalla sincronizzazione Drive (estensioni, accesso AniList).
  static Map<String, dynamic>? lastExtra;

  static Future<File> export({Map<String, dynamic>? extra}) async {
    final root = Directory(LibraryStore.I.dataDir);
    final arch = Archive();
    void addFile(File f, String name) {
      final bytes = f.readAsBytesSync();
      arch.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    for (final n in ['library.json', 'manga.json', 'manga_history.json', 'manga_updates.json', 'anime.json']) {
      final f = File(p.join(root.path, n));
      if (f.existsSync()) addFile(f, n);
    }
    for (final f in root.listSync().whereType<File>()) {
      final n = p.basename(f.path);
      if (n.startsWith('notes_') && n.endsWith('.json')) addFile(f, n);
    }
    final wiki = Directory(p.join(root.path, 'wiki'));
    if (wiki.existsSync()) {
      for (final f in wiki.listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(f.path, from: root.path);
        if (rel.endsWith('.tmp')) continue;
        addFile(f, rel.replaceAll('\\', '/'));
      }
    }
    // copertine (piccole): così la libreria resta bella anche prima di reimportare gli EPUB
    final books = Directory(p.join(root.path, 'books'));
    if (books.existsSync()) {
      for (final f in books.listSync().whereType<File>()) {
        if (p.basename(f.path).contains('_cover.')) addFile(f, 'books/${p.basename(f.path)}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final pj = <String, Object?>{};
    for (final k in _prefKeys) {
      final v = prefs.get(k);
      if (v != null) pj[k] = v;
    }
    final pb = utf8.encode(jsonEncode({'v': 1, 'prefs': pj, 'root': root.path, 'at': DateTime.now().toIso8601String(), if (extra != null) 'extra': extra}));
    arch.addFile(ArchiveFile('backup.json', pb.length, pb));
    final zip = ZipEncoder().encode(arch)!;
    final d = DateTime.now();
    final tmp = await getTemporaryDirectory();
    final out = File(p.join(tmp.path, 'Lorekeeper-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.zip'));
    await out.writeAsBytes(zip);
    return out;
  }

  /// Unisce due elenchi di anime (anime.json): non si perde niente da nessuna delle due parti.
  /// Per lo stesso anime vince la versione usata per ultima; gli episodi visti si sommano.
  static List<int> mergeAnime(List<int> incoming, File local) {
    if (!local.existsSync()) return incoming;
    try {
      final a = (jsonDecode(utf8.decode(incoming)) as List).cast<Map>();
      final b = (jsonDecode(local.readAsStringSync()) as List).cast<Map>();
      String k(Map j) => '${j['mid']}|${j['sid']}|${j['u']}';
      int t(Map j) => math.max((j['lw'] as num?)?.toInt() ?? 0, (j['add'] as num?)?.toInt() ?? 0);
      final out = <String, Map>{};
      for (final j in [...b, ...a]) {
        final old = out[k(j)];
        if (old == null) {
          out[k(j)] = j;
          continue;
        }
        final win = Map.of(t(j) >= t(old) ? j : old);
        win['w'] = {...((old['w'] as List?) ?? const []), ...((j['w'] as List?) ?? const [])}.toList();
        out[k(j)] = win;
      }
      return utf8.encode(jsonEncode(out.values.toList()));
    } catch (_) {
      return incoming;
    }
  }

  /// Solo alcune parti (la TV prende solo anime e AniList, senza libri né manga).
  static const animeFiles = {'anime.json'};
  static const tvFiles = {'anime.json', 'manga.json', 'manga_history.json', 'manga_updates.json'};
  static const tvPrefs = {...animePrefs, 'stats.mdays', 'stats.mchdays', 'manga.reader', 'manga.categories'};
  static const animePrefs = {'stats.adays', 'stats.aepdays', 'anime.history', 'anilist.user', 'anilist.name', 'anilist.avatar', 'anilist.client', 'manga.imgBridge'};

  /// Ripristina solo [files] e le preferenze [prefKeys] da un backup.
  static Future<Set<String>> restoreParts(String zipPath, {required Set<String> files, required Set<String> prefKeys}) async {
    final arch = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final meta = arch.findFile('backup.json');
    if (meta == null) throw Exception('Backup non valido');
    final info = jsonDecode(utf8.decode(meta.content as List<int>)) as Map;
    lastExtra = (info['extra'] as Map?)?.cast<String, dynamic>();
    final root = LibraryStore.I.dataDir;
    final found = <String>{};
    for (final n in files) {
      final f = arch.findFile(n);
      if (f == null) continue;
      found.add(n);
      final dest = File(p.join(root, n));
      var bytes = f.content as List<int>;
      if (n == 'anime.json') bytes = mergeAnime(bytes, dest);
      await dest.writeAsBytes(bytes);
    }
    final prefs = await SharedPreferences.getInstance();
    final pj = (info['prefs'] as Map?) ?? const {};
    for (final e in pj.entries) {
      final k = e.key as String, v = e.value;
      if (!prefKeys.contains(k)) continue;
      if (v is String) await prefs.setString(k, v);
      if (v is int) await prefs.setInt(k, v);
      if (v is double) await prefs.setDouble(k, v);
      if (v is bool) await prefs.setBool(k, v);
    }
    return found;
  }

  /// Prende il backup remoto e ci mette dentro solo le parti locali [files] e [prefKeys]
  /// (tutto il resto, libri e manga del telefono, resta com'è).
  static Future<List<int>> patchParts(List<int> remoteZip, {required Set<String> files, required Set<String> prefKeys}) async {
    final old = ZipDecoder().decodeBytes(remoteZip);
    final out = Archive();
    final root = LibraryStore.I.dataDir;
    final prefs = await SharedPreferences.getInstance();
    final remoteParts = <String, List<int>>{};
    for (final f in old.files) {
      if (f.isFile && files.contains(f.name)) remoteParts[f.name] = f.content as List<int>;
      if (!f.isFile || files.contains(f.name)) continue;
      if (f.name == 'backup.json') {
        final info = jsonDecode(utf8.decode(f.content as List<int>)) as Map;
        final pj = Map<String, Object?>.from((info['prefs'] as Map?) ?? const {});
        for (final k in prefKeys) {
          final v = prefs.get(k);
          if (v != null) pj[k] = v;
        }
        info['prefs'] = pj;
        info['at'] = DateTime.now().toIso8601String();
        final b = utf8.encode(jsonEncode(info));
        out.addFile(ArchiveFile('backup.json', b.length, b));
        continue;
      }
      final bytes = f.content as List<int>;
      out.addFile(ArchiveFile(f.name, bytes.length, bytes));
    }
    for (final n in files) {
      final lf = File(p.join(root, n));
      final remote = remoteParts[n];
      // mai togliere dal backup quello che c'era: al massimo si unisce
      final List<int>? b = n == 'anime.json' && remote != null
          ? mergeAnime(remote, lf)
          : (lf.existsSync() ? lf.readAsBytesSync() : remote);
      if (b == null) continue;
      out.addFile(ArchiveFile(n, b.length, b));
    }
    return ZipEncoder().encode(out)!;
  }

  /// Ripristina un backup. Gli EPUB vanno reimportati: i libri ritrovano progressi e note.
  static Future<int> restore(String zipPath) async {
    final arch = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final meta = arch.findFile('backup.json');
    if (meta == null || arch.findFile('library.json') == null) throw Exception('Questo file non è un backup di Lorekeeper');
    final info = jsonDecode(utf8.decode(meta.content as List<int>)) as Map;
    lastExtra = (info['extra'] as Map?)?.cast<String, dynamic>();
    final root = LibraryStore.I.dataDir;
    final oldRoot = (info['root'] as String?) ?? root;
    for (final f in arch.files) {
      if (!f.isFile || f.name == 'backup.json') continue;
      final dest = File(p.join(root, f.name));
      await dest.parent.create(recursive: true);
      var bytes = f.content as List<int>;
      if (f.name == 'library.json' && oldRoot != root) {
        bytes = utf8.encode(utf8.decode(bytes).replaceAll(oldRoot, root));
      }
      if (f.name == 'anime.json') bytes = mergeAnime(bytes, dest);
      await dest.writeAsBytes(bytes);
    }
    final prefs = await SharedPreferences.getInstance();
    final pj = (info['prefs'] as Map?) ?? const {};
    for (final e in pj.entries) {
      final k = e.key as String, v = e.value;
      if (v is String) await prefs.setString(k, v);
      if (v is int) await prefs.setInt(k, v);
      if (v is double) await prefs.setDouble(k, v);
      if (v is bool) await prefs.setBool(k, v);
    }
    WikiStore.I.clearCache();
    Annotations.I.clearCache();
    await LibraryStore.I.reload();
    return LibraryStore.I.books.where((b) => !File(b.filePath).existsSync()).length;
  }
}
