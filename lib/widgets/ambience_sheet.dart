import 'package:flutter/material.dart';

import '../services/ambience.dart';
import '../services/library_store.dart';
import '../services/weather.dart';
import '../theme.dart';

/// Pannello dei suoni d'ambiente (dal lettore o dalle impostazioni).
Future<void> showAmbienceSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      builder: (ctx) => const _AmbienceSheet(),
    );

class _AmbienceSheet extends StatefulWidget {
  const _AmbienceSheet();
  @override
  State<_AmbienceSheet> createState() => _AmbienceSheetState();
}

class _AmbienceSheetState extends State<_AmbienceSheet> {
  static const _icons = {
    'Automatico': Icons.auto_awesome,
    'Pioggia': Icons.water_drop_outlined,
    'Camino': Icons.local_fire_department_outlined,
    'Taverna': Icons.sports_bar_outlined,
    'Vento': Icons.air,
    'Mare': Icons.waves,
    'Notte': Icons.nightlight_outlined,
  };

  void _save() {
    LibraryStore.I.saveAppPrefs();
    Ambience.I.update();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final a = LibraryStore.I.app;
    final w = Weather.I.now;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: LK.accent,
            value: a.ambient,
            onChanged: (v) {
              a.ambient = v;
              _save();
            },
            title: Text('Suoni d\'ambiente mentre leggi', style: LK.display(17)),
            subtitle: Text('Partono quando apri un libro o un manga.', style: LK.body(12.5, color: LK.muted)),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final name in Ambience.sounds.keys)
              ChoiceChip(
                selected: a.ambientSound == name,
                selectedColor: LK.accent.withValues(alpha: 0.2),
                backgroundColor: LK.card,
                side: BorderSide(color: LK.border),
                avatar: Icon(_icons[name], size: 16, color: LK.accent),
                label: Text(name, style: LK.body(13)),
                onSelected: (_) {
                  a.ambientSound = name;
                  if (!a.ambient) a.ambient = true;
                  _save();
                },
              ),
          ]),
          if (a.ambientSound == 'Automatico')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                w != null
                    ? 'Segue il tempo vero (${w.label.toLowerCase()} a ${a.weatherCity?.split(',').first ?? 'casa'}) e l\'ora: pioggia quando piove, il camino la sera, i grilli di notte.'
                    : 'Segue l\'ora: la taverna di giorno, il camino la sera, i grilli di notte. Scegli una città nelle impostazioni per seguire anche il meteo.',
                style: LK.body(12.5, color: LK.muted, style: FontStyle.italic),
              ),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.volume_down, color: LK.muted),
            Expanded(
              child: Slider(
                value: a.ambientVolume,
                activeColor: LK.accent,
                onChanged: (v) => setState(() => a.ambientVolume = v),
                onChangeEnd: (_) => _save(),
              ),
            ),
            Icon(Icons.volume_up, color: LK.muted),
          ]),
        ]),
      ),
    );
  }
}
