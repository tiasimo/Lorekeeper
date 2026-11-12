import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme.dart';
import 'adaptive.dart';
import 'lk_icons.dart';

export 'lk_icons.dart';

class NavItem {
  final LKGlyph icon;
  final String label;
  final VoidCallback onTap;
  const NavItem(this.icon, this.label, this.onTap);
}

/// Barra di navigazione flottante color mattone.
class FloatingNav extends StatelessWidget {
  final List<NavItem> items;
  final int selected;
  const FloatingNav({super.key, required this.items, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: LK.accent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x477A2F1F), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
              child: Tooltip(
                message: items[i].label,
                child: Material(
                  color: i == selected ? LK.paper : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: items[i].onTap,
                    child: SizedBox(
                      width: 54,
                      height: 46,
                      child: Center(child: LKIcon(items[i].icon, color: i == selected ? LK.accent : LK.paper, size: 23)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BackLink extends StatelessWidget {
  final String? trail;
  const BackLink({super.key, this.trail});
  @override
  Widget build(BuildContext context) {
    final pane = EmbeddedPane.of(context);
    return InkWell(
      onTap: pane?.onClose ?? () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(pane != null ? Icons.close : Icons.chevron_left, size: 18, color: LK.accent),
          Text(pane != null ? ' CHIUDI' : 'TORNA', style: LK.label(11, color: LK.accent, spacing: 1.4)),
          if (trail != null && pane == null) Text('  ·  $trail', style: LK.label(11, color: LK.muted, spacing: 0.4)),
        ]),
      ),
    );
  }
}

class Chip2 extends StatelessWidget {
  final String text;
  const Chip2(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: LK.accent, borderRadius: BorderRadius.circular(6)),
        child: Text(text.toUpperCase(), style: LK.label(10, color: LK.onAccent, spacing: 1.4)),
      );
}

/// Copertina del libro: immagine dell'EPUB oppure una copertina disegnata.
class BookCover extends StatelessWidget {
  final Book book;
  final double width;
  final double height;
  const BookCover({super.key, required this.book, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(5);
    Widget child;
    if (book.coverPath != null && File(book.coverPath!).existsSync()) {
      child = Image.file(File(book.coverPath!), width: width, height: height, fit: BoxFit.cover);
    } else {
      final c = Color(book.spineColor);
      final t = Color(book.spineTextColor);
      child = Container(
        width: width,
        height: height,
        color: c,
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: t, width: 1)),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(6),
          child: Text(book.title, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: LK.display(width * 0.13, color: t)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(borderRadius: r, boxShadow: const [BoxShadow(color: Color(0x40501E14), blurRadius: 18, offset: Offset(0, 8))]),
      child: ClipRRect(borderRadius: r, child: child),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(), style: LK.label(10, spacing: 1.8)),
      );
}

class Segmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const Segmented({super.key, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: LK.accent, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: i == selected ? LK.accentDark : Colors.transparent, borderRadius: BorderRadius.circular(7)),
                child: Text(labels[i].toUpperCase(), style: LK.label(11, color: i == selected ? Colors.white : LK.navOff, spacing: 1.2)),
              ),
            ),
        ]),
      );
}

/// Il libro "esce dallo scaffale": il dorso si sfila, ruota sul bordo e diventa la copertina.
/// Chiudendo la scheda fa il gesto al contrario e torna al suo posto.
Widget bookHero(Book b, Widget cover) => Hero(
      tag: 'book-${b.id}',
      flightShuttleBuilder: (ctx, anim, dir, fromCtx, toCtx) {
        final push = dir == HeroFlightDirection.push;
        final coverHero = (push ? toCtx.widget : fromCtx.widget) as Hero;
        final spineHero = (push ? fromCtx.widget : toCtx.widget) as Hero;
        return AnimatedBuilder(
          animation: anim,
          builder: (context, _) {
            final v = anim.value; // 0 = sullo scaffale, 1 = copertina aperta
            // prima si sfila (leggero sollevamento), poi ruota mostrando la copertina
            final turn = Curves.easeInOutCubic.transform(((v - 0.15) / 0.85).clamp(0.0, 1.0));
            final lift = math.sin(v * math.pi) * 18;
            final showCover = turn > 0.45;
            final angle = showCover ? (1 - turn) * (math.pi / 2) : -turn * (math.pi / 2);
            return Transform.translate(
              offset: Offset(0, -lift),
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0016)
                  ..rotateY(angle),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18 + 0.2 * math.sin(v * math.pi)), blurRadius: 22, offset: const Offset(6, 10))],
                  ),
                  child: showCover ? coverHero.child : FittedBox(fit: BoxFit.fill, child: spineHero.child),
                ),
              ),
            );
          },
        );
      },
      child: cover,
    );

/// Apertura del libro con animazione lenta, per vedere il gesto.
Route<T> bookRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 1100),
      reverseTransitionDuration: const Duration(milliseconds: 950),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: const Interval(0.35, 1, curve: Curves.easeOut)),
        child: child,
      ),
    );

/// SafeArea che su tablet centra il contenuto con una larghezza comoda da leggere.
class TabletSafeArea extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const TabletSafeArea({super.key, required this.child, this.maxWidth = 760});
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child)),
      );
}
