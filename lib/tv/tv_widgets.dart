import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/anime_store.dart';
import '../widgets/manga_image.dart';

/// Colori della versione TV: nero, argento e l'arancione dell'app ("menu di un DVD").
class TV {
  static const bg = Color(0xFF0A0A0B);
  static const bgDeep = Color(0xFF050506);
  static const panel = Color(0xFF17181C);
  static const panelHi = Color(0xFF26272C);
  static const ink = Color(0xFFF3F4F5);
  static const soft = Color(0xFFC9CDD2);
  static const muted = Color(0xFFB4B8BD);
  static const line = Color(0xFF5A5E66);
  static const accent = Color(0xFFE0703F);
  static const peach = Color(0xFFF0A27A);
  static const gold = Color(0xFFE2B95C);
}

/// Titoli in maiuscolo stretto, da copertina di film.
TextStyle tvDisplay(double size, {Color color = TV.ink, FontStyle? style, FontWeight weight = FontWeight.w600, double spacing = 1}) =>
    GoogleFonts.oswald(fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing, height: 1.05, fontStyle: style);
TextStyle tvBody(double size, {Color color = TV.soft, FontWeight weight = FontWeight.w500}) => GoogleFonts.inter(fontSize: size, color: color, fontWeight: weight, height: 1.4);
TextStyle tvLabel(double size, {Color color = TV.muted, double spacing = 1.6}) => GoogleFonts.oswald(fontSize: size, color: color, fontWeight: FontWeight.w500, letterSpacing: spacing);

/// Numeri a cifre fisse, come il contatore di un lettore.
TextStyle tvMono(double size, {Color color = TV.soft, FontWeight weight = FontWeight.w500}) => GoogleFonts.jetBrainsMono(fontSize: size, color: color, fontWeight: weight);

/// Le schermate TV sono disegnate su una tela fissa di 1280×720 e poi adattate allo schermo:
/// così hanno le stesse proporzioni su ogni televisore (anche sul Chromecast, che ha uno
/// schermo "logico" più piccolo).
class TvCanvas extends StatelessWidget {
  final Widget child;
  final Color? color;
  const TvCanvas({super.key, required this.child, this.color = TV.bg});

  static const size = Size(1280, 720);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final canvas = FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: MediaQuery(data: mq.copyWith(size: size, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero, viewInsets: EdgeInsets.zero), child: child),
      ),
    );
    return color == null ? canvas : ColoredBox(color: color!, child: canvas);
  }
}

/// Un elemento che si seleziona con il telecomando. A fuoco prende il bordo arancione
/// (oppure si ridisegna da solo con [builder]); OK lo apre, OK tenuto premuto chiama [onLongSelect].
class TvFocus extends StatefulWidget {
  final Widget? child;
  final Widget Function(BuildContext context, bool focused)? builder;
  final VoidCallback? onSelect, onLongSelect;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;
  final double scale;
  final BorderRadius radius;
  final FocusNode? focusNode;
  const TvFocus({
    super.key,
    this.child,
    this.builder,
    this.onSelect,
    this.onLongSelect,
    this.onFocus,
    this.autofocus = false,
    this.scale = 1,
    this.radius = BorderRadius.zero,
    this.focusNode,
  }) : assert(child != null || builder != null);

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  bool _focused = false, _long = false;
  DateTime? _downAt;

