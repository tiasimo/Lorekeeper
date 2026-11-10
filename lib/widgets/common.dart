import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme.dart';

class NavItem {
  final IconData icon;
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
                      child: Icon(items[i].icon, color: i == selected ? LK.accent : LK.paper, size: 22),
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
  Widget build(BuildContext context) => InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.chevron_left, size: 18, color: LK.accent),
            Text('TORNA', style: LK.label(11, color: LK.accent, spacing: 1.4)),
            if (trail != null) Text('  ·  $trail', style: LK.label(11, color: const Color(0xFF8A7E75), spacing: 0.4)),
          ]),
        ),
      );
}

class Chip2 extends StatelessWidget {
  final String text;
  const Chip2(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: LK.accent, borderRadius: BorderRadius.circular(6)),
        child: Text(text.toUpperCase(), style: LK.label(10, color: Colors.white, spacing: 1.4)),
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
                child: Text(labels[i].toUpperCase(), style: LK.label(11, color: i == selected ? Colors.white : const Color(0xFFFBE9E2), spacing: 1.2)),
              ),
            ),
        ]),
      );
}
