import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/wiki.dart';
import '../theme.dart';

// ======================================================================
// Luoghi: veduta dipinta generata dalla descrizione (scena + ora del giorno)
// ======================================================================

/// Scena di un luogo: quella indicata da Gemini o, in mancanza, dedotta dal nome.
(String setting, String time) placeScene(WikiEntry e, int limit) {
  final sc = e.extraAt('scene', limit);
  String? setting = sc is Map ? sc['setting'] as String? : null;
  String? time = sc is Map ? sc['time'] as String? : null;
  const settings = ['villaggio', 'città', 'castello', 'palazzo', 'accademia', 'foresta', 'montagna', 'mare', 'lago', 'deserto', 'pianura', 'grotta', 'rovine', 'neve', 'palude', 'cielo'];
  if (setting == null || !settings.contains(setting)) {
    final t = '${e.name} ${e.extraAt('kind', limit) ?? ''} ${e.roleAt(limit)}'.toLowerCase();
    bool has(List<String> w) => w.any(t.contains);
    setting = has(['bosco', 'forest', 'selva', 'giungla'])
        ? 'foresta'
        : has(['monte', 'montagn', 'picco', 'vetta', 'catena'])
            ? 'montagna'
            : has(['mare', 'oceano', 'costa', 'porto', 'baia', 'isola'])
                ? 'mare'
                : has(['lago', 'fiume', 'stagno'])
                    ? 'lago'
                    : has(['desert', 'dune', 'sabbi'])
                        ? 'deserto'
                        : has(['castell', 'fortezza', 'rocca', 'forte'])
                            ? 'castello'
                            : has(['palazz', 'reggia', 'tempio'])
                                ? 'palazzo'
                                : has(['accademia', 'scuola', 'istituto', 'università', 'torre'])
                                    ? 'accademia'
                                    : has(['città', 'capitale', 'metropoli'])
                                        ? 'città'
                                        : has(['villaggio', 'paese', 'borgo', 'casa'])
                                            ? 'villaggio'
                                            : has(['grotta', 'caverna', 'dungeon', 'sotterran', 'miniera'])
                                                ? 'grotta'
                                                : has(['rovin'])
                                                    ? 'rovine'
                                                    : has(['palude', 'acquitrino'])
                                                        ? 'palude'
                                                        : has(['ghiacc', 'neve', 'gelo'])
                                                            ? 'neve'
                                                            : 'pianura';
  }
  if (time == null || !const ['alba', 'giorno', 'tramonto', 'notte'].contains(time)) {
    time = const ['giorno', 'tramonto', 'giorno', 'alba'][e.id.hashCode.abs() % 4];
  }
  return (setting, time);
}

class Landscape extends StatelessWidget {
  final WikiEntry entry;
  final int limit;
  final double height;
  final bool fade;
  const Landscape({super.key, required this.entry, required this.limit, this.height = 300, this.fade = true});

  @override
  Widget build(BuildContext context) {
    final (setting, time) = placeScene(entry, limit);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _LandscapePainter(setting, time, entry.id.hashCode, fade)),
    );
  }
}

class _LandscapePainter extends CustomPainter {
  final String setting, time;
  final int seed;
  final bool fade;
  _LandscapePainter(this.setting, this.time, this.seed, this.fade);

  static const _skies = {
    'alba': [Color(0xFFF2B8A0), Color(0xFFF6D7B8), Color(0xFFFBEAD6)],
    'giorno': [Color(0xFF8DBBE0), Color(0xFFC6DFEE), Color(0xFFEEF3EA)],
    'tramonto': [Color(0xFFE39A64), Color(0xFFF1CD97), Color(0xFFF6E7C4)],
    'notte': [Color(0xFF141A33), Color(0xFF243058), Color(0xFF3B4373)],
  };

  /// Scurisce/tinge i colori in base all'ora.
  Color _t(Color c) {
    switch (time) {
      case 'notte':
        return Color.lerp(c, const Color(0xFF151B33), 0.62)!;
      case 'tramonto':
        return Color.lerp(c, const Color(0xFF8A4A3A), 0.18)!;
      case 'alba':
        return Color.lerp(c, const Color(0xFFB07A8A), 0.12)!;
      default:
        return c;
    }
  }