  static final _ok = {LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.gameButtonA};

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (!_ok.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (widget.onLongSelect == null) {
      if (e is KeyDownEvent) widget.onSelect?.call();
      return KeyEventResult.handled;
    }
    // con la pressione lunga: OK breve al rilascio, OK tenuto dopo mezzo secondo
    if (e is KeyDownEvent) {
      _downAt = DateTime.now();
      _long = false;
    } else if (e is KeyRepeatEvent) {
      if (!_long && _downAt != null && DateTime.now().difference(_downAt!) > const Duration(milliseconds: 550)) {
        _long = true;
        widget.onLongSelect!();
      }
    } else if (e is KeyUpEvent) {
      if (!_long && _downAt != null) widget.onSelect?.call();
      _downAt = null;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = widget.builder != null
        ? widget.builder!(context, _focused)
        : AnimatedScale(
            scale: _focused ? widget.scale : 1,
            duration: const Duration(milliseconds: 120),
            child: DecoratedBox(
              // l'ultimo dell'elenco si disegna sopra: anello arancione, poi un filo di nero attorno all'elemento
              decoration: BoxDecoration(
                borderRadius: widget.radius,
                boxShadow: _focused ? const [BoxShadow(color: TV.accent, spreadRadius: 6), BoxShadow(color: TV.bg, spreadRadius: 3)] : const [],
              ),
              child: widget.child,
            ),
          );
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      onFocusChange: (v) {
        if (!mounted) return;
        setState(() => _focused = v);
        widget.onFocus?.call(v);
        if (v) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      },
      child: GestureDetector(onTap: widget.onSelect, onLongPress: widget.onLongSelect, child: body),
    );
  }
}

/// Pulsante rettangolare della TV.
class TvButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onSelect;
  final bool primary, autofocus;
  const TvButton({super.key, required this.label, required this.onSelect, this.icon, this.primary = false, this.autofocus = false});

  @override
  Widget build(BuildContext context) => TvFocus(
        autofocus: autofocus,
        onSelect: onSelect,
        builder: (context, focused) {
          final bg = focused ? TV.accent : (primary ? TV.ink : Colors.transparent);
          final fg = focused || primary ? TV.bg : TV.ink;
          return Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(color: bg, border: Border.all(color: focused ? TV.accent : (primary ? TV.ink : const Color(0xFF8C9198)), width: 2)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, color: fg, size: 19), const SizedBox(width: 8)],
              Text(label.toUpperCase(), style: tvDisplay(17, color: fg, weight: FontWeight.w500, spacing: 1.8)),
            ]),
          );
        },
      );
}

/// Voce di un menu del disco: testo grande, piena d'arancione quando è a fuoco.
class TvMenuItem extends StatelessWidget {
  final String label;
  final String? trailing;
  final VoidCallback? onSelect;
  final ValueChanged<bool>? onFocus;
  final bool autofocus, active;
  final double height, size;
  final FocusNode? focusNode;
  const TvMenuItem({super.key, required this.label, this.trailing, this.onSelect, this.onFocus, this.autofocus = false, this.active = false, this.height = 44, this.size = 20, this.focusNode});

  @override
  Widget build(BuildContext context) => TvFocus(
        focusNode: focusNode,
        autofocus: autofocus,
        onSelect: onSelect,
        onFocus: onFocus,
        builder: (context, focused) {
          final fg = focused ? TV.bg : (active ? TV.peach : TV.ink);
          return Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: focused ? TV.accent : (active ? TV.panelHi : Colors.transparent),
            child: Row(children: [
              SizedBox(width: 26, child: focused || active ? Icon(Icons.play_arrow, size: 20, color: fg) : null),
              Expanded(child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: tvDisplay(size, color: fg, weight: focused ? FontWeight.w600 : FontWeight.w500, spacing: 2))),
              if (trailing != null) Text(trailing!, style: tvMono(13, color: fg, weight: FontWeight.w700)),
            ]),
          );
        },
      );
}

/// Come si presenta una custodia: ogni sezione ha la sua.
enum DvdStyle { bluray, white, steel }

DvdStyle dvdStyleFor(SavedAnime a) => switch (a.section) { 0 => DvdStyle.bluray, 1 => DvdStyle.white, _ => DvdStyle.steel };

