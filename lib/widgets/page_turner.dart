import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sfoglio "page curl" come Google Libri: il bordo del foglio segue il dito,
/// la pagina si piega lungo una linea, sul retro si intravede il testo
/// specchiato e sotto compare la pagina successiva con l'ombra della piega.
class PageTurner extends StatefulWidget {
  final int count;
  final int index;
  final Widget Function(int index) builder; // riceve anche -1 e count (bordi del capitolo)
  final ValueChanged<int> onChanged;
  final VoidCallback onBeforeFirst;
  final VoidCallback onAfterLast;
  final bool canGoBefore;
  final bool canGoAfter;
  final VoidCallback onCenterTap;
  final Color background;
  final String animation; // Arricciatura | Scorrimento | Nessuna
  final bool tapEdges;
  final bool invertTaps;

  const PageTurner({
    super.key,
    required this.count,
    required this.index,
    required this.builder,
    required this.onChanged,
    required this.onBeforeFirst,
    required this.onAfterLast,
    required this.canGoBefore,
    required this.canGoAfter,
    required this.onCenterTap,
    required this.background,
    this.animation = 'Arricciatura',
    this.tapEdges = true,
    this.invertTaps = false,
  });

  @override
  State<PageTurner> createState() => PageTurnerState();
}

class PageTurnerState extends State<PageTurner> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this);
  int _dir = 0; // 1 avanti, -1 indietro
  Size _size = Size.zero;

  // Punto "afferrato" (bordo destro del foglio che gira) e posizione del dito.
  double _anchorY = 0;
  double _fx = 0, _fy = 0;
  double _startX = 0, _startY = 0;
  double _fromX = 0, _toX = 0, _fromY = 0, _toY = 0;

  @override
  void initState() {
    super.initState();
    _a.addListener(() {
      final t = Curves.easeOutCubic.transform(_a.value);
      setState(() {
        _fx = _fromX + (_toX - _fromX) * t;
        _fy = _fromY + (_toY - _fromY) * t;
      });
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  double get _w => _size.width;
  double get _h => _size.height;

  bool _allowed(int dir) {
    final target = widget.index + dir;
    if (target < 0) return widget.canGoBefore;
    if (target >= widget.count) return widget.canGoAfter;
    return true;
  }

  Future<void> _animateTo(double x, double y, {required bool commit}) async {
    _fromX = _fx;
    _fromY = _fy;
    _toX = x;
    _toY = y;
    final dist = (x - _fx).abs() / (2 * _w);
    _a.duration = Duration(milliseconds: (420 * dist).round().clamp(120, 420));
    await _a.forward(from: 0);
    if (!mounted) return;
    final dir = _dir;
    setState(() => _dir = 0);
    if (!commit) return;
    final target = widget.index + dir;
    if (target < 0) {
      widget.onBeforeFirst();
    } else if (target >= widget.count) {
      widget.onAfterLast();
    } else {
      widget.onChanged(target);
    }
  }

  void _begin(int dir, double y) {
    _dir = dir;
    _anchorY = y.clamp(_h * 0.15, _h * 0.85);
    _fy = _anchorY;
    _fx = dir == 1 ? _w : -_w; // avanti: foglio piatto; indietro: foglio già girato
  }

  void turn(int dir) {
    if (_a.isAnimating || _dir != 0 || !_allowed(dir)) return;
    if (widget.animation == 'Nessuna') {
      _dir = dir;
      _fx = dir == 1 ? -_w : _w;
      _animateTo(_fx, _fy, commit: true);
      return;
    }
    setState(() => _begin(dir, _h * 0.55));
    // piccola inclinazione come quando si gira con un tocco
    if (dir == 1) {
      _animateTo(-_w, _anchorY - _h * 0.04, commit: true);
    } else {
      _animateTo(_w, _anchorY, commit: true);
    }
  }

  /// Tocco inoltrato da un paragrafo (coordinate globali).
  void tapAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    _tap(box.globalToLocal(global));
  }

  void _tap(Offset local) {
    final x = local.dx / _w;
    final back = widget.invertTaps ? 1 : -1;
    if (widget.tapEdges && x < 0.3) {
      turn(back);
    } else if (widget.tapEdges && x > 0.7) {
      turn(-back);
    } else {
      widget.onCenterTap();
    }
  }

  void _onStart(DragStartDetails d) {
    _startX = d.localPosition.dx;
    _startY = d.localPosition.dy;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_a.isAnimating) return;
    final dx = d.localPosition.dx - _startX;
    if (_dir == 0) {
      if (dx.abs() < 2) return;
      final dir = dx < 0 ? 1 : -1;
      if (!_allowed(dir)) return;
      setState(() => _begin(dir, _startY));
    }
    final dy = d.localPosition.dy - _startY;
    setState(() {
      if (_dir == 1) {
        _fx = (_w + dx * 1.6).clamp(-_w, _w);
      } else {
        _fx = (-_w + dx * 2.0).clamp(-_w, _w);
      }
      _fy = _anchorY + dy * 0.45;
    });
  }

  void _onEnd(DragEndDetails d) {
    if (_dir == 0 || _a.isAnimating) return;
    final v = d.primaryVelocity ?? 0;
    if (_dir == 1) {
      final go = v < -350 || (_fx < _w * 0.45 && v < 350);
      _animateTo(go ? -_w : _w, go ? _fy : _anchorY, commit: go);
    } else {
      final go = v > 350 || (_fx > -_w * 0.35 && v > -350);
      _animateTo(go ? _w : -_w, go ? _anchorY : _fy, commit: go);
    }
  }

  Widget _page(int i) => RepaintBoundary(
        child: ColoredBox(color: widget.background, child: SizedBox(width: _w, height: _h, child: widget.builder(i))),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onStart,
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        onTapUp: (d) => _tap(d.localPosition),
        child: _dir == 0 ? _page(widget.index) : (widget.animation == 'Scorrimento' ? _slide() : _curl()),
      );
    });
  }

  /// Scorrimento laterale semplice: il foglio scivola via e scopre quello sotto.
  Widget _slide() {
    final top = _dir == 1 ? widget.index : widget.index - 1;
    final under = _dir == 1 ? widget.index + 1 : widget.index;
    final off = (_fx - _w) / 2; // da 0 a -_w
    return Stack(clipBehavior: Clip.hardEdge, children: [
      _page(under),
      Transform.translate(
        offset: Offset(off, 0),
        child: DecoratedBox(
          decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 16)]),
          child: _page(top),
        ),
      ),
    ]);
  }

  Widget _curl() {
    final top = _dir == 1 ? widget.index : widget.index - 1; // foglio che si piega
    final under = _dir == 1 ? widget.index + 1 : widget.index;
    final g = _Fold(Offset(_w, _anchorY), Offset(_fx, _fy), _size);
    if (!g.valid) {
      return _dir == 1 ? _page(top) : _page(under);
    }
    return Stack(clipBehavior: Clip.hardEdge, children: [
      // pagina sotto (dal lato della piega verso il bordo)
      ClipPath(clipper: _PolyClip(g.underPoly), child: _page(under)),
      // parte del foglio ancora piatta
      ClipPath(clipper: _PolyClip(g.flatPoly), child: _page(top)),
      // ombra della piega sulla pagina sotto
      IgnorePointer(child: CustomPaint(size: _size, painter: _ShadowPainter(g))),
      // retro del foglio: la parte piegata, specchiata lungo la linea
      Transform(
        transform: g.reflection,
        child: ClipPath(
          clipper: _PolyClip(g.underPoly),
          child: Stack(children: [
            _page(top),
            Positioned.fill(child: ColoredBox(color: widget.background.withValues(alpha: 0.82))),
            Positioned.fill(child: CustomPaint(painter: _BackShade(g))),
          ]),
        ),
      ),
    ]);
  }
}

