import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

enum _Mode { walk, sit, sleep, away }

/// Il "cervello" del gatto: su quale scaffale si trova e cosa sta facendo.
/// Ogni scaffale mostra il gatto solo se è il suo turno.
class CatBrain extends ChangeNotifier {
  CatBrain._();
  static final I = CatBrain._();

  final _r = math.Random();
  List<String> rows = [];
  String? row;
  double x = 0.3; // 0–1 sulla larghezza dello scaffale
  int dir = 1;
  _Mode mode = _Mode.sit;
  double modeLeft = 3; // secondi
  double target = 0.6;
  double meow = 0; // secondi di fumetto "Miao"

  /// La libreria comunica quali scaffali ci sono.
  void setRows(List<String> keys) {
    rows = keys;
    if (rows.isEmpty) return;
    if (row == null || !rows.contains(row)) {
      row = rows[DateTime.now().day % rows.length];
      x = 0.2 + _r.nextDouble() * 0.6;
      _choose();
    }
  }

  void _choose() {
    final p = _r.nextDouble();
    if (p < 0.45) {
      mode = _Mode.walk;
      // a volte se ne va verso un altro scaffale
      if (rows.length > 1 && _r.nextDouble() < 0.3) {
        target = _r.nextBool() ? -0.15 : 1.15;
      } else {
        target = 0.08 + _r.nextDouble() * 0.84;
      }
      dir = target > x ? 1 : -1;
    } else if (p < 0.75) {
      mode = _Mode.sit;
      modeLeft = 4 + _r.nextDouble() * 6;
    } else {
      mode = _Mode.sleep;
      modeLeft = 25 + _r.nextDouble() * 35;
    }
  }

  void tick(double dt, double width) {
    if (meow > 0) meow = math.max(0, meow - dt);
    switch (mode) {
      case _Mode.walk:
        final speed = 38 / math.max(width, 1);
        x += dir * speed * dt;
        if ((dir > 0 && x >= target) || (dir < 0 && x <= target)) {
          if (target < 0 || target > 1) {
            // passa a un altro scaffale ed entra dal lato opposto
            final others = rows.where((k) => k != row).toList();
            row = others[_r.nextInt(others.length)];
            x = dir > 0 ? -0.1 : 1.1;
            target = 0.15 + _r.nextDouble() * 0.7;
            dir = target > x ? 1 : -1;
            mode = _Mode.away;
            modeLeft = 6 + _r.nextDouble() * 10;
            notifyListeners();
            return;
          }
          x = target;
          mode = _Mode.sit;
          modeLeft = 3 + _r.nextDouble() * 4;
        }
      case _Mode.away:
        modeLeft -= dt;
        if (modeLeft <= 0) {
          mode = _Mode.walk;
          notifyListeners();
        }
        return;
      default:
        modeLeft -= dt;
        if (modeLeft <= 0) _choose();
    }
    notifyListeners();
  }

  void poke() {
    meow = 1.6;
    if (mode == _Mode.sleep) {
      mode = _Mode.sit;
      modeLeft = 5;
    }
    notifyListeners();
  }
}

/// Il gatto disegnato sopra uno scaffale (solo quello in cui si trova).
class ShelfCat extends StatefulWidget {
  final String rowKey;
  final double boardTop;
  const ShelfCat({super.key, required this.rowKey, required this.boardTop});
  @override
  State<ShelfCat> createState() => _ShelfCatState();
}