  Path _ridge(Size s, double base, double amp, int peaks, math.Random r, {bool sharp = false}) {
    final p = Path()..moveTo(0, s.height);
    p.lineTo(0, base);
    final step = s.width / peaks;
    for (var i = 0; i < peaks; i++) {
      final x0 = i * step;
      final top = base - amp * (0.5 + r.nextDouble() * 0.6);
      if (sharp) {
        p.lineTo(x0 + step * (0.4 + r.nextDouble() * 0.2), top);
        p.lineTo(x0 + step, base - amp * 0.15 * r.nextDouble());
      } else {
        p.quadraticBezierTo(x0 + step / 2, top, x0 + step, base - amp * 0.2 * r.nextDouble());
      }
    }
    p.lineTo(s.width, s.height);
    p.close();
    return p;
  }

  void _house(Canvas c, double x, double y, double w, Paint p) {
    c.drawPath(
        Path()
          ..moveTo(x, y)
          ..lineTo(x, y - w * 0.8)
          ..lineTo(x + w / 2, y - w * 1.35)
          ..lineTo(x + w, y - w * 0.8)
          ..lineTo(x + w, y)
          ..close(),
        p);
  }

  void _pine(Canvas c, double x, double y, double h, Paint p) {
    c.drawPath(
        Path()
          ..moveTo(x - h * 0.28, y)
          ..lineTo(x, y - h)
          ..lineTo(x + h * 0.28, y)
          ..close(),
        p);
  }