/// Geometria della piega: linea = asse tra il bordo afferrato A e il dito F.
class _Fold {
  final Offset a, f;
  final Size size;
  late final bool valid;
  late final Offset m; // punto medio sulla linea
  late final Offset n; // normale verso A (lato "girato")
  late final List<Offset> flatPoly; // foglio che resta piatto
  late final List<Offset> underPoly; // zona che si scopre
  late final Matrix4 reflection;

  _Fold(this.a, this.f, this.size) {
    final d = a - f;
    final len = d.distance;
    valid = len > 0.5;
    if (!valid) return;
    n = d / len;
    m = (a + f) / 2;
    final rect = [Offset.zero, Offset(size.width, 0), Offset(size.width, size.height), Offset(0, size.height)];
    flatPoly = _clip(rect, (p) => -_side(p));
    underPoly = _clip(rect, _side);
    final nx = n.dx, ny = n.dy;
    final k = 2 * (m.dx * nx + m.dy * ny);
    reflection = Matrix4(
      1 - 2 * nx * nx, -2 * nx * ny, 0, 0, //
      -2 * nx * ny, 1 - 2 * ny * ny, 0, 0, //
      0, 0, 1, 0, //
      k * nx, k * ny, 0, 1,
    );
  }

  double _side(Offset p) => (p.dx - m.dx) * n.dx + (p.dy - m.dy) * n.dy;

