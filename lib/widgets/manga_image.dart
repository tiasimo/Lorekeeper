import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme.dart';

/// Scarica le immagini di copertine e pagine (con gli header della sorgente),
/// con una piccola cache in memoria e su disco.
class MangaImages {
  static final _mem = LinkedHashMap<String, Uint8List>();
  static final _pending = <String, Future<Uint8List?>>{};
  static Directory? _dir;
  static final _client = http.Client();

  static Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final t = await getTemporaryDirectory();
    final d = Directory(p.join(t.path, 'manga_cache'));
    await d.create(recursive: true);
    return _dir = d;
  }

  static String _name(String url) => '${url.hashCode.toUnsigned(32).toRadixString(16)}_${url.length}';

  static Future<Uint8List?> get(String url, {Map<String, String>? headers, String? sourceId, String? managerId}) {
    final hit = _mem[url];
    if (hit != null) return Future.value(hit);
    return _pending[url] ??= _load(url, headers, sourceId, managerId).whenComplete(() => _pending.remove(url));
  }

  static Future<Uint8List?> _load(String url, Map<String, String>? headers, String? sourceId, String? managerId) async {
    if (url.startsWith('/')) {
      final local = await File(url).readAsBytes();
      _mem[url] = local;
      return local;
    }
    final f = File(p.join((await _cacheDir()).path, _name(url)));
    Uint8List? bytes;
    if (await f.exists()) bytes = await f.readAsBytes();
    // Le estensioni Mihon possono avere regole proprie per le immagini
    if (bytes == null && managerId == 'aniyomi' && sourceId != null) {
      try {
        bytes = await AnymeXRuntimeBridge.getImageBytes(sourceId, false, url);
      } catch (_) {}
    }
    if (bytes == null) {
      final r = await _client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
        ...?headers,
      });
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw Exception('HTTP ${r.statusCode}');
      bytes = r.bodyBytes;
    }
    try {
      await f.writeAsBytes(bytes, flush: false);
    } catch (_) {}
    _mem[url] = bytes;
    while (_mem.length > 40) {
      _mem.remove(_mem.keys.first);
    }
    return bytes;
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

  /// Svuota la cache su disco.
  static Future<void> clear() async {
    _mem.clear();
    final d = await _cacheDir();
    if (await d.exists()) await d.delete(recursive: true);
    _dir = null;
  }
}

class MangaImage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final String? sourceId, managerId;
  final BoxFit fit;
  final double? width, height;
  final Widget? placeholder;
  const MangaImage(this.url, {super.key, this.headers, this.sourceId, this.managerId, this.fit = BoxFit.cover, this.width, this.height, this.placeholder});

  @override
  State<MangaImage> createState() => _MangaImageState();
}

class _MangaImageState extends State<MangaImage> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _go();
  }

  @override
  void didUpdateWidget(MangaImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _error = null;
      _go();
    }
  }

  void _go() {
    if (widget.url.isEmpty) {
      _error = 'vuoto';
      return;
    }
    MangaImages.get(widget.url, headers: widget.headers, sourceId: widget.sourceId, managerId: widget.managerId).then((b) {
      if (mounted) setState(() => _bytes = b);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: widget.fit, width: widget.width, height: widget.height, gaplessPlayback: true, errorBuilder: (_, __, ___) => _broken());
    }
    if (_error != null) return _broken();
    return widget.placeholder ??
        Container(
          width: widget.width,
          height: widget.height,
          color: LK.line,
          alignment: Alignment.center,
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: LK.accent)),
        );
  }

  Widget _broken() => Container(
        width: widget.width,
        height: widget.height,
        color: LK.line,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => setState(() {
            _error = null;
            _go();
          }),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.broken_image_outlined, color: LK.muted),
            const SizedBox(height: 4),
            Text('Tocca per riprovare', style: LK.label(9, spacing: 0.4)),
          ]),
        ),
      );
}
