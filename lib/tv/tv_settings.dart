import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../services/ambience.dart';
import '../services/anilist.dart';
import '../services/drive_sync.dart';
import '../services/library_store.dart';
import '../services/updater.dart';
import '../widgets/update_dialog.dart';
import 'tv_widgets.dart';

/// Impostazioni essenziali sulla TV, tutte raggiungibili con il telecomando.
class TvSettings extends StatefulWidget {
  const TvSettings({super.key});
  @override
  State<TvSettings> createState() => _TvSettingsState();
}

class _TvSettingsState extends State<TvSettings> {
  String? _msg;
  int? _build;

  @override
  void initState() {
    super.initState();
    Updater.currentBuild().then((b) {
      if (mounted) setState(() => _build = b);
    });
  }

  Widget _section(String title, String text, List<Widget> actions) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: const Color(0x10F3E7CF), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: tvDisplay(22)),
          const SizedBox(height: 6),
          Text(text, style: tvBody(15)),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final app = LibraryStore.I.app;
    final d = DriveSync.I;
    final al = AniList.I;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(56, 16, 56, 30), children: [
        if (_msg != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(_msg!, style: tvBody(16, color: TV.peach))),
        _section(
          'Sincronizzazione con Google Drive',
          d.enabled
              ? 'Collegato a ${d.email ?? 'Google Drive'}. ${d.status ?? (d.lastSync == null ? '' : 'Ultima sincronizzazione alle ${d.lastSync!.hour}:${d.lastSync!.minute.toString().padLeft(2, '0')}.')}'
              : 'Usa lo stesso account Google del telefono per avere qui libreria, manga, anime e progressi.',
          [
            if (!d.enabled)
              TvButton(label: 'Collega Google Drive', icon: Icons.cloud_sync_outlined, primary: true, onSelect: () => d.connect())
            else ...[
              TvButton(label: 'Sincronizza ora', icon: Icons.sync, primary: true, onSelect: () => d.sync()),
              TvButton(label: 'Scollega', onSelect: d.disconnect),
            ],
            if (d.error != null) Text(d.error!, style: tvBody(14, color: TV.peach)),
          ],
        ),
        _section(
          'AniList',
          al.loggedIn ? 'Collegato come ${al.userName ?? 'utente'}.' : 'Per collegarlo serve un browser sulla TV. In alternativa gli stati arrivano comunque con la sincronizzazione.',
          [
            if (!al.loggedIn)
              TvButton(
                label: 'Collega AniList',
                onSelect: () async {
                  try {
                    await al.login();
                  } catch (e) {
                    _msg = 'AniList: $e';
                  }
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
        _section(
          'Suoni d\'ambiente',
          app.ambient ? 'Attivi durante la lettura e i manga: ${app.ambientSound}.' : 'Disattivati.',
          [
            TvButton(
              label: app.ambient ? 'Disattiva' : 'Attiva',
              primary: !app.ambient,
              onSelect: () {
                app.ambient = !app.ambient;
                LibraryStore.I.saveAppPrefs();
                Ambience.I.update();
                setState(() {});
              },
            ),
            for (final s in Ambience.sounds.keys)
              TvButton(
                label: s,
                primary: app.ambient && app.ambientSound == s,
                onSelect: () {
                  app
                    ..ambient = true
                    ..ambientSound = s;
                  LibraryStore.I.saveAppPrefs();
                  setState(() {});
                },
              ),
          ],
        ),
        _section(
          'Aggiornamenti',
          'Versione installata: build ${_build ?? '…'}.',
          [
            TvButton(
              label: 'Cerca aggiornamenti',
              icon: Icons.system_update_alt,
              onSelect: () async {
                final u = await Updater.check();
                if (!mounted) return;
                if (u == null) {
                  setState(() => _msg = 'Hai già l\'ultima versione.');
                } else {
                  showUpdateDialog(context, u);
                }
              },
            ),
          ],
        ),
        _section('Altre impostazioni', 'Lettura, Gemini, wiki, backup e tutto il resto (versione telefono, comandabile con il telecomando).', [
          TvButton(label: 'Apri tutte le impostazioni', icon: Icons.tune, onSelect: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ]),
      ]),
    );
  }
}
