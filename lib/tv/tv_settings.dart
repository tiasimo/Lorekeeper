import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';

import '../screens/manga/manga_home.dart';
import '../services/anilist.dart';
import '../services/anime_store.dart';
import '../services/crash_log.dart';
import '../services/drive_sync.dart';
import '../services/manga_store.dart';
import '../services/updater.dart';
import '../widgets/update_dialog.dart';
import 'tv_widgets.dart';

/// Impostazioni della TV, tutte raggiungibili con il telecomando.
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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        color: TV.panel,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: tvDisplay(20, spacing: 2)),
          const SizedBox(height: 8),
          Text(text, style: tvBody(14)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = DriveSync.I;
    final al = AniList.I;
    return ListenableBuilder(
      listenable: Listenable.merge([d, al]),
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(48, 10, 48, 24), children: [
        if (_msg != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(_msg!, style: tvBody(16, color: TV.peach))),
        _section(
          'Sincronizzazione con Google Drive',
          d.enabled
              ? 'Collegato a ${d.email ?? 'Google Drive'}. ${d.status ?? (d.lastSync == null ? '' : 'Ultima sincronizzazione alle ${d.lastSync!.hour}:${d.lastSync!.minute.toString().padLeft(2, '0')}.')}${d.tvSummary == null ? '' : '\n${d.tvSummary}'}'
              : 'Usa lo stesso account Google del telefono: sulla TV arrivano gli anime, AniList e le estensioni anime (niente libri né manga, così non occupa spazio).',
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
          al.loggedIn
              ? 'Collegato come ${al.userName ?? 'utente'}. Le sezioni (Sul lettore, Prossimamente, Collezione) seguono la tua lista AniList.'
              : 'Sulla TV non c\'è un browser per l\'accesso: collega AniList sul telefono e sincronizza con Google Drive, l\'accesso arriva qui da solo.',
          [
            if (al.loggedIn)
              TvButton(
                label: 'Aggiorna la lista',
                icon: Icons.sync,
                onSelect: () async {
                  try {
                    final n = AnimeStore.I.importAniList(await al.myList(type: 'ANIME'));
                    if (mounted) setState(() => _msg = n == 0 ? 'Lista AniList aggiornata.' : 'Lista AniList aggiornata: $n anime nuovi.');
                  } catch (e) {
                    if (mounted) setState(() => _msg = 'AniList non risponde: $e');
                  }
                },
              ),
            if (!al.loggedIn && d.enabled) TvButton(label: 'Prendi l\'accesso dal telefono', icon: Icons.sync, primary: true, onSelect: () => d.sync()),
          ],
        ),
        _section(
          'Estensioni e fonti',
          'Le fonti da cui arrivano gli episodi. Con Google Drive si installano da sole quelle del telefono; qui puoi aggiungerne o toglierne.',
          [
            TvButton(
              label: 'Apri le estensioni',
              icon: Icons.extension_outlined,
              onSelect: () async {
                try {
                  await MangaStore.I.ensureBridge();
                } catch (_) {}
                if (!context.mounted) return;
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TvExtensionsPage()));
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
                if (!context.mounted) return;
                if (u == null) {
                  setState(() => _msg = 'Hai già l\'ultima versione.');
                } else {
                  showUpdateDialog(context, u);
                }
              },
            ),
          ],
        ),
        _section(
          'Errori recenti',
          CrashLog.lines.isEmpty ? 'Nessun errore registrato.' : 'Se l\'app si blocca o si chiude, fai una foto a queste righe e mandamela.\n\n${CrashLog.lines.reversed.take(10).join('\n')}',
          [
            if (CrashLog.lines.isNotEmpty) TvButton(label: 'Cancella', icon: Icons.delete_outline, onSelect: () => setState(CrashLog.clear)),
          ],
        ),
      ]),
    );
  }
}

/// Repository e fonti anime installate su questa TV (lo stesso pannello del telefono).
class TvExtensionsPage extends StatelessWidget {
  const TvExtensionsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: const ExtensionsPanel(type: ItemType.anime)),
          ),
        ),
      );
}