  /// Sutherland–Hodgman su un semipiano (tiene i punti con f(p) >= 0).
  static List<Offset> _clip(List<Offset> poly, double Function(Offset) f) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i], q = poly[(i + 1) % poly.length];
      final fp = f(p), fq = f(q);
      if (fp >= 0) out.add(p);
      if ((fp >= 0) != (fq >= 0)) {
        final t = fp / (fp - fq);
        out.add(Offset(p.dx + (q.dx - p.dx) * t, p.dy + (q.dy - p.dy) * t));
      }
    }
    return out;
  }

  /// Quanto è avanzata la piega (0 = piatto, 1 = girato).
  double get progress => ((a.dx - f.dx) / (2 * size.width)).clamp(0.0, 1.0);
}

class _PolyClip extends CustomClipper<Path> {
  final List<Offset> pts;
  _PolyClip(this.pts);
  @override
  Path getClip(Size size) {
    final p = Path();
    if (pts.length >= 3) p.addPolygon(pts, true);
    return p;
  }

  @override
  bool shouldReclip(_PolyClip old) => true;
}

class _ShadowPainter extends CustomPainter {
  final _Fold g;
  _ShadowPainter(this.g);

  @override
  void paint(Canvas c, Size s) {
    if (g.underPoly.length < 3) return;
    final strength = math.sin(g.progress * math.pi).clamp(0.25, 1.0);
    final width = 46.0 * strength + 10;
    final path = Path()..addPolygon(g.underPoly, true);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.black.withValues(alpha: 0.42 * strength), Colors.black.withValues(alpha: 0.0)],
      ).createShader(Rect.fromPoints(g.m, g.m + g.n * width));
    // il gradiente va lungo la normale: lo ottengo ruotando il canvas
    c.save();
    c.clipPath(path);
    c.translate(g.m.dx, g.m.dy);
    c.rotate(math.atan2(g.n.dy, g.n.dx));
    paint.shader = LinearGradient(
      colors: [Colors.black.withValues(alpha: 0.42 * strength), Colors.black.withValues(alpha: 0.0)],
    ).createShader(Rect.fromLTWH(0, -2000, width, 4000));
    c.drawRect(Rect.fromLTWH(0, -2000, width, 4000), paint);
    c.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => true;
}

/// Sfumatura sul retro del foglio: più chiaro sulla piega, più scuro verso il bordo.
class _BackShade extends CustomPainter {
  final _Fold g;
  _BackShade(this.g);

  @override
  void paint(Canvas c, Size s) {
    // Il canvas qui è nelle coordinate della pagina *prima* della riflessione:
    // la piega è sulla linea, il bordo libero è verso A.
    c.save();
    c.translate(g.m.dx, g.m.dy);
    c.rotate(math.atan2(g.n.dy, g.n.dx));
    final len = (g.a - g.m).distance + 2;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white.withValues(alpha: 0.10), Colors.black.withValues(alpha: 0.06), Colors.black.withValues(alpha: 0.22)],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromLTWH(0, -2000, len, 4000));
    c.drawRect(Rect.fromLTWH(0, -2000, len + 4000, 4000), paint);
    c.restore();
  }

  @override
  bool shouldRepaint(_BackShade old) => true;
}
