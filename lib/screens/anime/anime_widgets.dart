import 'package:flutter/material.dart';

import '../../services/anime_store.dart';
import '../../theme.dart';
import '../../widgets/manga_image.dart';

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
