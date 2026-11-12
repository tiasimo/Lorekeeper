import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Un download in coda.
class _Job {
  final String url;
  final Map<String, String>? headers;
  final String? sourceId, managerId;
  final completer = Completer<Uint8List?>();
  bool started = false, prefetch = false;
  _Job(this.url, this.headers, this.sourceId, this.managerId);
}

/// Scarica le immagini di copertine e pagine (con gli header della sorgente).
/// - cache su disco permanente (con un limite: le immagini più vecchie si cancellano,
///   le copertine della libreria mai);
/// - al massimo 6 download insieme, con la precedenza a quelli chiesti per ultimi
///   (cioè quelli che stai guardando) e annullando quelli non più visibili;
/// - per le estensioni Mihon prova prima il download diretto e usa il motore
///   dell'estensione solo se serve, ricordandosi la scelta per ogni sorgente.
class MangaImages {
  static final _mem = LinkedHashMap<String, Uint8List>();
  static final _jobs = <String, _Job>{};
  static final _queue = <_Job>[];
  static int _running = 0;
  static const _maxRunning = 6;
  static const _maxCacheBytes = 300 * 1024 * 1024;
  static Directory? _dir;
  static final _client = http.Client();
  static final _needsBridge = <String>{};
  static bool _prefsLoaded = false, _trimmed = false;

  /// Url delle copertine dei manga in libreria: non vengono mai cancellate.
  static final Map<String, Set<String> Function()> protectedSources = {};
  static Set<String> protectedUrls() => {for (final f in protectedSources.values) ...f()};

