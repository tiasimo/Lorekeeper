import 'package:flutter/material.dart';

import '../services/library_store.dart';
import '../theme.dart';

/// Pannello per riordinare gli scaffali delle novel trascinandoli.
Future<void> showShelfOrder(BuildContext context) {
  final store = LibraryStore.I;
  final groups = store.shelfGroups();
  final keys = [for (final g in groups) g.$1];
  final names = {for (final g in groups) g.$1: g.$2 ?? 'Altri libri'};
  final counts = {for (final g in groups) g.$1: g.$3.where((e) => e.startsWith('b:')).length};
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: LK.paper,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Ordine degli scaffali', style: LK.display(20)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text('Tieni premuto e trascina, oppure usa le frecce.', style: LK.body(13, color: LK.muted)),
            ),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                onReorder: (from, to) {
                  if (to > from) to--;
                  set(() => keys.insert(to, keys.removeAt(from)));
                  store.reorderShelves(keys);
                },
                children: [
                  for (var i = 0; i < keys.length; i++)
                    Padding(
                      key: ValueKey(keys[i]),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ReorderableDelayedDragStartListener(
                        index: i,
                        child: Container(
                          decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: LK.border)),
                          child: Row(children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(padding: const EdgeInsets.all(14), child: Icon(Icons.drag_indicator, color: LK.muted)),
                            ),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(names[keys[i]]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(16, style: FontStyle.italic)),
                                Text('${counts[keys[i]]} volumi', style: LK.label(9.5, spacing: 0.6)),
                              ]),
                            ),
                            IconButton(
                              tooltip: 'Su',
                              onPressed: i == 0
                                  ? null
                                  : () {
                                      set(() => keys.insert(i - 1, keys.removeAt(i)));
                                      store.reorderShelves(keys);
                                    },
                              icon: Icon(Icons.keyboard_arrow_up, color: i == 0 ? LK.border : LK.ink),
                            ),
                            IconButton(
                              tooltip: 'Giù',
                              onPressed: i == keys.length - 1
                                  ? null
                                  : () {
                                      set(() => keys.insert(i + 1, keys.removeAt(i)));
                                      store.reorderShelves(keys);
                                    },
                              icon: Icon(Icons.keyboard_arrow_down, color: i == keys.length - 1 ? LK.border : LK.ink),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (store.app.shelfOrder.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextButton.icon(
                  onPressed: () {
                    store.reorderShelves(const []);
                    Navigator.pop(ctx);
                  },
                  icon: Icon(Icons.restart_alt, color: LK.muted),
                  label: Text('Torna all\'ordine automatico', style: LK.body(14, color: LK.muted)),
                ),
              ),
          ]),
        ),
      ),
    ),
  );
}
