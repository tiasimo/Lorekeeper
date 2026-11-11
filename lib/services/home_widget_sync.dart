import 'package:home_widget/home_widget.dart';

import '../models/book.dart';
import 'library_store.dart';

/// Aggiorna il widget "Continua a leggere" della schermata Home.
class HomeWidgetSync {
  static Book? lastRead() {
    final read = LibraryStore.I.books.where((b) => b.lastReadAt != null).toList()..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    return read.isEmpty ? null : read.first;
  }

  static Future<void> update() async {
    try {
      final b = lastRead();
      if (b == null) return;
      final ch = b.chapters.isEmpty ? '' : 'Cap. ${b.lastChapter + 1} di ${b.chapters.length}';
      await HomeWidget.saveWidgetData<String>('title', b.title);
      await HomeWidget.saveWidgetData<String>('sub', '$ch · ${(b.progress * 100).round()}%');
      await HomeWidget.saveWidgetData<int>('progress', (b.progress * 100).round());
      await HomeWidget.saveWidgetData<String>('cover', b.coverPath);
      await HomeWidget.updateWidget(androidName: 'ContinueWidget');
    } catch (_) {}
  }
}
