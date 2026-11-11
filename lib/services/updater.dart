import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final int build;
  final String url;
  final int size;
  final String notes;
  final DateTime? date;
  const UpdateInfo(this.build, this.url, this.size, this.notes, this.date);
}

/// Aggiornamenti dell'app dalle release di GitHub (ogni compilazione pubblica l'APK).
class Updater {
  static const repo = 'tiasimo/Lorekeeper';

  static Future<int> currentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (build ${info.buildNumber})';
  }

  /// L'ultima versione pubblicata, se è più nuova di quella installata.
  static Future<UpdateInfo?> check() async {
    final r = await http.get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('GitHub ha risposto ${r.statusCode}');
    final j = jsonDecode(r.body) as Map;
    final tag = (j['tag_name'] as String?) ?? '';
    final build = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final assets = (j['assets'] as List?) ?? const [];
    final apk = assets.cast<Map>().where((a) => (a['name'] as String? ?? '').endsWith('.apk')).firstOrNull;
    if (apk == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('update.lastCheck', DateTime.now().millisecondsSinceEpoch);
    if (build <= await currentBuild()) return null;
    return UpdateInfo(build, apk['browser_download_url'] as String, (apk['size'] as int?) ?? 0, (j['body'] as String?) ?? '', DateTime.tryParse((j['published_at'] as String?) ?? ''));
  }

  /// Controllo automatico al massimo una volta ogni 12 ore.
  static Future<UpdateInfo?> checkIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('update.lastCheck') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < 12 * 3600 * 1000) return null;
    try {
      return await check();
    } catch (_) {
      return null;
    }
  }

  /// Scarica l'APK e apre l'installazione di Android.
  static Future<void> install(UpdateInfo u, void Function(double) onProgress) async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, 'Lorekeeper-${u.build}.apk'));
    final req = await http.Client().send(http.Request('GET', Uri.parse(u.url)));
    if (req.statusCode != 200) throw Exception('Download non riuscito (${req.statusCode})');
    final total = req.contentLength ?? u.size;
    var got = 0;
    final sink = f.openWrite();
    await for (final chunk in req.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got / total);
    }
    await sink.close();
    final r = await OpenFilex.open(f.path, type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) throw Exception(r.message);
  }
}