  static Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final t = await getApplicationSupportDirectory();
    final d = Directory(p.join(t.path, 'manga_cache'));
    await d.create(recursive: true);
    _dir = d;
    if (!_trimmed) {
      _trimmed = true;
      Future.delayed(const Duration(seconds: 20), _trim);
    }
    return d;
  }

  static String _name(String url) {
    // FNV-1a a 64 bit: stabile tra un avvio e l'altro
    var h = 0xcbf29ce484222325;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return '${h.toUnsigned(64).toRadixString(16)}_${url.length}';
  }

  static Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    _needsBridge.addAll(prefs.getStringList('manga.imgBridge') ?? const []);
  }

  static Future<void> _rememberBridge(String sourceId) async {
    if (!_needsBridge.add(sourceId)) return;
    (await SharedPreferences.getInstance()).setStringList('manga.imgBridge', _needsBridge.toList());
  }

  /// Immagine già in memoria (senza attese).
  static Uint8List? peek(String url) => _mem[url];

  /// [prefetch]: in fondo alla coda, dopo tutto il resto.
  static Future<Uint8List?> get(String url, {Map<String, String>? headers, String? sourceId, String? managerId, bool prefetch = false}) {
    final hit = _mem[url];
    if (hit != null) return Future.value(hit);
    final j = _jobs[url];
    if (j != null) {
      if (!prefetch) j.prefetch = false;
      if (!j.started && !prefetch) {
        _queue.remove(j);
        _queue.add(j);
      }
      return j.completer.future;
    }
    final job = _Job(url, headers, sourceId, managerId)..prefetch = prefetch;
    _jobs[url] = job;
    prefetch ? _queue.insert(0, job) : _queue.add(job);
    _pump();
    return job.completer.future;
  }

  static final _viewers = <String, int>{};

  /// Un widget mostra questa immagine.
  static void watch(String url) => _viewers[url] = (_viewers[url] ?? 0) + 1;

  /// Il widget non la mostra più (es. è uscita dallo schermo): se il download
  /// non è ancora partito, lo annullo.
  static void unwatch(String url) {
    final n = (_viewers[url] ?? 1) - 1;
    if (n > 0) {
      _viewers[url] = n;
      return;
    }
    _viewers.remove(url);
    final j = _jobs[url];
    if (j == null || j.started || j.prefetch) return;
    _queue.remove(j);
    _jobs.remove(url);
    j.completer.completeError(const _Cancelled());
  }

  /// Precarica in silenzio (es. la pagina successiva dei risultati).
  static void prefetch(Iterable<String> urls, {String? sourceId, String? managerId}) {
    for (final u in urls) {
      if (u.isEmpty) continue;
      get(u, sourceId: sourceId, managerId: managerId, prefetch: true).then((_) {}, onError: (_) {});
    }
  }

  static void _pump() {
    while (_running < _maxRunning && _queue.isNotEmpty) {
      final j = _queue.removeLast(); // l'ultima richiesta è quella che stai guardando
      j.started = true;
      _running++;
      _load(j.url, j.headers, j.sourceId, j.managerId).then((b) => j.completer.complete(b), onError: (Object e) => j.completer.completeError(e)).whenComplete(() {
        _running--;
        _jobs.remove(j.url);
        _pump();
      });
    }
  }

  static Future<Uint8List?> _load(String url, Map<String, String>? headers, String? sourceId, String? managerId) async {
    if (url.startsWith('/')) {
      final local = await File(url).readAsBytes();
      _remember(url, local);
      return local;
    }
    await _loadPrefs();
    final f = File(p.join((await _cacheDir()).path, _name(url)));
    Uint8List? bytes;
    if (await f.exists()) {
      bytes = await f.readAsBytes();
      f.setLastModified(DateTime.now()).catchError((_) {});
    }
    final mihon = managerId == 'aniyomi' && sourceId != null;
    Future<Uint8List?> viaBridge() async {
      try {
        final Uint8List? b = await AnymeXRuntimeBridge.getImageBytes(sourceId!, false, url);
        return (b == null || b.isEmpty) ? null : b;
      } catch (_) {
        return null;
      }
    }

    if (bytes == null && mihon && _needsBridge.contains(sourceId)) bytes = await viaBridge();
    if (bytes == null) {
      try {
        final r = await _client.get(Uri.parse(url), headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
          ...?headers,
        }).timeout(const Duration(seconds: 20));
        final type = r.headers['content-type'] ?? 'image/';
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty && !type.startsWith('text/')) bytes = r.bodyBytes;
        if (bytes == null && !mihon) throw Exception('HTTP ${r.statusCode}');
      } catch (e) {
        if (!mihon) rethrow;
      }
      if (bytes == null && mihon && !_needsBridge.contains(sourceId)) {
        bytes = await viaBridge();
        if (bytes != null) _rememberBridge(sourceId);
      }
      if (bytes == null) throw Exception('immagine non disponibile');
      try {
        await f.writeAsBytes(bytes, flush: false);
      } catch (_) {}
    }
    _remember(url, bytes);
    return bytes;
  }

  static void _remember(String url, Uint8List b) {
    _mem[url] = b;
    while (_mem.length > 30) {
      _mem.remove(_mem.keys.first);
    }
  }

  /// Tiene la cache sotto il limite, cancellando prima le immagini usate meno di recente.
  static Future<void> _trim() async {
    try {
      final d = await _cacheDir();
      final keep = protectedUrls().map(_name).toSet();
      final files = <(File, int, DateTime)>[];
      var total = 0;
      await for (final e in d.list()) {
        if (e is! File) continue;
        final st = await e.stat();
        total += st.size;
        files.add((e, st.size, st.modified));
      }
      if (total <= _maxCacheBytes) return;
      files.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (f, size, _) in files) {
        if (total <= _maxCacheBytes * 0.8) break;
        if (keep.contains(p.basename(f.path))) continue;
        try {
          await f.delete();
          total -= size;
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Percorso su disco dell'immagine (la scarica se serve), per il widget della Home.
  static Future<String?> localPath(String url, {String? sourceId, String? managerId}) async {
    if (url.startsWith('/')) return url;
    try {
      await get(url, sourceId: sourceId, managerId: managerId);
      final f = File(p.join((await _cacheDir()).path, _name(url)));
      return await f.exists() ? f.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Svuota la cache su disco (le copertine della libreria restano).
  static Future<void> clear() async {
    _mem.clear();
    PaintingBinding.instance.imageCache.clear();
    final d = await _cacheDir();
    final keep = protectedUrls().map(_name).toSet();
    await for (final e in d.list()) {
      if (e is File && !keep.contains(p.basename(e.path))) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// ImageProvider: così le copertine già decodificate restano nella cache di Flutter
/// e ricompaiono subito quando torni su una pagina.
class MangaImageProvider extends ImageProvider<MangaImageProvider> {
  final String url;
  final Map<String, String>? headers;
  final String? sourceId, managerId;
  const MangaImageProvider(this.url, {this.headers, this.sourceId, this.managerId});

  @override
  Future<MangaImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(MangaImageProvider key, ImageDecoderCallback decode) => MultiFrameImageStreamCompleter(
        codec: () async {
          final bytes = await MangaImages.get(url, headers: headers, sourceId: sourceId, managerId: managerId);
          if (bytes == null) throw Exception('immagine vuota');
          return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        }(),
        scale: 1,
        debugLabel: url,
      );

  @override
  bool operator ==(Object other) => other is MangaImageProvider && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

class MangaImage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final String? sourceId, managerId;
  final BoxFit fit;
  final double? width, height;
  final Widget? placeholder;
  /// Colore di attesa (es. il colore della copertina già calcolato).
  final Color? tint;
  const MangaImage(this.url, {super.key, this.headers, this.sourceId, this.managerId, this.fit = BoxFit.cover, this.width, this.height, this.placeholder, this.tint});

  @override
  State<MangaImage> createState() => _MangaImageState();
}

class _MangaImageState extends State<MangaImage> {
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    if (widget.url.isNotEmpty) MangaImages.watch(widget.url);
  }

  @override
  void didUpdateWidget(MangaImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      if (old.url.isNotEmpty) MangaImages.unwatch(old.url);
      if (widget.url.isNotEmpty) MangaImages.watch(widget.url);
    }
  }

  @override
  void dispose() {
    if (widget.url.isNotEmpty) MangaImages.unwatch(widget.url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return _box(null);
    return LayoutBuilder(builder: (context, c) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final w = widget.width ?? (c.maxWidth.isFinite ? c.maxWidth : null);
      final target = w == null ? null : (w * dpr).round().clamp(64, 1400);
      ImageProvider img = MangaImageProvider(widget.url, headers: widget.headers, sourceId: widget.sourceId, managerId: widget.managerId);
      if (target != null) img = ResizeImage(img, width: target, policy: ResizeImagePolicy.fit, allowUpscaling: false);
      return Image(
        key: ValueKey('${widget.url}#$_retry'),
        image: img,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (sync) return child;
          return Stack(fit: StackFit.passthrough, children: [
            Positioned.fill(child: widget.placeholder ?? _box(null)),
            AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 260), curve: Curves.easeOut, child: child),
          ]);
        },
        errorBuilder: (_, e, __) {
          if (e is _Cancelled) {
            // annullato mentre un altro widget lo aspettava ancora: riprovo
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _retry++);
            });
            return _box(null);
          }
          return _broken();
        },
      );
    });
  }

  Widget _box(Widget? child) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          gradient: widget.tint == null
              ? null
              : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [widget.tint!, Color.lerp(widget.tint!, Colors.black, 0.25)!]),
          color: widget.tint == null ? LK.line : null,
        ),
        alignment: Alignment.center,
        child: child,
      );

  Widget _broken() => _box(GestureDetector(
        onTap: () {
          PaintingBinding.instance.imageCache.evict(MangaImageProvider(widget.url));
          setState(() => _retry++);
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.broken_image_outlined, color: LK.muted),
          const SizedBox(height: 4),
          Text('Tocca per riprovare', style: LK.label(9, spacing: 0.4)),
        ]),
      ));
}
