import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import 'lk_icons.dart';

/// Tablet: il lato corto è almeno 600 dp.
bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).shortestSide >= 600;

/// Tablet con spazio per più colonne (di solito in orizzontale).
bool isWide(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.shortestSide >= 600 && s.width >= 900;
}

/// Una schermata mostrata dentro un pannello laterale invece che a tutto schermo:
/// il "Torna" diventa "Chiudi" e chiude il pannello.
class EmbeddedPane extends InheritedWidget {
  final VoidCallback onClose;
  const EmbeddedPane({super.key, required this.onClose, required super.child});

  static EmbeddedPane? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<EmbeddedPane>();

  @override
  bool updateShouldNotify(EmbeddedPane old) => old.onClose != onClose;
}

/// Barra di navigazione verticale per il tablet.
class SideRail extends StatelessWidget {
  final List<NavItem> items;
  final int selected;
  final int? accentIndex; // il pulsante tondo (es. "Importa")
  final Widget? bottom;
  const SideRail({super.key, required this.items, required this.selected, this.accentIndex, this.bottom});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      decoration: BoxDecoration(color: LK.dark ? LK.card : const Color(0xFFF5F0E8), border: Border(right: BorderSide(color: LK.border))),
      child: SafeArea(
        right: false,
        child: Column(children: [
          const SizedBox(height: 18),
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: LK.accent, borderRadius: BorderRadius.circular(12)),
            child: Text('L', style: LK.display(24, color: LK.onAccent)),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: i == accentIndex
                  ? Tooltip(
                      message: items[i].label,
                      child: Material(
                        color: LK.accent,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: items[i].onTap,
                          child: SizedBox(width: 54, height: 54, child: Center(child: LKIcon(items[i].icon, color: LK.onAccent, size: 24))),
                        ),
                      ),
                    )
                  : Material(
                      color: i == selected ? LK.navOff : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: items[i].onTap,
                        child: SizedBox(
                          width: 72,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Column(children: [
                              LKIcon(items[i].icon, color: i == selected ? LK.accent : LK.muted, size: 23),
                              const SizedBox(height: 4),
                              Text(items[i].label.split(' ').first.toUpperCase(),
                                  maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: LK.label(8.5, color: i == selected ? LK.accent : LK.muted, spacing: 0.5)),
                            ]),
                          ),
                        ),
                      ),
                    ),
            ),
          const Spacer(),
          if (bottom != null) bottom!,
          const SizedBox(height: 18),
        ]),
      ),
    );
  }
}

/// Selettore Novel/Manga verticale per la barra laterale.
class VerticalSwitch extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const VerticalSwitch({super.key, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: LK.line, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
              child: Material(
                color: i == selected ? LK.card : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(i),
                  child: SizedBox(
                    width: 62,
                    height: 44,
                    child: Center(child: Text(labels[i].toUpperCase(), style: LK.label(9.5, color: i == selected ? LK.accent : LK.muted, spacing: 0.6))),
                  ),
                ),
              ),
            ),
        ]),
      );
}