  void _tower(Canvas c, double x, double y, double w, double h, Paint p) {
    c.drawRect(Rect.fromLTWH(x, y - h, w, h), p);
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(x + i * w / 2.5, y - h - w * 0.25, w / 5, w * 0.25), p);
    }
  }

  @override
  void paint(Canvas c, Size s) {
    final r = math.Random(seed);
    final rect = Offset.zero & s;
    final sky = _skies[time]!;
    c.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky).createShader(rect));
    final night = time == 'notte';
    // stelle, sole o luna
    if (night) {
      final sp = Paint()..color = Colors.white.withValues(alpha: 0.7);
      for (var i = 0; i < 60; i++) {
        c.drawCircle(Offset(r.nextDouble() * s.width, r.nextDouble() * s.height * 0.55), 0.5 + r.nextDouble() * 0.9, sp);
      }
      c.drawCircle(Offset(s.width * 0.74, s.height * 0.22), s.height * 0.07, Paint()..color = const Color(0xFFF4EBCB));
    } else {
      final y = time == 'giorno' ? 0.2 : 0.42;
      final sun = Offset(s.width * 0.72, s.height * y);
      c.drawCircle(sun, s.height * 0.22, Paint()..color = const Color(0xFFFFF2D6).withValues(alpha: 0.35));
      c.drawCircle(sun, s.height * 0.1, Paint()..color = const Color(0xFFFFF4DC).withValues(alpha: 0.95));
    }
    // nuvole
    if (!night) {
      final cp = Paint()..color = Colors.white.withValues(alpha: time == 'giorno' ? 0.75 : 0.4);
      for (var i = 0; i < 3; i++) {
        final cx = r.nextDouble() * s.width, cy = s.height * (0.12 + r.nextDouble() * 0.2), w = 40 + r.nextDouble() * 50;
        c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: w, height: w * 0.32), cp);
        c.drawOval(Rect.fromCenter(center: Offset(cx + w * 0.25, cy - 6), width: w * 0.6, height: w * 0.3), cp);
      }
    }
    final h = s.height;
    // palette del terreno per ambientazione
    var far = const Color(0xFF9AA6B4), mid = const Color(0xFF6E8A6A), near = const Color(0xFF4A6A4A), ink = const Color(0xFF2E2620);
    switch (setting) {
      case 'deserto':
        far = const Color(0xFFD9B98A);
        mid = const Color(0xFFD7A766);
        near = const Color(0xFFC08A4A);
      case 'neve':
        far = const Color(0xFFC9D3E0);
        mid = const Color(0xFFE6ECF2);
        near = const Color(0xFFF6F8FA);
      case 'palude':
        mid = const Color(0xFF5E6B4A);
        near = const Color(0xFF3E4A34);
      case 'grotta':
      case 'rovine':
        mid = const Color(0xFF8A8270);
        near = const Color(0xFF6A6252);
      default:
        break;
    }
    far = _t(far);
    mid = _t(mid);
    near = _t(near);
    ink = _t(ink);
    final pInk = Paint()..color = ink;

    if (setting == 'cielo') {
      // isola sospesa tra le nuvole
      final isl = Path()
        ..moveTo(s.width * 0.25, h * 0.55)
        ..lineTo(s.width * 0.75, h * 0.55)
        ..lineTo(s.width * 0.55, h * 0.8)
        ..lineTo(s.width * 0.45, h * 0.78)
        ..close();
      c.drawPath(isl, Paint()..color = _t(const Color(0xFF7A6A58)));
      c.drawRect(Rect.fromLTWH(s.width * 0.25, h * 0.52, s.width * 0.5, h * 0.04), Paint()..color = mid);
      _tower(c, s.width * 0.46, h * 0.53, 18, 50, pInk);
      final cl = Paint()..color = Colors.white.withValues(alpha: night ? 0.25 : 0.85);
      for (var i = 0; i < 7; i++) {
        c.drawOval(Rect.fromCenter(center: Offset(i * s.width / 6, h * 0.92), width: 120, height: 50), cl);
      }
    } else {
      // montagne lontane
      final sharpFar = setting == 'montagna' || setting == 'neve';
      c.drawPath(_ridge(s, h * (sharpFar ? 0.5 : 0.58), h * (sharpFar ? 0.32 : 0.18), sharpFar ? 4 : 5, r, sharp: true), Paint()..color = far.withValues(alpha: 0.85));
      if (setting == 'mare' || setting == 'lago') {
        final water = Rect.fromLTWH(0, h * 0.62, s.width, h * 0.38);
        c.drawRect(water, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_t(const Color(0xFF6E9AB8)), _t(const Color(0xFF3E6A8A))]).createShader(water));
        final wp = Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        for (var i = 0; i < 9; i++) {
          final y = h * (0.66 + r.nextDouble() * 0.3), x = r.nextDouble() * s.width;
          c.drawLine(Offset(x, y), Offset(x + 18 + r.nextDouble() * 20, y), wp);
        }
        if (setting == 'lago') {
          c.drawPath(_ridge(s, h * 0.9, h * 0.08, 3, r), Paint()..color = near);
        } else {
          // vela lontana
          final x = s.width * 0.3;
          c.drawPath(
              Path()
                ..moveTo(x, h * 0.66)
                ..lineTo(x + 10, h * 0.58)
                ..lineTo(x + 12, h * 0.66)
                ..close(),
              pInk);
        }
      } else {
        c.drawPath(_ridge(s, h * 0.68, h * 0.1, 3, r), Paint()..color = mid);
        // elementi sulla collina di mezzo
        final y = h * 0.66;
        switch (setting) {
          case 'villaggio':
            for (var i = 0; i < 4; i++) {
              _house(c, s.width * (0.36 + i * 0.07), y + (i.isOdd ? 4 : 0), 14 + r.nextDouble() * 6, pInk);
            }
          case 'città':
            for (var i = 0; i < 14; i++) {
              final w = 10 + r.nextDouble() * 12, hh = 18 + r.nextDouble() * 46;
              c.drawRect(Rect.fromLTWH(s.width * 0.18 + i * s.width * 0.045, y - hh, w, hh + 6), pInk);
            }
            _tower(c, s.width * 0.5, y, 16, 80, pInk);
          case 'castello':
            _tower(c, s.width * 0.42, y, 18, 60, pInk);
            _tower(c, s.width * 0.58, y, 18, 60, pInk);
            c.drawRect(Rect.fromLTWH(s.width * 0.42, y - 38, s.width * 0.16 + 18, 40), pInk);
            _tower(c, s.width * 0.5, y - 36, 14, 40, pInk);
          case 'palazzo':
          case 'accademia':
            c.drawRect(Rect.fromLTWH(s.width * 0.34, y - 34, s.width * 0.32, 36), pInk);
            c.drawArc(Rect.fromCenter(center: Offset(s.width * 0.5, y - 34), width: 44, height: 44), math.pi, math.pi, true, pInk);
            if (setting == 'accademia') {
              _tower(c, s.width * 0.3, y, 14, 64, pInk);
              _tower(c, s.width * 0.66, y, 14, 64, pInk);
            }
          case 'rovine':
            for (var i = 0; i < 6; i++) {
              final hh = 14 + r.nextDouble() * 34;
              c.drawRect(Rect.fromLTWH(s.width * (0.3 + i * 0.07), y - hh, 7, hh + 4), pInk);
            }
            c.drawRect(Rect.fromLTWH(s.width * 0.3, y - 40, s.width * 0.16, 5), pInk);
          case 'foresta':
          case 'neve':
          case 'palude':
            for (var i = 0; i < 18; i++) {
              _pine(c, r.nextDouble() * s.width, y + r.nextDouble() * 10, 26 + r.nextDouble() * 22, Paint()..color = Color.lerp(ink, mid, 0.3)!);
            }
          default:
            break;
        }
        c.drawPath(_ridge(s, h * 0.8, h * 0.08, 2, r), Paint()..color = near);
        if (setting == 'foresta' || setting == 'montagna' || setting == 'pianura' || setting == 'villaggio') {
          for (var i = 0; i < (setting == 'foresta' ? 10 : 4); i++) {
            final x = r.nextBool() ? r.nextDouble() * s.width * 0.25 : s.width * (0.75 + r.nextDouble() * 0.25);
            _pine(c, x, h * (0.86 + r.nextDouble() * 0.08), 34 + r.nextDouble() * 20, Paint()..color = Color.lerp(ink, near, 0.25)!);
          }
        }
        if (setting == 'grotta') {
          // arco di roccia in primo piano
          final arc = Path()
            ..addRect(rect)
            ..addOval(Rect.fromCenter(center: Offset(s.width / 2, h * 0.75), width: s.width * 0.8, height: h * 1.1));
          arc.fillType = PathFillType.evenOdd;
          c.drawPath(arc, Paint()..color = _t(const Color(0xFF3A3028)));
        }
      }
    }
    if (fade) {
      c.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xC01C1714)], stops: [0, 0.5, 1])
                .createShader(rect));
    }
  }

  @override
  bool shouldRepaint(_LandscapePainter old) => old.setting != setting || old.time != time || old.seed != seed;
}

