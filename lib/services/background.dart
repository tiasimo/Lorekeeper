import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'library_store.dart';
import 'manga_store.dart';

const _task = 'lorekeeper-nuovi-capitoli';

/// Lavoro in background: cerca i nuovi capitoli dei manga e manda la notifica.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await LibraryStore.I.load();
      await MangaStore.I.load();
      if (MangaStore.I.library.isEmpty) return true;
      await MangaStore.I.refreshLibrary();
    } catch (e) {
      debugPrint('Controllo in background non riuscito: $e');
    }
    return true;
  });
}

class Background {
  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool('manga.bg') ?? true;

  /// Programma (o toglie) il controllo ogni 3 ore, solo con la connessione attiva.
  static Future<void> setup() async {
    try {
      await Workmanager().initialize(backgroundDispatcher);
      if (await enabled()) {
        await Workmanager().registerPeriodicTask(
          _task,
          _task,
          frequency: const Duration(hours: 3),
          constraints: Constraints(networkType: NetworkType.connected, requiresBatteryNotLow: true),
        );
      } else {
        await Workmanager().cancelByUniqueName(_task);
      }
    } catch (e) {
      debugPrint('Workmanager: $e');
    }
  }

  static Future<void> setEnabled(bool v) async {
    await (await SharedPreferences.getInstance()).setBool('manga.bg', v);
    await setup();
  }
}
