import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'manga_image.dart';

/// Dimensioni dell'immagine e bordi vuoti da ritagliare (in frazioni 0–1).
class PageInfo {
  final Uint8List bytes;
  final Size size;
  final Rect crop; // area utile
  PageInfo(this.bytes, this.size, this.crop);
  bool get wide => size.width > size.height * 1.05;
}

class PageInfos {
  static final _cache = <String, PageInfo>{};
  static final _pending = <String, Future<PageInfo>>{};

  static PageInfo? peek(String url) => _cache[url];

  static Future<PageInfo> get(String url, Uint8List bytes) {
    final c = _cache[url];
    if (c != null) return Future.value(c);
    return _pending[url] ??= _analyze(bytes).then((p) {
      _cache[url] = p;
      if (_cache.length > 300) _cache.remove(_cache.keys.first);
      return p;
    }).whenComplete(() => _pending.remove(url));
  }

  static Future<PageInfo> _analyze(Uint8List bytes) async {
    final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buf);
    final size = Size(desc.width.toDouble(), desc.height.toDouble());
    var crop = const Rect.fromLTRB(0, 0, 1, 1);
    try {
      // analisi su una copia piccola
      final tw = 120;
      final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: (tw * size.height / size.width).round().clamp(1, 4000));
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null) crop = _bounds(data, img.width, img.height);
      img.dispose();
      codec.dispose();
    } catch (_) {}
    desc.dispose();
    buf.dispose();
    return PageInfo(bytes, size, crop);
  }

  static Rect _bounds(ByteData d, int w, int h) {
    int px(int x, int y) => (y * w + x) * 4;
    final o = px(0, 0);
    final br = d.getUint8(o), bg = d.getUint8(o + 1), bb = d.getUint8(o + 2);
    bool differs(int x, int y) {
      final i = px(x, y);
      return (d.getUint8(i) - br).abs() + (d.getUint8(i + 1) - bg).abs() + (d.getUint8(i + 2) - bb).abs() > 60;
    }

    bool rowHas(int y) {
      var n = 0;
      for (var x = 0; x < w; x++) {
        if (differs(x, y) && ++n > w * 0.01) return true;
      }
      return false;
    }

    bool colHas(int x) {
      var n = 0;
      for (var y = 0; y < h; y++) {
        if (differs(x, y) && ++n > h * 0.01) return true;
      }
      return false;
    }

    var top = 0, bottom = h - 1, left = 0, right = w - 1;
    while (top < bottom && !rowHas(top)) {
      top++;
    }
    while (bottom > top && !rowHas(bottom)) {
      bottom--;
    }
    while (left < right && !colHas(left)) {
      left++;
    }
    while (right > left && !colHas(right)) {
      right--;
    }
    final r = Rect.fromLTRB(
      ((left - 1) / w).clamp(0.0, 1.0),
      ((top - 1) / h).clamp(0.0, 1.0),
      ((right + 2) / w).clamp(0.0, 1.0),
      ((bottom + 2) / h).clamp(0.0, 1.0),
    );
    if (r.width < 0.3 || r.height < 0.3) return const Rect.fromLTRB(0, 0, 1, 1);
    return r;
  }
}

/// Pagina del manga: ritaglio dei bordi, metà di una pagina larga, rotazione.
class MangaPage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final String? sourceId, managerId;
  final bool crop;
  final int half; // 0 intera, 1 metà sinistra, 2 metà destra
  final bool rotateWide;
  final bool fitWidth; // verticale lungo
  final double placeholderHeight;
  final int number;
  final Color background;
  final ValueChanged<PageInfo>? onInfo;
  const MangaPage({
    super.key,
    required this.url,
    this.headers,
    this.sourceId,
    this.managerId,
    this.crop = false,
    this.half = 0,
    this.rotateWide = false,
    this.fitWidth = false,
    this.placeholderHeight = 500,
    required this.number,
    this.background = Colors.black,
    this.onInfo,
  });

  @override
  State<MangaPage> createState() => _MangaPageState();
}

class _MangaPageState extends State<MangaPage> {
  PageInfo? _info;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _go();
  }

  @override
  void didUpdateWidget(MangaPage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _info = null;
      _error = null;
      _go();
    }
  }

  void _go() {
    final cached = PageInfos.peek(widget.url);
    if (cached != null) {
      _info = cached;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onInfo?.call(cached));
      return;
    }
    MangaImages.get(widget.url, headers: widget.headers, sourceId: widget.sourceId, managerId: widget.managerId).then((b) async {
      if (b == null) throw Exception('immagine vuota');
      final info = await PageInfos.get(widget.url, b);
      if (!mounted) return;
      setState(() => _info = info);
      widget.onInfo?.call(info);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final fg = widget.background.computeLuminance() > 0.5 ? const Color(0xFF6B5F57) : const Color(0xFF8A7E75);
    if (info == null) {
      return Container(
        height: widget.fitWidth ? widget.placeholderHeight : null,
        color: widget.background,
        alignment: Alignment.center,
        child: _error != null
            ? GestureDetector(
                onTap: () => setState(() {
                  _error = null;
                  _go();
                }),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.broken_image_outlined, color: fg),
                  const SizedBox(height: 6),
                  Text('Pagina ${widget.number} non caricata · tocca per riprovare', style: LK.label(10, color: fg, spacing: 0.3)),
                ]),
              )
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE2B84B))),
                const SizedBox(height: 10),
                Text('${widget.number}', style: LK.label(11, color: fg, spacing: 0.4)),
              ]),
      );
    }
    // area visibile: ritaglio, poi metà
    var r = widget.crop ? info.crop : const Rect.fromLTRB(0, 0, 1, 1);
    if (widget.half == 1) r = Rect.fromLTRB(r.left, r.top, r.left + r.width / 2, r.bottom);
    if (widget.half == 2) r = Rect.fromLTRB(r.left + r.width / 2, r.top, r.right, r.bottom);
    final wf = r.width, hf = r.height;
    double align(double start, double f) => f >= 0.999 ? 0 : (2 * start / (1 - f) - 1).clamp(-1.0, 1.0);
    Widget img = ClipRect(
      child: Align(
        alignment: Alignment(align(r.left, wf), align(r.top, hf)),
        widthFactor: wf,
        heightFactor: hf,
        child: Image.memory(info.bytes, width: info.size.width, height: info.size.height, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
      ),
    );
    if (widget.rotateWide && widget.half == 0 && info.wide && !widget.fitWidth) img = RotatedBox(quarterTurns: 1, child: img);
    return FittedBox(fit: widget.fitWidth ? BoxFit.fitWidth : BoxFit.contain, child: img);
  }
}
