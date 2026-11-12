import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/anime_store.dart';
import '../../theme.dart';
import '../../widgets/manga_image.dart';
import '../../tv/tv_mode.dart';

/// Stili delle custodie.
const caseStyles = ['Blu-ray', '4K', 'Steelbook'];

/// Una custodia Blu-ray vista di fronte, con la copertina dell'anime.
class BluRayCase extends StatelessWidget {
  final SavedAnime anime;
  final double width;
  final double tilt; // leggera rotazione per dare profondità (radianti)
  final int? badge;
  const BluRayCase({super.key, required this.anime, this.width = 100, this.tilt = 0, this.badge});

  @override
  Widget build(BuildContext context) {
    final style = anime.caseStyle;
    final steel = style == 'Steelbook';
    final uhd = style == '4K';
    final tint = anime.caseColor == null ? const Color(0xFF4A4A52) : Color(anime.caseColor!);
    final frame = steel ? Color.lerp(tint, const Color(0xFF9AA0A8), 0.55)! : (uhd ? const Color(0xFF141416) : const Color(0xFF0F3E8C));
    final h = width * 1.28;
    final band = width * 0.13;
    final cover = Container(
      width: width,
      height: h,
      padding: EdgeInsets.all(width * 0.03),
      decoration: BoxDecoration(
        color: frame,
        borderRadius: BorderRadius.circular(width * 0.05),
        gradient: steel
            ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(frame, Colors.white, 0.35)!, frame, Color.lerp(frame, Colors.black, 0.25)!])
            : null,
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 6))],
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(children: [
        if (!steel)
          SizedBox(
            height: band,
            child: Center(
              child: Text(
                uhd ? '4K ULTRA HD' : 'BLU-RAY DISC',
                maxLines: 1,
                style: LK.label(width * 0.068, color: Colors.white, spacing: width * 0.012),
              ),
            ),
          ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(width * 0.025),
            child: Stack(fit: StackFit.expand, children: [
              (anime.cover ?? '').isEmpty
                  ? Container(
                      color: tint,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(6),
                      child: Text(anime.title, textAlign: TextAlign.center, maxLines: 4, style: LK.display(width * 0.12, color: Colors.white)),
                    )
                  : MangaImage(anime.cover!, sourceId: anime.sourceId, managerId: anime.managerId, tint: anime.caseColor == null ? null : Color(anime.caseColor!)),
              // riflesso della plastica
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0)],
                      stops: const [0, 0.35, 1],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
    return Stack(clipBehavior: Clip.none, children: [
      Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0018)
          ..rotateY(tilt),
        child: cover,
      ),
      if ((badge ?? 0) > 0)
        Positioned(
          top: -8,
          right: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 22),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: LK.accent, borderRadius: BorderRadius.circular(9), border: Border.all(color: LK.paper, width: 1.5)),
            child: Text(badge! > 999 ? '999+' : '$badge', textAlign: TextAlign.center, style: LK.label(9.5, color: Colors.white, spacing: 0.2)),
          ),
        ),
    ]);
  }
}

/// Il disco: la copertina ritagliata a cerchio con il foro al centro.
class BluRayDisc extends StatelessWidget {
  final SavedAnime anime;
  final double size;
  const BluRayDisc({super.key, required this.anime, this.size = 140});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, 4))]),
      child: ClipOval(
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
            child: (anime.cover ?? '').isEmpty
                ? Container(color: anime.caseColor == null ? LK.accent : Color(anime.caseColor!))
                : MangaImage(anime.cover!, sourceId: anime.sourceId, managerId: anime.managerId),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0),
                ]),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
              ),
            ),
          ),
          Container(
            width: size * 0.34,
            height: size * 0.34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFD9E3F2), border: Border.all(color: const Color(0xFFB9C8DE), width: size * 0.04)),
            alignment: Alignment.center,
            child: Container(width: size * 0.1, height: size * 0.1, decoration: BoxDecoration(shape: BoxShape.circle, color: LK.paper)),
          ),
        ]),
      ),
    );
  }
}