/// Una custodia vista di fronte, con la copertina dell'anime.
class DvdCase extends StatelessWidget {
  final SavedAnime anime;
  final double width;
  final DvdStyle style;
  final String? badge;
  final bool badgeLight, dim;
  const DvdCase({super.key, required this.anime, this.width = 122, this.style = DvdStyle.bluray, this.badge, this.badgeLight = false, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final a = anime;
    final h = width * 1.42;
    final tint = a.caseColor == null ? const Color(0xFF3A3C42) : Color(a.caseColor!);
    final Widget art = (a.cover ?? '').isEmpty
        ? Container(
            color: tint,
            alignment: Alignment.bottomLeft,
            padding: EdgeInsets.all(width * 0.07),
            child: Text(a.title.toUpperCase(), maxLines: 4, overflow: TextOverflow.ellipsis, style: tvDisplay(width * 0.11, weight: FontWeight.w700, spacing: 0.6)),
          )
        : MangaImage(a.cover!, sourceId: a.sourceId, managerId: a.managerId, tint: a.caseColor == null ? null : Color(a.caseColor!));
    final cover = Stack(fit: StackFit.expand, children: [
      art,
      if (dim) const ColoredBox(color: Color(0x8C0A0A0B)),
      if (style == DvdStyle.steel) ...[
        // riflesso del metallo e piega del dorso
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment(-1, -0.6), end: Alignment(1, 0.6), colors: [Color(0x00FFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)], stops: [0.3, 0.46, 0.6]),
          ),
        ),
        Positioned(left: width * 0.065, top: 0, bottom: 0, child: Container(width: 1, color: const Color(0x66FFFFFF))),
      ],
    ]);
    final Widget box = switch (style) {
      DvdStyle.bluray => Container(
          width: width,
          height: h,
          padding: const EdgeInsets.fromLTRB(3, 0, 3, 3),
          decoration: BoxDecoration(color: const Color(0xFF1D5BC2), borderRadius: BorderRadius.circular(5)),
          child: Column(children: [
            SizedBox(
              height: width * 0.12,
              child: Center(child: Text('BLU-RAY', style: GoogleFonts.inter(fontSize: width * 0.066, fontWeight: FontWeight.w700, letterSpacing: width * 0.014, color: Colors.white))),
            ),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(2), child: cover)),
          ]),
        ),
      DvdStyle.white => Container(
          width: width,
          height: h,
          padding: EdgeInsets.all(width * 0.04),
          decoration: BoxDecoration(color: TV.ink, borderRadius: BorderRadius.circular(4)),
          child: ClipRRect(borderRadius: BorderRadius.circular(2), child: cover),
        ),
      DvdStyle.steel => Container(
          width: width,
          height: h,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE6E9ED), Color(0xFF8C9198), Color(0xFFD6D9DD), Color(0xFF6E737A)], stops: [0, 0.45, 0.6, 1]),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(5), child: cover),
        ),
    };
    if (badge == null) return box;
    return Stack(clipBehavior: Clip.none, children: [
      box,
      Positioned(
        top: -9,
        right: -9,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: badgeLight ? TV.ink : TV.accent,
          child: Text(badge!, style: tvMono(11, color: TV.bg, weight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

/// La riga di aiuto del telecomando, in basso a destra.
class TvHints extends StatelessWidget {
  final List<String> hints;
  const TvHints(this.hints, {super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final h in hints) Padding(padding: const EdgeInsets.only(left: 20), child: Text(h, style: tvMono(11, color: const Color(0xFFA5AAB0)))),
      ]);
}

/// Quando esce il prossimo episodio, detto in breve ("oggi alle 17:30", "venerdì", "il 3 dicembre").
String tvWhen(DateTime d) {
  final now = DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final hm = '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  if (days <= 0) return 'oggi alle $hm';
  if (days == 1) return 'domani alle $hm';
  const week = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];
  if (days < 7) return week[d.weekday - 1];
  const months = ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'];
  return 'il ${d.day} ${months[d.month - 1]}';
}

/// I nomi delle sezioni, per lo stato nella lista.
const tvStatusNames = {
  'CURRENT': 'Sul lettore',
  'REPEATING': 'Sul lettore',
  'PAUSED': 'In pausa',
  'PLANNING': 'Prossimamente',
  'COMPLETED': 'Collezione',
  'DROPPED': 'Abbandonato',
};