/// Percorso del luogo: "Dicathen › Regno di Sapin › Ashber".
List<WikiEntry> placePath(Wiki w, WikiEntry e, int limit) {
  final out = <WikiEntry>[e];
  var cur = e;
  for (var i = 0; i < 4; i++) {
    final inside = cur.extraAt('inside', limit);
    if (inside is! String) break;
    final up = w.find(inside, type: 'luogo') ?? w.find(inside);
    if (up == null || out.contains(up)) {
      out.insert(0, WikiEntry(id: '', name: inside, type: 'luogo'));
      break;
    }
    out.insert(0, up);
    cur = up;
  }
  return out;
}

// ======================================================================
// Termini: tre stili secondo la categoria
// ======================================================================

/// 'grimorio' per le magie, 'schedario' per le organizzazioni, 'dizionario' per il resto.
String termStyle(Wiki w, WikiEntry e, int limit) {
  final cat = (e.extraAt('category', limit) as String?) ?? '';
  if (cat == 'magia') return 'grimorio';
  if (cat == 'organizzazione') return 'schedario';
  if (cat.isEmpty) {
    if (w.groupsAt(limit).keys.any((g) => g.toLowerCase() == e.name.toLowerCase())) return 'schedario';
    final t = '${e.roleAt(limit)} ${e.name}'.toLowerCase();
    if (['magi', 'incantes', 'mana', 'potere', 'tecnica', 'sigillo', 'elemento'].any(t.contains)) return 'grimorio';
    if (['gruppo', 'squadra', 'gilda', 'casata', 'ordine', 'esercito', 'organizz', 'clan', 'famiglia'].any(t.contains)) return 'schedario';
  }
  return 'dizionario';
}

