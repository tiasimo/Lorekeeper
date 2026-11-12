import 'dart:convert';
import 'dart:io';

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
  static Future<File> export() async {
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
    final pb = utf8.encode(jsonEncode({'v': 1, 'prefs': pj, 'root': root.path, 'at': DateTime.now().toIso8601String()}));
    arch.addFile(ArchiveFile('backup.json', pb.length, pb));
    final zip = ZipEncoder().encode(arch)!;
    final d = DateTime.now();
    final tmp = await getTemporaryDirectory();
    final out = File(p.join(tmp.path, 'Lorekeeper-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.zip'));
    await out.writeAsBytes(zip);
    return out;
  }

  /// Ripristina un backup. Gli EPUB vanno reimportati: i libri ritrovano progressi e note.
  static Future<int> restore(String zipPath) async {
    final arch = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final meta = arch.findFile('backup.json');
    if (meta == null || arch.findFile('library.json') == null) throw Exception('Questo file non è un backup di Lorekeeper');
    final info = jsonDecode(utf8.decode(meta.content as List<int>)) as Map;
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
