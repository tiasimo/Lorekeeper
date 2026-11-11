import 'package:home_widget/home_widget.dart';

import '../models/book.dart';
import '../widgets/manga_image.dart';
import 'library_store.dart';
import 'manga_store.dart';

/// Aggiorna il widget "Continua a leggere" della schermata Home (novel o manga, il più recente).
class HomeWidgetSync {
  static Book? lastRead() {
    final read = LibraryStore.I.books.where((b) => b.lastReadAt != null).toList()..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    return read.isEmpty ? null : read.first;
  }

  static SavedManga? lastManga() {
    final read = MangaStore.I.library.where((m) => m.lastReadAt != null).toList()..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    return read.isEmpty ? null : read.first;
  }

  /// true se l'ultima lettura è un manga.
  static bool mangaIsLatest() {
    final b = lastRead(), m = lastManga();
    if (m == null) return false;
    if (b == null) return true;
    return m.lastReadAt!.isAfter(b.lastReadAt!);
  }

  static Future<void> update() async {
    try {
      await MangaStore.I.load();
      if (mangaIsLatest()) {
        final m = lastManga()!;
        final c = m.chapters.where((c) => c.url == m.lastChapter).firstOrNull;
        await HomeWidget.saveWidgetData<String>('title', m.title);
        await HomeWidget.saveWidgetData<String>('sub', '${c?.name ?? 'Manga'} · pagina ${m.lastPage + 1}');
        await HomeWidget.saveWidgetData<int>('progress', (m.progress * 100).round());
        await HomeWidget.saveWidgetData<String>('cover', m.cover == null ? null : await MangaImages.localPath(m.cover!, sourceId: m.sourceId, managerId: m.managerId));
      } else {
        final b = lastRead();
        if (b == null) return;
        final ch = b.chapters.isEmpty ? '' : 'Cap. ${b.lastChapter + 1} di ${b.chapters.length}';
        await HomeWidget.saveWidgetData<String>('title', b.title);
        await HomeWidget.saveWidgetData<String>('sub', '$ch · ${(b.progress * 100).round()}%');
        await HomeWidget.saveWidgetData<int>('progress', (b.progress * 100).round());
        await HomeWidget.saveWidgetData<String>('cover', b.coverPath);
      }
      await HomeWidget.updateWidget(androidName: 'ContinueWidget');
    } catch (_) {}
  }
}