String termCategory(WikiEntry e, int limit, String style) {
  final cat = e.extraAt('category', limit) as String?;
  if (cat != null && cat.isNotEmpty) return cat;
  return style == 'grimorio' ? 'magia' : (style == 'schedario' ? 'organizzazione' : 'termine');
}

IconData categoryIcon(String cat) => switch (cat) {
      'organizzazione' => Icons.shield_outlined,
      'magia' => Icons.local_fire_department_outlined,
      'oggetto' => Icons.diamond_outlined,
      'razza' => Icons.pets_outlined,
      'titolo' => Icons.workspace_premium_outlined,
      _ => Icons.auto_stories_outlined,
    };

Color categoryColor(String cat) => switch (cat) {
      'organizzazione' => const Color(0xFF2F4A6A),
      'magia' => const Color(0xFF7A1E2E),
      'oggetto' => const Color(0xFF8A6A1E),
      'razza' => const Color(0xFF3E6B4A),
      'titolo' => const Color(0xFF5A3A6A),
      _ => const Color(0xFF6B5A4A),
    };

/// Sigillo magico dorato, diverso per ogni termine.
class Sigil extends StatelessWidget {
  final int seed;
  final double size;
  const Sigil({super.key, required this.seed, this.size = 70});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _SigilPainter(seed)));
}

class _SigilPainter extends CustomPainter {
  final int seed;
  _SigilPainter(this.seed);
  @override
  void paint(Canvas c, Size s) {
    final r = math.Random(seed);
    final cx = s.width / 2, cy = s.height / 2, R = s.width / 2 - 2;
    final gold = Paint()
      ..color = const Color(0xFFD9B65E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    c.drawCircle(Offset(cx, cy), R, gold);
    final inner = R * 0.72;
    for (double a = 0; a < 2 * math.pi; a += 0.18) {
      c.drawLine(Offset(cx + math.cos(a) * inner, cy + math.sin(a) * inner), Offset(cx + math.cos(a + 0.07) * inner, cy + math.sin(a + 0.07) * inner), gold..strokeWidth = 0.8);
    }
    final n = 4 + r.nextInt(5);
    final star = Path();
    for (var i = 0; i < n * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / n;
      final rr = i.isEven ? R * 0.86 : R * (0.28 + r.nextDouble() * 0.12);
      final p = Offset(cx + math.cos(a) * rr, cy + math.sin(a) * rr);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    c.drawPath(
        star,
        Paint()
          ..color = const Color(0xFFE8C977)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3);
    if (r.nextBool()) {
      c.drawCircle(Offset(cx, cy), R * 0.42, gold..strokeWidth = 0.9);
    }
    c.drawCircle(Offset(cx, cy), R * 0.12, Paint()..color = const Color(0xFFE8C977));
  }

  @override
  bool shouldRepaint(_SigilPainter old) => old.seed != seed;
}

const grimoireGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A2820), Color(0xFF22160F)]);
const grimoireGold = Color(0xFFB8964A);

/// Voci collegate citate nel testo ("Vedi anche").
List<WikiEntry> seeAlso(Wiki w, WikiEntry e, String text, int limit) {
  final t = text.toLowerCase();
  final out = <WikiEntry>[];
  for (final o in w.entries.values) {
    if (o.id == e.id || !o.visibleAt(limit) || o.name.length < 3) continue;
    if ([o.name, ...o.aliases.where((a) => a.length >= 4)].any((n) => t.contains(n.toLowerCase()))) out.add(o);
    if (out.length >= 6) break;
  }
  return out;
}

TextStyle dictTitle(double size) => LK.display(size);
