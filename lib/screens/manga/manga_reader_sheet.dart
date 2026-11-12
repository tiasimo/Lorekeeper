import 'package:flutter/material.dart';

import '../../services/manga_prefs.dart';
import '../../theme.dart';

/// Colori del pannello (scuro, come il lettore).
const _bg = Color(0xFF1F1B18);
const _ink = Color(0xFFEFE4D2);
const _muted = Color(0xFFA99C8E);
const _chipOn = Color(0xFF5A2A22);
const _gold = Color(0xFFE2B84B);

/// Pannello delle impostazioni del lettore, con tre schede come in Mihon.
Future<void> showMangaReaderSheet(
  BuildContext context, {
  required MangaPrefs prefs,
  required int seriesMode,
  required int seriesRotation,
  required int effectiveMode,
  required void Function({int? mode, int? rotation}) onSeries,
  required VoidCallback onChanged,
  bool showSeries = true,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: _bg,
    barrierColor: Colors.black26,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.62,
      child: _Sheet(prefs: prefs, seriesMode: seriesMode, seriesRotation: seriesRotation, effectiveMode: effectiveMode, onSeries: onSeries, onChanged: onChanged, showSeries: showSeries),
    ),
  );
}

class _Sheet extends StatefulWidget {
  final MangaPrefs prefs;
  final int seriesMode, seriesRotation, effectiveMode;
  final void Function({int? mode, int? rotation}) onSeries;
  final VoidCallback onChanged;
  final bool showSeries;
  const _Sheet({required this.prefs, required this.seriesMode, required this.seriesRotation, required this.effectiveMode, required this.onSeries, required this.onChanged, this.showSeries = true});
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  MangaPrefs get p => widget.prefs;
  late int _mode = widget.seriesMode, _rot = widget.seriesRotation;

  void _set(VoidCallback f) {
    setState(f);
    p.save();
    widget.onChanged();
  }