class _ShelfCatState extends State<ShelfCat> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _width = 300, _clock = 0;

  bool get _here => CatBrain.I.row == widget.rowKey && CatBrain.I.mode != _Mode.away;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    CatBrain.I.addListener(_changed);
    _sync();
  }

  void _sync() {
    // il ticker gira solo nello scaffale dove sta il gatto (o lo aspetta)
    final mine = CatBrain.I.row == widget.rowKey;
    if (mine && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!mine && _ticker.isActive) {
      _ticker.stop();
    }
  }

  bool _shown = false;

  void _changed() {
    _sync();
    final now = _here;
    if (now || _shown) {
      _shown = now;
      if (mounted) setState(() {});
    }
  }

  void _onTick(Duration d) {
    final dt = _last == Duration.zero ? 0.016 : (d - _last).inMicroseconds / 1e6;
    _last = d;
    _clock += dt;
    CatBrain.I.tick(dt.clamp(0, 0.1), _width);
  }

  @override
  void dispose() {
    CatBrain.I.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _width = c.maxWidth;
      if (!_here) return const SizedBox.shrink();
      final b = CatBrain.I;
      const w = 58.0, h = 40.0;
      final left = 14 + b.x * (c.maxWidth - 28) - w / 2;
      return Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: left,
          top: widget.boardTop - h + 4,
          width: w,
          height: h,
          child: GestureDetector(
            onTap: b.poke,
            child: CustomPaint(painter: _CatPainter(b.mode, b.dir, _clock)),
          ),
        ),
        if (b.meow > 0)
          Positioned(
            left: left + (b.dir > 0 ? w - 8 : -34),
            top: widget.boardTop - h - 22,
            child: Opacity(
              opacity: b.meow.clamp(0.0, 1.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: LK.border)),
                child: Text('Miao!', style: LK.body(11.5, style: FontStyle.italic)),
              ),
            ),
          ),
      ]);
    });
  }
}

class _CatPainter extends CustomPainter {
  final _Mode mode;
  final int dir;
  final double t;
  _CatPainter(this.mode, this.dir, this.t);

  static const _fur = Color(0xFFE09A4F), _dark = Color(0xFFB8692A), _belly = Color(0xFFF6D9B0), _ink = Color(0xFF3A2A20);

  @override
  void paint(Canvas c, Size s) {
    c.save();
    if (dir < 0) {
      c.translate(s.width, 0);
      c.scale(-1, 1);
    }
    switch (mode) {
      case _Mode.sleep:
        _sleep(c, s);
      case _Mode.sit:
        _sit(c, s);
      default:
        _walk(c, s);
    }
    c.restore();
    if (mode == _Mode.sleep) {
      // le zeta salgono anche col gatto girato
      for (var i = 0; i < 3; i++) {
        final ph = ((t * 0.35) + i / 3) % 1;
        final tp = TextPainter(
          text: TextSpan(text: 'z', style: LK.display(9 + ph * 6, color: _ink.withValues(alpha: (1 - ph) * 0.8))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset(s.width * 0.62 + ph * 14, s.height * 0.25 - ph * 26));
      }
    }
  }

  Paint get _f => Paint()..color = _fur;
  Paint get _line => Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;

  void _head(Canvas c, Offset o, {bool closed = false}) {
    c.drawPath(Path()..moveTo(o.dx - 8, o.dy - 4)..lineTo(o.dx - 6, o.dy - 13)..lineTo(o.dx - 1, o.dy - 7)..close(), _f);
    c.drawPath(Path()..moveTo(o.dx + 8, o.dy - 4)..lineTo(o.dx + 6, o.dy - 13)..lineTo(o.dx + 1, o.dy - 7)..close(), _f);
    c.drawPath(Path()..moveTo(o.dx - 6.5, o.dy - 6)..lineTo(o.dx - 5.8, o.dy - 10.5)..lineTo(o.dx - 3, o.dy - 7)..close(), Paint()..color = const Color(0xFFF2A9A0));
    c.drawOval(Rect.fromCenter(center: o, width: 19, height: 16), _f);
    c.drawOval(Rect.fromCenter(center: o + const Offset(2, 4), width: 9, height: 6), Paint()..color = _belly);
    if (closed) {
      c.drawArc(Rect.fromCenter(center: o + const Offset(-3, -1), width: 4, height: 3), 0, math.pi, false, _line);
      c.drawArc(Rect.fromCenter(center: o + const Offset(4, -1), width: 4, height: 3), 0, math.pi, false, _line);
    } else {
      final blink = (t % 4) < 0.12;
      for (final dx in [-3.0, 4.0]) {
        if (blink) {
          c.drawLine(o + Offset(dx - 1.5, -1), o + Offset(dx + 1.5, -1), _line);
        } else {
          c.drawOval(Rect.fromCenter(center: o + Offset(dx, -1), width: 3, height: 3.6), Paint()..color = const Color(0xFF6E8F3A));
          c.drawOval(Rect.fromCenter(center: o + Offset(dx, -1), width: 1, height: 3), Paint()..color = _ink);
        }
      }
    }
    c.drawCircle(o + const Offset(1, 2.5), 1, Paint()..color = const Color(0xFFD9776B));
    // baffi
    final wh = Paint()
      ..color = _ink.withValues(alpha: 0.5)
      ..strokeWidth = 0.6;
    c.drawLine(o + const Offset(5, 3), o + const Offset(13, 1.5), wh);
    c.drawLine(o + const Offset(5, 4), o + const Offset(13, 5), wh);
  }

  void _stripes(Canvas c, Rect body) {
    final p = Paint()
      ..color = _dark
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final x = body.left + body.width * (0.3 + i * 0.18);
      c.drawLine(Offset(x, body.top + 1), Offset(x - 2, body.top + body.height * 0.4), p);
    }
  }

