import 'package:flutter/material.dart';

import '../../services/manga_store.dart';
import '../../theme.dart';

/// Sceglie le categorie del manga (e permette di crearne di nuove).
Future<void> editMangaCategories(BuildContext context, SavedManga m) {
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final store = MangaStore.I;
      Future<void> add() async {
        final c = TextEditingController();
        final name = await showDialog<String>(
          context: ctx,
          builder: (c2) => AlertDialog(
            backgroundColor: LK.paper,
            title: Text('Nuova categoria', style: LK.display(19)),
            content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Es. Preferiti, Shonen…')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Annulla')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(c2, c.text.trim()), child: const Text('Crea')),
            ],
          ),
        );
        if (name == null || name.isEmpty || store.categoryNames.contains(name)) return;
        store.categoryNames.add(name);
        m.categories.add(name);
        await store.saveCategories();
        store.save();
        setD(() {});
      }

      return AlertDialog(
        backgroundColor: LK.paper,
        title: Text('Categorie', style: LK.display(20)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            if (store.categoryNames.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Non hai ancora categorie.', style: LK.body(14, color: LK.muted))),
            for (final c in store.categoryNames)
              CheckboxListTile(
                value: m.categories.contains(c),
                activeColor: LK.accent,
                title: Text(c, style: LK.body(15)),
                secondary: IconButton(
                  tooltip: 'Elimina la categoria',
                  icon: Icon(Icons.delete_outline, color: LK.muted, size: 20),
                  onPressed: () async {
                    store.categoryNames.remove(c);
                    for (final x in store.library) {
                      x.categories.remove(c);
                    }
                    await store.saveCategories();
                    store.save();
                    setD(() {});
                  },
                ),
                onChanged: (v) {
                  v == true ? m.categories.add(c) : m.categories.remove(c);
                  store.save();
                  setD(() {});
                },
              ),
            TextButton.icon(onPressed: add, icon: Icon(Icons.add, color: LK.accent), label: Text('Nuova categoria', style: LK.body(14, color: LK.accent))),
          ]),
        ),
        actions: [FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx), child: const Text('Fatto'))],
      );
    }),
  );
}
