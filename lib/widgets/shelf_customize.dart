import 'package:flutter/material.dart';

import '../services/library_store.dart';
import '../theme.dart';
import 'seasonal.dart';
import 'shelf_backdrop.dart';
import 'spine.dart';

/// Personalizza un singolo scaffale: sfondo, legno e decorazioni delle feste.
Future<void> showShelfCustomize(BuildContext context, {required String key, required String title, bool manga = false}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: LK.paper,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final store = LibraryStore.I;
      final look = store.app.shelfLooks[key] ?? <String, dynamic>{};
      void set(String k, Object? v) {
        final m = Map<String, dynamic>.from(store.app.shelfLooks[key] ?? {});
        if (v == null) {
          m.remove(k);
        } else {
          m[k] = v;
        }
        store.app.shelfLooks[key] = m;
        store.saveAppPrefs();
        setS(() {});
      }

      final bg = look['bg'] as String?;
      final wood = look['wood'] as String?;
      final deco = (look['deco'] as bool?) ?? true;
      final season = currentSeason();
      Widget tile(String label, bool on, VoidCallback onTap, Widget preview) => GestureDetector(
            onTap: onTap,
            child: Container(
              width: 72,
              margin: const EdgeInsets.only(right: 8),
              child: Column(children: [
                Container(
                  height: 70,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: LK.paper,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: on ? LK.accent : LK.border, width: on ? 2.5 : 1),
                  ),
                  child: preview,
                ),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(11)),
              ]),
            ),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Scaffale «$title»', style: LK.display(19)),
            const SizedBox(height: 14),
            Text('SFONDO', style: LK.label(10, spacing: 1.4)),
            const SizedBox(height: 8),
            SizedBox(
              height: 98,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                tile('Predefinito', bg == null, () => set('bg', null), Center(child: Icon(Icons.auto_awesome, color: LK.muted))),
                for (final k in shelfBackdrops) tile(k, bg == k, () => set('bg', k), ShelfBackdrop(k)),
              ]),
            ),
            const SizedBox(height: 12),
            Text('LEGNO', style: LK.label(10, spacing: 1.4)),
            const SizedBox(height: 8),
            SizedBox(
              height: 98,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                tile('Automatico', wood == null, () => set('wood', null), Center(child: Icon(Icons.shuffle, color: LK.muted))),
                for (final w in Wood.all)
                  tile(
                    w.name,
                    wood == w.name,
                    () => set('wood', w.name),
                    Stack(children: [
                      Positioned(left: 4, top: 6, bottom: 6, child: ShelfSide(wood: w)),
                      Positioned(left: 4, right: 4, bottom: 10, child: ShelfBoard(wood: w)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: LK.accent,
              value: deco,
              onChanged: (v) => set('deco', v),
              title: Text('Decorazioni delle feste', style: LK.body(15)),
              subtitle: Text(
                'Cambiano da sole con le feste e le stagioni. Adesso: ${seasons[season]}',
                style: LK.body(12.5, color: LK.muted),
              ),
            ),
          ]),
        ),
      );
    }),
  );
}
