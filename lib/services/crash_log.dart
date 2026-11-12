import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiene gli ultimi errori dell'app in un file, per poterli leggere dalle impostazioni
/// (sulla TV non c'è altro modo di vedere cosa è andato storto).
class CrashLog {
  static File? _file;
  static final lines = <String>[];

  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/errori.log');
      if (await _file!.exists()) {
        final all = await _file!.readAsLines();
        lines.addAll(all.length > 200 ? all.sublist(all.length - 200) : all);
      }
      add('— avvio dell\'app —');
    } catch (_) {}
  }

  static String? _last;

  static void add(String text) {
    // lo stesso errore ripetuto a ogni fotogramma si scrive una volta sola
    if (text == _last) return;
    _last = text;
    final d = DateTime.now();
    final stamp = '${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    final short = text.length > 600 ? '${text.substring(0, 600)}…' : text;
    lines.add('$stamp  ${short.replaceAll('\n', ' ⏎ ')}');
    while (lines.length > 200) {
      lines.removeAt(0);
    }
    try {
      _file?.writeAsStringSync('${lines.join('\n')}\n');
    } catch (_) {}
  }

  static void clear() {
    lines.clear();
    try {
      _file?.writeAsStringSync('');
    } catch (_) {}
  }
}