  void _walk(Canvas c, Size s) {
    final step = math.sin(t * 9);
    final body = Rect.fromLTWH(10, s.height - 24, 32, 15);
    // coda
    final tail = Path()
      ..moveTo(body.left + 2, body.top + 5)
      ..quadraticBezierTo(body.left - 10, body.top - 2 + math.sin(t * 3) * 3, body.left - 6, body.top - 14);
    c.drawPath(tail, Paint()
      ..color = _fur
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round);
    // zampe
    final leg = Paint()
      ..color = _fur
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;
    for (final (x, ph) in [(body.left + 6, 0.0), (body.left + 12, math.pi), (body.right - 9, math.pi), (body.right - 3, 0.0)]) {
      final sw = math.sin(t * 9 + ph) * 3;
      c.drawLine(Offset(x, body.bottom - 3), Offset(x + sw, s.height - 2), leg);
    }
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(8)), _f);
    _stripes(c, body);
    _head(c, Offset(body.right + 3, body.top - 1 + step * 0.6));
  }

  void _sit(Canvas c, Size s) {
    final base = s.height - 2;
    final tail = Path()
      ..moveTo(18, base - 3)
      ..quadraticBezierTo(4, base - 2, 6 + math.sin(t * 2) * 2, base - 13);
    c.drawPath(tail, Paint()
      ..color = _fur
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round);
    final body = Rect.fromLTWH(14, base - 26, 24, 26);
    c.drawOval(body, _f);
    c.drawOval(Rect.fromLTWH(26, base - 20, 10, 16), Paint()..color = _belly);
    _stripes(c, Rect.fromLTWH(12, base - 24, 20, 20));
    // zampe davanti
    final leg = Paint()
      ..color = _fur
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(31, base - 10), Offset(32, base - 1), leg);
    c.drawLine(Offset(36, base - 10), Offset(37, base - 1), leg);
    _head(c, Offset(33, base - 29));
  }

  void _sleep(Canvas c, Size s) {
    final base = s.height - 2;
    final breathe = 1 + math.sin(t * 2.2) * 0.03;
    final body = Rect.fromCenter(center: Offset(28, base - 9), width: 34 * breathe, height: 17 * breathe);
    c.drawOval(body, _f);
    _stripes(c, body);
    // coda avvolta
    c.drawPath(
        Path()
          ..moveTo(body.left + 3, base - 4)
          ..quadraticBezierTo(body.center.dx, base + 1, body.right - 2, base - 3),
        Paint()
          ..color = _dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    _head(c, Offset(body.right - 6, base - 10), closed: true);
  }

  @override
  bool shouldRepaint(_CatPainter o) => true;
}
