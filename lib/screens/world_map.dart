import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/gemini.dart';
import '../services/wiki.dart';
import '../theme.dart';
import 'wiki_screens.dart';

/// Un luogo pronto per essere disegnato.
class _Place {
  final WikiEntry e;
  final Offset at;
  final String setting;
  final List<String> roads;
  final int order;
  _Place(this.e, this.at, this.setting, this.roads, this.order);
}

/// La mappa del mondo: i luoghi della wiki disegnati su pergamena,
/// con la nebbia sulle zone non ancora scoperte.
class WorldMapScreen extends StatefulWidget {
  final Book book;
  const WorldMapScreen({super.key, required this.book});
  @override
  State<WorldMapScreen> createState() => _WorldMapScreenState();
}

class _WorldMapScreenState extends State<WorldMapScreen> {
  static const size = 1000.0;
  Wiki? _w;
  bool _busy = false;
  String? _error;
  bool _journey = true;
  final _tc = TransformationController();
  Matrix4? _home;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _load(auto: true);
  }

  Future<void> _load({bool auto = false}) async {
    final w = await WikiStore.I.forBook(widget.book);
    if (!mounted) return;
    setState(() => _w = w);
    final todo = WikiStore.I.unmappedPlaces(w, WikiStore.I.limitFor(widget.book));
    if (auto && todo.isNotEmpty) _layout();
  }

  Future<void> _layout() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await WikiStore.I.layoutMap(widget.book);
    } on GeminiError catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Non sono riuscito a disegnare la mappa: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  List<_Place> _places(Wiki w, int limit) {
    final list = <_Place>[];
    final placed = w.entries.values.where((e) => e.type == 'luogo' && e.visibleAt(limit) && e.extraAt('map', limit) != null).toList()
      ..sort((a, b) => a.firstPos.compareTo(b.firstPos));
    for (var i = 0; i < placed.length; i++) {
      final e = placed[i];
      final m = e.extraAt('map', limit) as Map;
      final scene = e.extraAt('scene', limit);
      final setting = scene is Map ? (scene['setting'] as String? ?? '') : '';
      list.add(_Place(e, Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()), setting, ((m['roads'] as List?) ?? const []).cast<String>(), i));
    }
    return list;
  }

  void _tap(TapUpDetails d, List<_Place> places) {
    _Place? best;
    var bd = 46.0;
    for (final p in places) {
      final dist = (p.at - d.localPosition).distance;
      if (dist < bd) {
        bd = dist;
        best = p;
      }
    }
    if (best != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryScreen(book: widget.book, entryId: best!.e.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    final b = widget.book;
    final limit = WikiStore.I.limitFor(b);
    final places = w == null ? <_Place>[] : _places(w, limit);
    final todo = w == null ? 0 : WikiStore.I.unmappedPlaces(w, limit).length;
    return Scaffold(
      backgroundColor: const Color(0xFF2B2420),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.arrow_back, size: 18, color: Color(0xFFE9DCC3)),
                        const SizedBox(width: 6),
                        Text('Wiki', style: LK.body(14, color: const Color(0xFFE9DCC3))),
                      ]),
                    ),
                  ),
                  Text('Mappa del mondo', style: LK.display(26, color: const Color(0xFFF3E7CF))),
                ]),
              ),
              if (places.length > 1)
                IconButton(
                  tooltip: 'Il viaggio',
                  onPressed: () => setState(() => _journey = !_journey),
                  icon: Icon(Icons.route, color: _journey ? const Color(0xFFE2B95C) : const Color(0x88E9DCC3)),
                ),
              IconButton(
                tooltip: 'Centra',
                onPressed: () => _tc.value = _home ?? Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong_outlined, color: Color(0xFFE9DCC3)),
              ),
            ]),
          ),
          if (_busy || _error != null || todo > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                if (_busy) ...[
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE2B95C))),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Il cartografo sta disegnando i nuovi luoghi…', style: LK.body(13, color: const Color(0xFFE9DCC3)))),
                ] else ...[
                  Expanded(
                    child: Text(_error ?? '$todo ${todo == 1 ? 'luogo nuovo' : 'luoghi nuovi'} da aggiungere alla mappa',
                        style: LK.body(13, color: _error != null ? const Color(0xFFF0A08A) : const Color(0xFFE9DCC3))),
                  ),
                  TextButton(onPressed: _layout, child: Text(_error != null ? 'Riprova' : 'Disegna', style: LK.body(13.5, color: const Color(0xFFE2B95C)))),
                ],
              ]),
            ),
          Expanded(
            child: w == null
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE2B95C)))
                : places.isEmpty && !_busy
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Text('Nessun luogo sulla mappa per ora: si riempie man mano che leggi.',
                              textAlign: TextAlign.center, style: LK.body(15, color: const Color(0xFFE9DCC3), style: FontStyle.italic)),
                        ),
                      )
                    : LayoutBuilder(builder: (context, c) {
                        final fit = math.min(c.maxWidth, c.maxHeight) / size;
                        _home = Matrix4.identity()
                          ..translate((c.maxWidth - size * fit) / 2, (c.maxHeight - size * fit) / 2)
                          ..scale(fit, fit, 1);
                        if (!_fitted) {
                          _fitted = true;
                          _tc.value = _home!;
                        }
                        return InteractiveViewer(
                          transformationController: _tc,
                          minScale: fit * 0.9,
                          maxScale: 4,
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(200),
                          child: GestureDetector(
                            onTapUp: (d) => _tap(d, places),
                            child: SizedBox(
                              width: size,
                              height: size,
                              child: CustomPaint(painter: _MapPainter(places, (w.mapInfo['sea'] as String?) ?? 'nessuno', b.title, _journey)),
                            ),
                          ),
                        );
                      }),
          ),
        ]),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final List<_Place> places;
  final String sea;
  final String title;
  final bool journey;
  _MapPainter(this.places, this.sea, this.title, this.journey);

  static const _paper = Color(0xFFEBDDBF), _paperDark = Color(0xFFD9C59C), _ink = Color(0xFF4A3527), _sea = Color(0xFFB9C7BE), _seaInk = Color(0xFF6E8A85);

  Map<String, _Place> get _byId => {for (final p in places) p.e.id: p};

  @override
  void paint(Canvas c, Size s) {
    final rect = Offset.zero & s;
    final rnd = math.Random(title.hashCode);
    final hasSea = sea != 'nessuno' && sea.isNotEmpty;

    // fondo: mare o pergamena
    c.drawRect(rect, Paint()..color = hasSea ? _sea : _paper);
    if (hasSea) {
      // terre: blob attorno ai luoghi (prima il bordo, poi la terra)
      final land = _landBlobs(s);
      for (final (o, r, seed) in land) {
        c.drawPath(_blob(o, r + 7, seed), Paint()..color = _seaInk.withValues(alpha: 0.55));
      }
      for (final (o, r, seed) in land) {
        c.drawPath(_blob(o, r, seed), Paint()..color = _paper);
      }
      // onde
      final wave = Paint()
        ..color = _seaInk.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (var i = 0; i < 70; i++) {
        final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
        if (land.any((l) => (l.$1 - o).distance < l.$2 + 25)) continue;
        final path = Path()
          ..moveTo(o.dx - 9, o.dy)
          ..quadraticBezierTo(o.dx - 4.5, o.dy - 4, o.dx, o.dy)
          ..quadraticBezierTo(o.dx + 4.5, o.dy - 4, o.dx + 9, o.dy);
        c.drawPath(path, wave);
      }
    }
    // macchie della pergamena
    for (var i = 0; i < 26; i++) {
      final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
      c.drawCircle(o, 20 + rnd.nextDouble() * 70, Paint()..color = _paperDark.withValues(alpha: 0.12 + rnd.nextDouble() * 0.12));
    }

    // strade
    final byId = _byId;
    final road = Paint()
      ..color = _ink.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final done = <String>{};
    for (final p in places) {
      for (final id in p.roads) {
        final q = byId[id];
        if (q == null) continue;
        final k = ([p.e.id, id]..sort()).join('|');
        if (!done.add(k)) continue;
        _dashed(c, p.at, q.at, road, curve: ((k.hashCode % 7) - 3) * 6.0);
      }
    }

    // terreno attorno ai luoghi
    for (final p in places) {
      _terrain(c, p, math.Random(p.e.id.hashCode));
    }

    // il viaggio: i luoghi in ordine di apparizione
    if (journey && places.length > 1) {
      final j = Paint()
        ..color = const Color(0xFFA2312B).withValues(alpha: 0.75)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final seq = [...places]..sort((a, b) => a.order.compareTo(b.order));
      for (var i = 1; i < seq.length; i++) {
        if ((seq[i].at - seq[i - 1].at).distance < 12) continue;
        _dotted(c, seq[i - 1].at, seq[i].at, j);
      }
    }

    // icone e nomi
    for (final p in places) {
      _icon(c, p);
    }
    for (final p in places) {
      _label(c, p);
    }

    // nebbia su ciò che non hai ancora scoperto
    c.saveLayer(rect, Paint());
    c.drawRect(rect, Paint()..color = const Color(0xFF8F8574).withValues(alpha: 0.78));
    for (final p in places) {
      c.drawCircle(
        p.at,
        190,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = RadialGradient(colors: const [Colors.black, Colors.black, Color(0x00000000)], stops: const [0, 0.55, 1])
              .createShader(Rect.fromCircle(center: p.at, radius: 190)),
      );
    }
    c.restore();

    _compass(c, Offset(s.width - 90, 90));
    _cartouche(c, s);
    // cornice
    c.drawRect(rect.deflate(6), Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    c.drawRect(rect.deflate(13), Paint()
      ..color = _ink.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  List<(Offset, double, int)> _landBlobs(Size s) {
    final out = <(Offset, double, int)>[];
    for (final p in places) {
      out.add((p.at, 120, p.e.id.hashCode));
    }
    final byId = _byId;
    for (final p in places) {
      for (final id in p.roads) {
        final q = byId[id];
        if (q != null) out.add((Offset.lerp(p.at, q.at, 0.5)!, 95, (p.e.id + id).hashCode));
      }
    }
    // in base a dove sta il mare, il continente si allarga verso il lato opposto
    final edge = switch (sea) {
      'nord' => Offset(s.width / 2, s.height * 1.25),
      'sud' => Offset(s.width / 2, -s.height * 0.25),
      'est' => Offset(-s.width * 0.25, s.height / 2),
      'ovest' => Offset(s.width * 1.25, s.height / 2),
      _ => null,
    };
    if (edge != null) {
      for (final p in places) {
        out.add((Offset.lerp(p.at, edge, 0.5)!, 220, p.e.id.hashCode ^ 77));
      }
    }
    return out;
  }

  Path _blob(Offset o, double r, int seed) {
    final rnd = math.Random(seed);
    final n = 18;
    final radii = List.generate(n, (_) => r * (0.78 + rnd.nextDouble() * 0.36));
    final pts = [for (var i = 0; i < n; i++) o + Offset(math.cos(i * 2 * math.pi / n), math.sin(i * 2 * math.pi / n)) * radii[i]];
    final path = Path()..moveTo((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    for (var i = 1; i <= n; i++) {
      final a = pts[i % n], b = pts[(i + 1) % n];
      path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    }
    return path..close();
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, {double curve = 0}) {
    final mid = Offset.lerp(a, b, 0.5)!;
    final d = b - a;
    final normal = d.distance == 0 ? Offset.zero : Offset(-d.dy, d.dx) / d.distance;
    final ctrl = mid + normal * curve;
    const steps = 40;
    for (var i = 0; i < steps; i += 2) {
      Offset q(double t) => Offset(
            (1 - t) * (1 - t) * a.dx + 2 * (1 - t) * t * ctrl.dx + t * t * b.dx,
            (1 - t) * (1 - t) * a.dy + 2 * (1 - t) * t * ctrl.dy + t * t * b.dy,
          );
      c.drawLine(q(i / steps), q((i + 1) / steps), p);
    }
  }

  void _dotted(Canvas c, Offset a, Offset b, Paint p) {
    final len = (b - a).distance;
    final n = (len / 9).floor();
    for (var i = 1; i < n; i++) {
      c.drawCircle(Offset.lerp(a, b, i / n)!, 1.5, p..style = PaintingStyle.fill);
    }
    // freccia
    final dir = (b - a) / len;
    final tip = b - dir * 22;
    final side = Offset(-dir.dy, dir.dx);
    c.drawPath(Path()..moveTo(tip.dx + dir.dx * 8, tip.dy + dir.dy * 8)..lineTo(tip.dx + side.dx * 5, tip.dy + side.dy * 5)..lineTo(tip.dx - side.dx * 5, tip.dy - side.dy * 5)..close(), p);
    p.style = PaintingStyle.stroke;
  }

  void _terrain(Canvas c, _Place p, math.Random r) {
    final ink = Paint()
      ..color = _ink.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    Offset around(double min, double max) {
      final a = r.nextDouble() * math.pi * 2, d = min + r.nextDouble() * (max - min);
      return p.at + Offset(math.cos(a), math.sin(a)) * d;
    }

    switch (p.setting) {
      case 'foresta':
      case 'palude':
        for (var i = 0; i < 16; i++) {
          final o = around(22, 70);
          final h = 10 + r.nextDouble() * 6;
          c.drawPath(Path()..moveTo(o.dx, o.dy - h)..lineTo(o.dx - h * 0.45, o.dy)..lineTo(o.dx + h * 0.45, o.dy)..close(), Paint()..color = const Color(0xFF5E7A4A).withValues(alpha: 0.8));
          c.drawLine(o, o + const Offset(0, 3), ink);
        }
      case 'montagna':
      case 'neve':
        for (var i = 0; i < 7; i++) {
          final o = around(26, 66);
          final h = 16 + r.nextDouble() * 12;
          final path = Path()..moveTo(o.dx - h * 0.7, o.dy)..lineTo(o.dx, o.dy - h)..lineTo(o.dx + h * 0.7, o.dy);
          c.drawPath(path, Paint()..color = p.setting == 'neve' ? Colors.white.withValues(alpha: 0.85) : const Color(0xFFC9B48E));
          c.drawPath(path, ink);
          c.drawLine(Offset(o.dx, o.dy - h), Offset(o.dx + h * 0.2, o.dy - h * 0.3), ink);
        }
      case 'deserto':
        for (var i = 0; i < 8; i++) {
          final o = around(24, 64);
          c.drawArc(Rect.fromCenter(center: o, width: 26, height: 12), math.pi, math.pi, false, ink);
        }
      case 'lago':
      case 'mare':
        c.drawOval(Rect.fromCenter(center: p.at + const Offset(0, 4), width: 76, height: 44), Paint()..color = _sea);
        c.drawOval(Rect.fromCenter(center: p.at + const Offset(0, 4), width: 76, height: 44), Paint()
          ..color = _seaInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4);
      case 'pianura':
        for (var i = 0; i < 12; i++) {
          final o = around(20, 60);
          c.drawLine(o, o + const Offset(-2, -5), ink);
          c.drawLine(o, o + const Offset(2, -5), ink);
        }
      default:
        for (var i = 0; i < 5; i++) {
          final o = around(30, 60);
          c.drawCircle(o, 5, Paint()..color = const Color(0xFF7D9460).withValues(alpha: 0.55));
        }
    }
  }

  void _icon(Canvas c, _Place p) {
    final fill = Paint()..color = _paper;
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final o = p.at;
    switch (p.setting) {
      case 'città':
      case 'villaggio':
        final big = p.setting == 'città';
        for (var i = 0; i < (big ? 4 : 2); i++) {
          final x = o.dx - (big ? 15 : 8) + i * 10, h = big ? 12.0 + (i % 2) * 6 : 9.0;
          final r = Rect.fromLTWH(x, o.dy - h, 9, h);
          c.drawRect(r, fill);
          c.drawRect(r, ink);
          c.drawPath(Path()..moveTo(x - 1, o.dy - h)..lineTo(x + 4.5, o.dy - h - 6)..lineTo(x + 10, o.dy - h)..close(), Paint()..color = const Color(0xFFA2312B));
        }
      case 'castello':
      case 'palazzo':
      case 'accademia':
        final r = Rect.fromCenter(center: o + const Offset(0, -6), width: 30, height: 18);
        c.drawRect(r, fill);
        c.drawRect(r, ink);
        for (final dx in [-15.0, 9.0]) {
          final t = Rect.fromLTWH(o.dx + dx, o.dy - 26, 7, 22);
          c.drawRect(t, fill);
          c.drawRect(t, ink);
          c.drawPath(Path()..moveTo(o.dx + dx - 1, o.dy - 26)..lineTo(o.dx + dx + 3.5, o.dy - 34)..lineTo(o.dx + dx + 8, o.dy - 26)..close(), Paint()..color = const Color(0xFF34548A));
        }
        c.drawLine(o + const Offset(0, -15), o + const Offset(0, -26), ink);
        c.drawPath(Path()..moveTo(0 + o.dx, o.dy - 26)..lineTo(o.dx + 8, o.dy - 23)..lineTo(o.dx, o.dy - 20), Paint()..color = const Color(0xFFA2312B));
      case 'grotta':
        c.drawArc(Rect.fromCenter(center: o, width: 24, height: 22), math.pi, math.pi, true, Paint()..color = _ink.withValues(alpha: 0.85));
      case 'rovine':
        for (var i = 0; i < 3; i++) {
          final r = Rect.fromLTWH(o.dx - 12 + i * 9, o.dy - 8 - (i == 1 ? 8 : 0), 5, 8 + (i == 1 ? 8 : 0));
          c.drawRect(r, fill);
          c.drawRect(r, ink);
        }
      default:
        c.drawCircle(o, 7, fill);
        c.drawCircle(o, 7, ink);
        c.drawCircle(o, 2.5, Paint()..color = _ink);
    }
  }

  void _label(Canvas c, _Place p) {
    final tp = TextPainter(
      text: TextSpan(text: p.e.name, style: LK.display(15, color: _ink, style: FontStyle.italic)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 150);
    final at = p.at + Offset(-tp.width / 2, 12);
    final bg = RRect.fromRectAndRadius(Rect.fromLTWH(at.dx - 4, at.dy - 1, tp.width + 8, tp.height + 2), const Radius.circular(3));
    c.drawRRect(bg, Paint()..color = _paper.withValues(alpha: 0.75));
    tp.paint(c, at);
  }

  void _compass(Canvas c, Offset o) {
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    c.drawCircle(o, 34, ink);
    c.drawCircle(o, 28, ink..strokeWidth = 0.6);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 - math.pi / 2;
      final tip = o + Offset(math.cos(a), math.sin(a)) * 46;
      final l = o + Offset(math.cos(a - 0.5), math.sin(a - 0.5)) * 9, r = o + Offset(math.cos(a + 0.5), math.sin(a + 0.5)) * 9;
      c.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(l.dx, l.dy)..lineTo(o.dx, o.dy)..close(), Paint()..color = i == 0 ? const Color(0xFFA2312B) : _ink);
      c.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(r.dx, r.dy)..lineTo(o.dx, o.dy)..close(), Paint()..color = _paper);
      c.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(r.dx, r.dy)..lineTo(o.dx, o.dy)..close(), ink..strokeWidth = 0.8);
    }
    final tp = TextPainter(text: TextSpan(text: 'N', style: LK.display(14, color: _ink)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, o + Offset(-tp.width / 2, -66));
  }

  void _cartouche(Canvas c, Size s) {
    final tp = TextPainter(
      text: TextSpan(text: title, style: LK.display(22, color: _ink)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 380);
    final r = Rect.fromCenter(center: Offset(s.width / 2, s.height - 58), width: tp.width + 70, height: tp.height + 22);
    final path = Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right - 14, r.center.dy)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left + 14, r.center.dy)
      ..close();
    c.drawPath(path, Paint()..color = _paper);
    c.drawPath(path, Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
    tp.paint(c, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_MapPainter o) => o.places.length != places.length || o.journey != journey || o.sea != sea;
}
