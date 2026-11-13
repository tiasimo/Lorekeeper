import 'dart:async';
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';

import '../../services/anilist.dart';
import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../tv/tv_keyboard.dart';
import '../../tv/tv_mode.dart';
import '../../widgets/common.dart';
import 'manga_detail.dart';

const alBlue = Color(0xFF02A9FF);

// ======================================================================
// Scheda AniList dentro la pagina del manga
// ======================================================================
class AniListCard extends StatefulWidget {
  final SavedManga manga;
  const AniListCard({super.key, required this.manga});
  @override
  State<AniListCard> createState() => _AniListCardState();
}

class _AniListCardState extends State<AniListCard> {
  SavedManga get m => widget.manga;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AniList.I.load().then((_) => _pull());
  }

  /// Rilegge da AniList stato, progressi e voto.
  Future<void> _pull() async {
    final id = m.anilistId;
    if (id == null || !AniList.I.loggedIn) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final e = await AniList.I.entry(id);
      if (e != null) {
        m.alStatus = e.status;
        m.alProgress = e.progress;
        m.alScore = e.score;
        m.alTotal = e.media.chapters ?? m.alTotal;
        m.syncReadFromAniList();
        MangaStore.I.save();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AniList: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() async {
    final media = await pickAniListMedia(context, m.title);
    if (media == null) return;
    await _run(() => MangaStore.I.linkAniList(m, media));
  }

  @override
  Widget build(BuildContext context) {
    final al = AniList.I;
    if (!al.loggedIn) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.border)),
      child: m.anilistId == null
          ? Row(children: [
              _logo(),
              const SizedBox(width: 10),
              Expanded(child: Text('Non collegato ad AniList', style: LK.body(14, color: LK.muted))),
              TextButton(onPressed: _busy ? null : _link, child: Text('Collega', style: LK.body(14, color: LK.accent))),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _logo(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cap. ${m.alProgress}${m.alTotal != null ? ' / ${m.alTotal}' : ''}',
                    style: LK.display(15),
                  ),
                ),
                if (_busy) Padding(padding: const EdgeInsets.all(8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: LK.accent))),
                PopupMenuButton<String>(
                  color: LK.card,
                  icon: Icon(Icons.more_vert, color: LK.muted),
                  onSelected: (v) {
                    if (v == 'link') _link();
                    if (v == 'unlink') setState(() => MangaStore.I.unlinkAniList(m));
                    if (v == 'progress') {
                      final read = m.chapters.where((c) => m.read.contains(c.url)).map(m.chapterNumber).fold<int>(0, (a, b) => b > a ? b : a);
                      _run(() => MangaStore.I.setAniList(m, progress: read));
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'progress', child: Text('Allinea ai capitoli letti in app', style: LK.body(14))),
                    PopupMenuItem(value: 'link', child: Text('Cambia collegamento', style: LK.body(14))),
                    PopupMenuItem(value: 'unlink', child: Text('Scollega', style: LK.body(14))),
                  ],
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: m.alStatus,
                      hint: Text('Non in lista', style: LK.body(14, color: LK.muted)),
                      dropdownColor: LK.card,
                      items: [for (final e in alStatuses.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: LK.body(14)))],
                      onChanged: _busy ? null : (v) => _run(() => MangaStore.I.setAniList(m, status: v)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // voto da 0 a 10, a mezze stelle
                for (var i = 1; i <= 5; i++)
                  GestureDetector(
                    onTap: _busy
                        ? null
                        : () {
                            final full = i * 2.0, half = i * 2.0 - 1;
                            final next = m.alScore == full ? half : (m.alScore == half ? 0.0 : full);
                            _run(() => MangaStore.I.setAniList(m, score: next));
                          },
                    child: Icon(
                      m.alScore >= i * 2 ? Icons.star_rounded : (m.alScore >= i * 2 - 1 ? Icons.star_half_rounded : Icons.star_outline_rounded),
                      color: LK.gold,
                      size: 26,
                    ),
                  ),
              ]),
              if (MangaStore.I.syncError != null)
                Text('Ultimo invio non riuscito: ${MangaStore.I.syncError}', style: LK.body(11.5, color: LK.accent)),
            ]),
    );
  }

  Widget _logo() => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: const Color(0xFF152232), borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: Text('AL', style: LK.label(10, color: alBlue, spacing: 0)),
      );
}

/// Cerca un manga su AniList e restituisce quello scelto.
Future<AlMedia?> pickAniListMedia(BuildContext context, String title) {
  return showModalBottomSheet<AlMedia>(
    context: context,
    backgroundColor: LK.paper,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _AlSearch(initial: title),
  );
}

class _AlSearch extends StatefulWidget {
  final String initial;
  const _AlSearch({required this.initial});
  @override
  State<_AlSearch> createState() => _AlSearchState();
}