  Widget _title(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, 16, 0, 8), child: Text(t, style: LK.body(14, color: _ink).copyWith(fontWeight: FontWeight.w600)));

  Widget _chips(List<String> labels, int selected, ValueChanged<int> on) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < labels.length; i++)
          GestureDetector(
            onTap: () => on(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: i == selected ? _chipOn : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: i == selected ? _chipOn : const Color(0xFF4A423B)),
              ),
              child: Text(labels[i], style: LK.body(13, color: i == selected ? _ink : _muted)),
            ),
          ),
      ]);

  Widget _multi(List<String> labels, Set<int> selected, ValueChanged<int> on) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 1; i < labels.length; i++)
          GestureDetector(
            onTap: () => on(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected.contains(i) ? _chipOn : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected.contains(i) ? _chipOn : const Color(0xFF4A423B)),
              ),
              child: Text(labels[i], style: LK.body(13, color: selected.contains(i) ? _ink : _muted)),
            ),
          ),
      ]);

  Widget _check(String label, bool value, ValueChanged<bool> on) => InkWell(
        onTap: () => on(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: Checkbox(
                value: value,
                onChanged: (v) => on(v ?? false),
                activeColor: _gold,
                checkColor: _bg,
                side: const BorderSide(color: _muted, width: 1.5),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: LK.body(14, color: _ink))),
          ]),
        ),
      );

  Widget _slider(String label, int value, int min, int max, ValueChanged<int> on, {String suffix = ''}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Expanded(child: Text(label, style: LK.body(14, color: _ink))),
            Text('$value$suffix', style: LK.body(13, color: _muted)),
          ]),
        ),
        Slider(
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          activeColor: _gold,
          inactiveColor: const Color(0xFF4A423B),
          onChanged: (v) => on(v.round()),
        ),
      ]);

  // ---------------- Modalità di lettura ----------------
  Widget _readingTab() {
    final webtoon = widget.effectiveMode >= 4;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
      if (widget.showSeries) ...[
        Padding(padding: const EdgeInsets.only(top: 14), child: Text('PER QUESTA SERIE', style: LK.label(10, color: _gold, spacing: 1.4))),
        _title('Modalità di lettura'),
        _chips(mangaModes, _mode, (i) {
          setState(() => _mode = i);
          widget.onSeries(mode: i);
        }),
        _title('Rotazione'),
        _chips(mangaRotations, _rot, (i) {
          setState(() => _rot = i);
          widget.onSeries(rotation: i);
        }),
      ],
      if (!webtoon) ...[
        Padding(padding: const EdgeInsets.only(top: 22), child: Text('PER PAGINA', style: LK.label(10, color: _gold, spacing: 1.4))),
        _title('Zone di tocco'),
        _chips(mangaTapZones, p.pagedTapZones, (i) => _set(() => p.pagedTapZones = i)),
        _title('Inverti le zone di tocco'),
        _chips(mangaInvert, p.pagedInvert, (i) => _set(() => p.pagedInvert = i)),
        const SizedBox(height: 8),
        _check('Ritaglia bordi', p.cropBorders, (v) => _set(() => p.cropBorders = v)),
        _check('Dividi le pagine larghe', p.splitWide, (v) => _set(() => p.splitWide = v)),
        _check('Ruota le pagine larghe per adattarle allo schermo', p.rotateWide, (v) => _set(() => p.rotateWide = v)),
        _check('Doppio tocco per ingrandire', p.doubleTapZoom, (v) => _set(() => p.doubleTapZoom = v)),
      ] else ...[
        Padding(padding: const EdgeInsets.only(top: 22), child: Text('VERTICALE LUNGO', style: LK.label(10, color: _gold, spacing: 1.4))),
        _title('Zone di tocco'),
        _chips(mangaTapZones, p.webtoonTapZones, (i) => _set(() => p.webtoonTapZones = i)),
        _title('Inverti le zone di tocco'),
        _chips(mangaInvert, p.webtoonInvert, (i) => _set(() => p.webtoonInvert = i)),
        _slider('Riempimento laterale', p.sidePadding, 0, 25, (v) => _set(() => p.sidePadding = v), suffix: '%'),
        _check('Ritaglia bordi', p.webtoonCrop, (v) => _set(() => p.webtoonCrop = v)),
        _check('Doppio tocco per ingrandire', p.webtoonDoubleTap, (v) => _set(() => p.webtoonDoubleTap = v)),
        _check('Disattiva zoom indietro', p.disableZoomOut, (v) => _set(() => p.disableZoomOut = v)),
      ],
      Padding(padding: const EdgeInsets.only(top: 22), child: Text('PREDEFINITI PER TUTTI I MANGA', style: LK.label(10, color: _gold, spacing: 1.4))),
      _title('Modalità di lettura predefinita'),
      _chips(mangaModes.sublist(1), p.defaultMode - 1, (i) => _set(() => p.defaultMode = i + 1)),
      _title('Rotazione predefinita'),
      _chips(mangaRotations.sublist(1), p.defaultRotation - 1, (i) => _set(() => p.defaultRotation = i + 1)),
    ]);
  }

  // ---------------- Generale ----------------
  Widget _generalTab() => ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
        _title('Colore sfondo'),
        _chips(mangaBackgrounds, p.background, (i) => _set(() => p.background = i)),
        const SizedBox(height: 8),
        _check('Mostra numero pagina', p.showPageNumber, (v) => _set(() => p.showPageNumber = v)),
        _title('Navigatore dei capitoli verticale in'),
        _multi(mangaModes, p.verticalNavigatorIn, (i) => _set(() => p.verticalNavigatorIn.contains(i) ? p.verticalNavigatorIn.remove(i) : p.verticalNavigatorIn.add(i))),
        const SizedBox(height: 8),
        _check('Schermo intero', p.fullscreen, (v) => _set(() => p.fullscreen = v)),
        _check('Mostra il contenuto nell\'area della fotocamera', p.drawInCutout, (v) => _set(() => p.drawInCutout = v)),
        _check('Mantieni lo schermo acceso', p.keepScreenOn, (v) => _set(() => p.keepScreenOn = v)),
        _check('Mostra azioni con un tocco prolungato', p.longPressActions, (v) => _set(() => p.longPressActions = v)),
        _check('Lettura continua: il capitolo successivo si carica in anticipo e parte da solo', p.continuous, (v) => _set(() => p.continuous = v)),
        _check('Mostra sempre la transizione tra capitoli', p.alwaysTransition, (v) => _set(() => p.alwaysTransition = v)),
        _check('Anima le transizioni di pagina', p.animatePages, (v) => _set(() => p.animatePages = v)),
        _check('Lampeggia al cambio pagina', p.flashOnPage, (v) => _set(() => p.flashOnPage = v)),
        _check('Due pagine affiancate in orizzontale', p.doublePage, (v) => _set(() => p.doublePage = v)),
      ]);

  // ---------------- Filtro personalizzato ----------------
  Widget _filterTab() => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
        _check('Luminosità personalizzata', p.customBrightness, (v) => _set(() => p.customBrightness = v)),
        if (p.customBrightness) _slider('Luminosità', p.brightness, -75, 0, (v) => _set(() => p.brightness = v)),
        _check('Filtro colore personalizzato', p.colorFilter, (v) => _set(() => p.colorFilter = v)),
        if (p.colorFilter) ...[
          _slider('Rosso', p.filterR, 0, 255, (v) => _set(() => p.filterR = v)),
          _slider('Verde', p.filterG, 0, 255, (v) => _set(() => p.filterG = v)),
          _slider('Blu', p.filterB, 0, 255, (v) => _set(() => p.filterB = v)),
          _slider('Opacità', p.filterA, 0, 255, (v) => _set(() => p.filterA = v)),
          _title('Modalità di fusione'),
          _chips(mangaBlends, p.blend, (i) => _set(() => p.blend = i)),
          const SizedBox(height: 8),
        ],
        _check('Scala di grigi', p.grayscale, (v) => _set(() => p.grayscale = v)),
        _check('Inversa', p.invert, (v) => _set(() => p.invert = v)),
      ]);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(
          labelColor: _gold,
          unselectedLabelColor: _muted,
          indicatorColor: _gold,
          dividerColor: const Color(0xFF3A332D),
          labelStyle: LK.body(13.5),
          tabs: const [Tab(text: 'Modalità di lettura'), Tab(text: 'Generale'), Tab(text: 'Filtro personalizzato')],
          isScrollable: true,
          tabAlignment: TabAlignment.start,
        ),
        Expanded(child: TabBarView(children: [_readingTab(), _generalTab(), _filterTab()])),
      ]),
    );
  }
}
