import 'package:flutter/material.dart';

import '../../services/anilist.dart';
import '../../services/library_store.dart';
import '../../services/manga_downloads.dart';
import '../../services/manga_prefs.dart';
import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/manga_image.dart';
import '../../widgets/shelf_backdrop.dart';
import '../../widgets/spine.dart';
import '../settings_screen.dart';
import 'manga_reader_sheet.dart';

/// Impostazioni della sezione Manga.
class MangaSettingsScreen extends StatefulWidget {
  const MangaSettingsScreen({super.key});
  @override
  State<MangaSettingsScreen> createState() => _MangaSettingsScreenState();
}

class _MangaSettingsScreenState extends State<MangaSettingsScreen> {
  @override
  void initState() {
    super.initState();
    MangaDownloads.I.loadPrefs().then((_) => mounted ? setState(() {}) : null);
    AniList.I.load().then((_) => mounted ? setState(() {}) : null);
  }

  @override
  Widget build(BuildContext context) {
    final app = LibraryStore.I.app;
    final al = AniList.I;
    return Scaffold(
      body: TabletSafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
          const Align(alignment: Alignment.centerLeft, child: BackLink(trail: 'Manga')),
          Text('Impostazioni manga', style: LK.display(28)),
          const SizedBox(height: 20),
          const SectionLabel('Lettore'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: BorderSide(color: LK.border), backgroundColor: LK.card, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(14)),
            onPressed: () async {
              final p = await MangaPrefs.load();
              if (!context.mounted) return;
              showMangaReaderSheet(context, prefs: p, seriesMode: 0, seriesRotation: 0, effectiveMode: p.defaultMode, onSeries: ({mode, rotation}) {}, onChanged: () {}, showSeries: false);
            },
            icon: Icon(Icons.tune, color: LK.accent),
            label: Text('Modalità, zone di tocco, filtri…', style: LK.body(14)),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Download'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: LK.accent,
            value: MangaDownloads.I.autoDelete,
            onChanged: (v) async {
              await MangaDownloads.I.setAutoDelete(v);
              setState(() {});
            },
            title: Text('Elimina i capitoli scaricati dopo averli letti', style: LK.body(14.5)),
          ),
          TextButton.icon(
            onPressed: () async {
              await MangaImages.clear();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache delle immagini svuotata')));
            },
            icon: Icon(Icons.cleaning_services_outlined, color: LK.accent),
            label: Text('Svuota la cache delle immagini', style: LK.body(14)),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Nuovi capitoli'),
          Text('Controllo automatico ogni 12 ore, all\'apertura dell\'app, con una notifica se ne escono di nuovi.', style: LK.body(13.5, color: LK.muted)),
          TextButton.icon(
            onPressed: () async {
              final n = await MangaStore.I.refreshLibrary();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'Nessun capitolo nuovo' : '$n capitoli nuovi')));
            },
            icon: Icon(Icons.sync, color: LK.accent),
            label: Text('Controlla adesso', style: LK.body(14)),
          ),
          const SizedBox(height: 22),
          const SectionLabel('AniList'),
          Text(al.loggedIn ? 'Collegato come ${al.userName ?? ''}.' : 'Non collegato: accedi da Esplora → AniList.', style: LK.body(14)),
          if (al.loggedIn)
            TextButton.icon(
              onPressed: () async {
                await al.logout();
                setState(() {});
              },
              icon: Icon(Icons.logout, color: LK.muted),
              label: Text('Esci da AniList', style: LK.body(14, color: LK.muted)),
            ),
          const SizedBox(height: 22),
          const SectionLabel('Sfondo predefinito degli scaffali'),
          SizedBox(
            height: 112,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final k in shelfBackdrops)
                GestureDetector(
                  onTap: () {
                    app.mangaShelfBg = k;
                    LibraryStore.I.saveAppPrefs();
                    setState(() {});
                  },
                  child: Container(
                    width: 72,
                    margin: const EdgeInsets.only(right: 8),
                    child: Column(children: [
                      Container(
                        height: 82,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: LK.paper,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: app.mangaShelfBg == k ? LK.accent : LK.border, width: app.mangaShelfBg == k ? 2.5 : 1),
                        ),
                        child: Stack(children: [ShelfBackdrop(k), const Positioned(left: 6, right: 6, bottom: 12, child: ShelfBoard())]),
                      ),
                      const SizedBox(height: 4),
                      Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(11)),
                    ]),
                  ),
                ),
            ]),
          ),
          Text('Ogni scaffale si può personalizzare a parte con il pennello accanto al nome.', style: LK.body(12.5, color: LK.muted, style: FontStyle.italic)),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: BorderSide(color: LK.border), backgroundColor: LK.card, padding: const EdgeInsets.all(14)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: LKIcon(LKGlyph.settings, color: LK.accent),
            label: Text('Impostazioni generali dell\'app', style: LK.body(14)),
          ),
        ]),
      ),
    );
  }
}