class _AlSearchState extends State<_AlSearch> {
  late final _q = TextEditingController(text: widget.initial);
  List<AlMedia> _res = [];
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      _res = await AniList.I.search(_q.text.trim());
    } catch (e) {
      _err = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TvTextField(
              controller: _q,
              hint: 'Cerca su AniList…',
              onSubmitted: (_) => _go(),
              decoration: InputDecoration(
                hintText: 'Cerca su AniList…',
                prefixIcon: Icon(Icons.search, color: LK.muted),
                filled: true,
                fillColor: LK.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
              ),
            ),
          ),
          if (_busy) LinearProgressIndicator(color: LK.accent, backgroundColor: LK.line),
          if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(_err!, style: LK.body(13, color: LK.accent))),
          Expanded(
            child: ListView.builder(
              itemCount: _res.length,
              itemBuilder: (ctx, i) {
                final r = _res[i];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(width: 40, height: 58, child: r.cover == null ? Container(color: LK.line) : Image.network(r.cover!, cacheWidth: 120, fit: BoxFit.cover)),
                  ),
                  title: Text(r.title, style: LK.display(14.5)),
                  subtitle: Text(
                    [if (r.english != null && r.english != r.title) r.english!, if (r.year != null) '${r.year}', if (r.format != null) r.format!.toLowerCase(), if (r.chapters != null) '${r.chapters} cap.'].join(' · '),
                    style: LK.body(12.5, color: LK.muted),
                  ),
                  onTap: () => Navigator.pop(ctx, r),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ======================================================================
// Scheda "AniList" della sezione Manga: accesso e lista importata
// ======================================================================
class AniListTab extends StatefulWidget {
  const AniListTab({super.key});
  @override
  State<AniListTab> createState() => _AniListTabState();
}

class _AniListTabState extends State<AniListTab> {
  final _client = TextEditingController();
  bool _busy = false;
  List<AlEntry>? _list;
  String? _err;
  String _status = 'CURRENT';

  @override
  void initState() {
    super.initState();
    AniList.I.load().then((_) async {
      _client.text = await AniList.I.clientId() ?? '';
      if (AniList.I.loggedIn) _refresh();
      if (mounted) setState(() {});
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      _list = await AniList.I.myList();
      final added = MangaStore.I.importAniList(_list!);
      if (added > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$added ${added == 1 ? 'manga aggiunto' : 'manga aggiunti'} alla libreria')));
      }
    } catch (e) {
      _err = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _login() async {
    await AniList.I.setClientId(_client.text);
    setState(() => _busy = true);
    try {
      await AniList.I.login();
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Accesso non riuscito: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Apre un manga della lista: cerca nelle sorgenti installate e lo collega da solo.
  Future<void> _open(AlEntry e) async {
    final have = MangaStore.I.library.where((m) => m.anilistId == e.media.id).firstOrNull;
    if (have != null) {
      Navigator.of(context).push(bookRoute(MangaDetail(manga: have)));
      return;
    }
    final picked = await showModalBottomSheet<(Source, DMedia)>(
      context: context,
      backgroundColor: LK.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SourceSearchSheet(titles: e.media.titles),
    );
    if (picked == null || !mounted) return;
    final m = MangaStore.I.entry(picked.$1, picked.$2);
    m.anilistId = e.media.id;
    m.alStatus = e.status;
    m.alProgress = e.progress;
    m.alScore = e.score;
    m.alTotal = e.media.chapters;
    if (!m.inLibrary) MangaStore.I.toggleLibrary(m);
    MangaStore.I.save();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MangaDetail(manga: m)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AniList.I,
      builder: (context, _) {
        final al = AniList.I;
        if (!al.loggedIn) return _setup();
        final counts = <String, int>{};
        for (final e in _list ?? const <AlEntry>[]) {
          counts[e.status] = (counts[e.status] ?? 0) + 1;
        }
        final shown = (_list ?? const <AlEntry>[]).where((e) => e.status == _status).toList()..sort((a, b) => a.media.title.compareTo(b.media.title));
        return RefreshIndicator(
          color: LK.accent,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Row(children: [
                CircleAvatar(radius: 18, backgroundColor: LK.line, backgroundImage: al.avatar == null ? null : NetworkImage(al.avatar!)),
                const SizedBox(width: 10),
                Expanded(child: Text(al.userName ?? 'AniList', style: LK.display(17))),
                TextButton(onPressed: () => al.logout(), child: Text('Esci', style: LK.body(13, color: LK.muted))),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final s in alStatuses.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${s.value}${counts[s.key] != null ? ' ${counts[s.key]}' : ''}', style: LK.body(12.5)),
                        selected: _status == s.key,
                        selectedColor: LK.accentSoft,
                        backgroundColor: LK.card,
                        side: BorderSide(color: LK.border),
                        onSelected: (_) => setState(() => _status = s.key),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              if (_busy && _list == null) Padding(padding: const EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: LK.accent))),
              if (_err != null) Text(_err!, style: LK.body(13, color: LK.accent)),
              if (_list != null && shown.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('Niente in questa lista.', textAlign: TextAlign.center, style: LK.body(14, color: LK.muted))),
              for (final e in shown)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.line)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(width: 42, height: 60, child: e.media.cover == null ? Container(color: LK.line) : Image.network(e.media.cover!, cacheWidth: 120, fit: BoxFit.cover)),
                    ),
                    title: Text(e.media.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.display(14.5)),
                    subtitle: Text(
                      'Cap. ${e.progress}${e.media.chapters != null ? ' / ${e.media.chapters}' : ''}${e.score > 0 ? ' · ★ ${e.score.toStringAsFixed(e.score % 1 == 0 ? 0 : 1)}' : ''}',
                      style: LK.label(9.5, spacing: 0.4),
                    ),
                    trailing: Icon(Icons.chevron_right, color: LK.border),
                    onTap: () => _open(e),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _setup() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Text('Collega AniList', style: LK.display(20)),
        const SizedBox(height: 6),
        Text('Serve una volta sola: crea il collegamento per Lorekeeper sul sito di AniList e incolla qui il suo ID.', style: LK.body(14, color: LK.muted)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: LK.parchment, borderRadius: BorderRadius.circular(10), border: Border.all(color: LK.parchmentBorder)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, t) in const [
              (1, 'Apri anilist.co → Settings → Developer → «Create New Client».'),
              (2, 'Name: Lorekeeper. Redirect URL: lorekeeper://anilist'),
              (3, 'Salva e copia il numero «ID» che compare.'),
              (4, 'Incollalo qui sotto e premi «Accedi».'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 20, child: Text('$i.', style: LK.body(14, color: LK.accent))),
                  Expanded(child: SelectableText(t, style: LK.body(14, color: LK.parchmentInk))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _client,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'ID client di AniList',
            filled: true,
            fillColor: LK.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LK.accent),
            onPressed: _busy ? null : _login,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('ACCEDI CON ANILIST'),
          ),
        ),
      ],
    );
  }
}

/// Cerca un titolo in tutte le sorgenti installate e fa scegliere il risultato.
class SourceSearchSheet extends StatefulWidget {
  final List<String> titles;
  final String title;
  final String? excludeSourceId;
  final bool anime; // cerca nelle sorgenti anime
  const SourceSearchSheet({super.key, required this.titles, this.title = 'Dove vuoi leggerlo?', this.excludeSourceId, this.anime = false});
  @override
  State<SourceSearchSheet> createState() => SourceSearchSheetState();
}

class SourceSearchSheetState extends State<SourceSearchSheet> {
  late final _q = TextEditingController(text: widget.titles.first);
  final List<(Source, DMedia)> _res = [];
  final Map<String, String> _errors = {};
  int _pending = 0, _run = 0;

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    final my = ++_run;
    final sources = (widget.anime ? MangaStore.I.ext.installedAnimeExtensions : MangaStore.I.ext.installedMangaExtensions).where((s) => s.id != widget.excludeSourceId).toList();
    setState(() {
      _res.clear();
      _errors.clear();
      _pending = sources.length;
    });
    searchSources(
      sources,
      _q.text.trim(),
      alive: () => my == _run && mounted,
      onResult: (s, list) => setState(() => _res.addAll(list.take(tvMode ? 4 : 6).map((d) => (s, d)))),
      onError: (s, e) => setState(() => _errors[s.name ?? ''] = e is TimeoutException ? 'non risponde' : '$e'),
      onDone: () => setState(() => _pending--),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.anime ? MangaStore.I.ext.installedAnimeExtensions : MangaStore.I.ext.installedMangaExtensions;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(widget.title, style: LK.display(18)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TvTextField(
              controller: _q,
              hint: 'Cerca il titolo',
              onSubmitted: (_) => _go(),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, color: LK.muted),
                filled: true,
                fillColor: LK.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
              ),
            ),
          ),
          if (widget.titles.length > 1)
            SizedBox(
              height: 38,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                for (final t in widget.titles)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(t, style: LK.body(12)),
                      backgroundColor: LK.card,
                      side: BorderSide(color: LK.border),
                      onPressed: () {
                        _q.text = t;
                        _go();
                      },
                    ),
                  ),
              ]),
            ),
          if (_pending > 0) LinearProgressIndicator(color: LK.accent, backgroundColor: LK.line),
          if (sources.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('Installa prima una sorgente in «Estensioni».', style: LK.body(14, color: LK.muted))),
          Expanded(
            child: ListView.builder(
              itemCount: _res.length,
              itemBuilder: (ctx, i) {
                final (s, d) = _res[i];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(width: 40, height: 58, child: (d.cover ?? '').isEmpty ? Container(color: LK.line) : Image.network(d.cover!, cacheWidth: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: LK.line))),
                  ),
                  title: Text(d.title ?? '', style: LK.display(14)),
                  subtitle: Text('${s.name} · ${(s.lang ?? '').toUpperCase()}', style: LK.label(9.5, spacing: 0.4)),
                  onTap: () => Navigator.pop(ctx, (s, d)),
                );
              },
            ),
          ),
          if (_pending == 0 && _res.isEmpty && sources.isNotEmpty)
            Padding(padding: const EdgeInsets.all(20), child: Text('Nessuna sorgente l\'ha trovato. Prova un altro titolo.', style: LK.body(14, color: LK.muted))),
        ]),
      ),
    );
  }
}
