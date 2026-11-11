import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Modi di lettura (come in Mihon). 0 = predefinita (solo per la serie).
const mangaModes = [
  'Predefinita',
  'Per pagina (da sinistra a destra)',
  'Per pagina (da destra a sinistra)',
  'Per pagina (verticale)',
  'Verticale lungo',
  'Verticale lungo con interruzioni',
];
const mangaRotations = ['Predefinita', 'Libero', 'Verticale', 'Orizzontale', 'Bloccato verticale', 'Bloccato orizzontale', 'Verticale inverso'];
const mangaTapZones = ['Predefinita', 'A forma di L', 'Stile Kindle', 'Bordo', 'Destra e Sinistra', 'Disattivato'];
const mangaInvert = ['Nessuno', 'Orizzontale', 'Verticale', 'Entrambi'];
const mangaBackgrounds = ['Nero', 'Grigio', 'Bianco', 'Auto'];
const mangaBlends = ['Predefinito', 'Moltiplica', 'Schermo', 'Sovrapponi', 'Schiarisci', 'Scurisci'];

/// Impostazioni del lettore manga: una parte vale per tutti, modo e rotazione anche per serie.
class MangaPrefs {
  // generali
  int defaultMode = 2; // destra → sinistra
  int defaultRotation = 1; // libero
  // per pagina
  int pagedTapZones = 0;
  int pagedInvert = 0;
  bool cropBorders = false;
  bool splitWide = false;
  bool rotateWide = false;
  bool doubleTapZoom = true;
  bool disableZoomOut = false;
  // verticale lungo
  int webtoonTapZones = 0;
  int webtoonInvert = 0;
  int sidePadding = 0; // percentuale 0–25
  bool webtoonCrop = false;
  bool webtoonDoubleTap = true;
  // aspetto e comportamento
  int background = 0;
  bool showPageNumber = true;
  Set<int> verticalNavigatorIn = {};
  bool fullscreen = true;
  bool drawInCutout = true;
  bool keepScreenOn = true;
  bool longPressActions = true;
  bool alwaysTransition = true;
  bool animatePages = true;
  bool flashOnPage = false;
  bool doublePage = true; // due pagine affiancate in orizzontale
  // filtri
  bool customBrightness = false;
  int brightness = 0; // -75 … 0
  bool colorFilter = false;
  int filterR = 0, filterG = 0, filterB = 0, filterA = 60;
  int blend = 0;
  bool grayscale = false;
  bool invert = false;

  Map<String, dynamic> toJson() => {
        'dm': defaultMode,
        'dr': defaultRotation,
        'ptz': pagedTapZones,
        'pinv': pagedInvert,
        'crop': cropBorders,
        'split': splitWide,
        'rot': rotateWide,
        'dtz': doubleTapZoom,
        'nzo': disableZoomOut,
        'wtz': webtoonTapZones,
        'winv': webtoonInvert,
        'side': sidePadding,
        'wcrop': webtoonCrop,
        'wdt': webtoonDoubleTap,
        'bg': background,
        'num': showPageNumber,
        'vnav': verticalNavigatorIn.toList(),
        'full': fullscreen,
        'cut': drawInCutout,
        'awake': keepScreenOn,
        'long': longPressActions,
        'trans': alwaysTransition,
        'anim': animatePages,
        'flash': flashOnPage,
        'dp': doublePage,
        'cb': customBrightness,
        'b': brightness,
        'cf': colorFilter,
        'fr': filterR,
        'fg': filterG,
        'fb': filterB,
        'fa': filterA,
        'blend': blend,
        'gray': grayscale,
        'inv': invert,
      };

  static MangaPrefs fromJson(Map j) {
    final p = MangaPrefs();
    T v<T>(String k, T d) => j[k] is T ? j[k] as T : d;
    p.defaultMode = v('dm', p.defaultMode);
    p.defaultRotation = v('dr', p.defaultRotation);
    p.pagedTapZones = v('ptz', 0);
    p.pagedInvert = v('pinv', 0);
    p.cropBorders = v('crop', false);
    p.splitWide = v('split', false);
    p.rotateWide = v('rot', false);
    p.doubleTapZoom = v('dtz', true);
    p.disableZoomOut = v('nzo', false);
    p.webtoonTapZones = v('wtz', 0);
    p.webtoonInvert = v('winv', 0);
    p.sidePadding = v('side', 0);
    p.webtoonCrop = v('wcrop', false);
    p.webtoonDoubleTap = v('wdt', true);
    p.background = v('bg', 0);
    p.showPageNumber = v('num', true);
    p.verticalNavigatorIn = ((j['vnav'] as List?) ?? const []).whereType<int>().toSet();
    p.fullscreen = v('full', true);
    p.drawInCutout = v('cut', true);
    p.keepScreenOn = v('awake', true);
    p.longPressActions = v('long', true);
    p.alwaysTransition = v('trans', true);
    p.animatePages = v('anim', true);
    p.flashOnPage = v('flash', false);
    p.doublePage = v('dp', true);
    p.customBrightness = v('cb', false);
    p.brightness = v('b', 0);
    p.colorFilter = v('cf', false);
    p.filterR = v('fr', 0);
    p.filterG = v('fg', 0);
    p.filterB = v('fb', 0);
    p.filterA = v('fa', 60);
    p.blend = v('blend', 0);
    p.grayscale = v('gray', false);
    p.invert = v('inv', false);
    return p;
  }

  static MangaPrefs? _cache;

  static Future<MangaPrefs> load() async {
    if (_cache != null) return _cache!;
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString('manga.reader');
    MangaPrefs p;
    try {
      p = s == null ? MangaPrefs() : fromJson(jsonDecode(s) as Map);
    } catch (_) {
      p = MangaPrefs();
    }
    return _cache = p;
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('manga.reader', jsonEncode(toJson()));
  }

  // --- impostazioni per serie (modo e rotazione)
  static Future<(int, int)> series(String key) async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getInt('manga.s.mode.$key') ?? 0, sp.getInt('manga.s.rot.$key') ?? 0);
  }

  static Future<void> setSeries(String key, {int? mode, int? rotation}) async {
    final sp = await SharedPreferences.getInstance();
    if (mode != null) await sp.setInt('manga.s.mode.$key', mode);
    if (rotation != null) await sp.setInt('manga.s.rot.$key', rotation);
  }
}