/// Tag dell'animazione che porta la custodia dallo scaffale alla scheda.
String caseHeroTag(SavedAnime a) => 'anime-case-${a.key}';

/// La custodia che si apre: arriva chiusa dallo scaffale, la copertina gira sul
/// dorso centrale e scopre il libretto (a sinistra) e il disco (a destra), che gira.
class OpeningCase extends StatefulWidget {
  final SavedAnime anime;
  const OpeningCase({super.key, required this.anime});
  @override
  State<OpeningCase> createState() => _OpeningCaseState();
}

class _OpeningCaseState extends State<OpeningCase> with TickerProviderStateMixin {
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void initState() {
    super.initState();
    // aspetto che la custodia arrivi dallo scaffale, poi la apro
    Future.delayed(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      _open.forward();
      if (!tvMode) _spin.repeat();
    });
  }

  @override
  void dispose() {
    _open.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anime;
    final frame = a.caseStyle == '4K' ? const Color(0xFF141416) : const Color(0xFF0F3E8C);
    return LayoutBuilder(builder: (context, c) {
      final half = (c.maxWidth - 10) / 2;
      final h = half * 1.28;
      return SizedBox(
        height: h + 10,
        child: AnimatedBuilder(
          animation: Listenable.merge([_open, _spin]),
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(_open.value);
            // la copertina viene verso chi guarda mentre si apre (come una custodia vera)
            final angle = math.pi * t;
            final showBack = t > 0.5;
            // il fondo della custodia (libretto e vassoio del disco) compare mentre si apre
            final booklet = Container(
              width: half,
              height: h,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF7F1E4), borderRadius: BorderRadius.circular(5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('LIBRETTO', style: LK.label(8, spacing: 1.4)),
                const SizedBox(height: 4),
                Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.display(15, color: const Color(0xFF2A2420)).copyWith(height: 1.15)),
                const SizedBox(height: 6),
                Expanded(child: Text(a.description ?? 'Trama non disponibile.', overflow: TextOverflow.fade, style: LK.body(11, color: const Color(0xFF5E534B), height: 1.4))),
                if (a.genres.isNotEmpty) Text(a.genres.take(3).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.label(8.5, color: const Color(0xFF6B5F57), spacing: 0.4)),
              ]),
            );
            final tray = Container(
              width: half,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A4F9E), Color(0xFF0B2F6A)]),
              ),
              child: Stack(alignment: Alignment.center, children: [
                Transform.translate(
                  // il disco si solleva un poco quando la custodia è aperta
                  offset: Offset(0, -6 * t),
                  child: Transform.rotate(
                    angle: _spin.value * 2 * math.pi * (0.15 + 0.85 * (1 - t)) + t * math.pi * 0.6,
                    child: BluRayDisc(anime: a, size: math.min(half * 0.84, h * 0.7)),
                  ),
                ),
                Positioned(bottom: 8, child: Text('${a.total} EPISODI', style: LK.label(7.5, color: Colors.white70, spacing: 1.2))),
              ]),
            );
            return Stack(clipBehavior: Clip.none, children: [
              // guscio esterno: si allarga da metà a intero
              Positioned(
                left: (half + 5) * (1 - t),
                top: 0,
                width: (half + 10) + (half) * t,
                height: h + 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: frame,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: const Color(0x47000000), blurRadius: 18, offset: Offset(0, 10 * (0.4 + 0.6 * t)))],
                  ),
                ),
              ),
              // vassoio con il disco (a destra, sotto la copertina)
              Positioned(left: half + 5, top: 5, child: tray),
              // la copertina che ruota sul dorso centrale
              Positioned(
                left: half + 5,
                top: 5,
                child: Transform(
                  alignment: Alignment.centerLeft,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(angle),
                  child: showBack
                      // dentro la copertina c'è il libretto (girato, così si legge dritto)
                      ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: booklet)
                      : Hero(tag: caseHeroTag(a), child: BluRayCase(anime: a, width: half)),
                ),
              ),
            ]);
          },
        ),
      );
    });
  }
}
