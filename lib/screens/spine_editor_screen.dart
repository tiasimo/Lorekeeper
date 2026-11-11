import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/spine.dart';

class SpineEditorScreen extends StatefulWidget {
  final Book book;
  /// Salvataggio alternativo (per i dorsi dei manga).
  final void Function(Book)? onSave;
  const SpineEditorScreen({super.key, required this.book, this.onSave});
  @override
  State<SpineEditorScreen> createState() => _SpineEditorScreenState();
}

class _SpineEditorScreenState extends State<SpineEditorScreen> {
  late String palette = widget.book.spinePalette;
  late String style = widget.book.spineStyle;
  late double height = widget.book.spineHeight;
  late double width = widget.book.spineWidth;
  late int? titleColor = widget.book.spineTitleColor;
  // colore personalizzato (tonalità, saturazione, luminosità)
  late HSLColor custom = HSLColor.fromColor(Color(widget.book.spineColor));
  late int customText = widget.book.spineTextColor;
  late final TextEditingController _title = TextEditingController(text: widget.book.title);

  (int, int) get colors {
    if (palette == 'cover') return (widget.book.coverSpineColor, widget.book.coverSpineTextColor);
    if (palette == 'custom') return (custom.toColor().toARGB32(), customText);
    final p = SpinePalette.presets.firstWhere((p) => p.name == palette, orElse: () => SpinePalette.presets.first);
    return (p.bg, p.text);
  }

  void _save() {
    final b = widget.book;
    final (bg, tx) = colors;
    b
      ..spinePalette = palette
      ..spineStyle = style
      ..spineHeight = height
      ..spineWidth = width
      ..spineColor = bg
      ..spineTextColor = tx
      ..spineTitleColor = titleColor;
    if (_title.text.trim().isNotEmpty) b.title = _title.text.trim();
    if (widget.onSave != null) {
      widget.onSave!(b);
    } else {
      LibraryStore.I.updateBook(b);
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Widget _swatch(int c, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Color(c),
            shape: BoxShape.circle,
            border: Border.all(color: on ? LK.accent : LK.border, width: on ? 3 : 1),
          ),
        ),
      );

  Widget _chip(String label, int bg, int tx, bool on, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: LK.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? LK.accent : LK.border, width: on ? 2 : 1),
          ),
          child: Row(children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: Color(bg), shape: BoxShape.circle, border: Border.all(color: Color(tx), width: 2.5)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(13))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    final (bg, tx) = colors;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              Expanded(child: Text('Modifica dorso', style: LK.display(21))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: LK.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                onPressed: _save,
                child: const Icon(Icons.save_outlined, size: 20),
              ),
            ]),
          ),
          Divider(height: 1, color: LK.line),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              children: [
                SizedBox(
                  height: 230,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    BookCover(book: b, width: 130, height: 190),
                    const SizedBox(width: 28),
                    SpineView(
                      title: _title.text.isEmpty ? b.title : _title.text,
                      color: Color(bg),
                      textColor: Color(tx),
                      titleColor: titleColor == null ? null : Color(titleColor!),
                      style: style,
                      heightScale: height,
                      widthScale: width,
                      baseHeight: 190,
                    ),
                  ]),
                ),
                const ShelfBoard(),
                const SizedBox(height: 22),
                const SectionLabel('Titolo sul dorso'),
                TextField(
                  controller: _title,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: LK.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Colori'),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.6,
                  children: [
                    _chip('Dalla copertina', b.coverSpineColor, b.coverSpineTextColor, palette == 'cover', () => setState(() => palette = 'cover')),
                    for (final p in SpinePalette.presets) _chip(p.name, p.bg, p.text, palette == p.name, () => setState(() => palette = p.name)),
                    _chip('Personalizzato', custom.toColor().toARGB32(), customText, palette == 'custom', () => setState(() => palette = 'custom')),
                  ],
                ),
                if (palette == 'custom') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.line)),
                    child: Column(children: [
                      Row(children: [
                        SizedBox(width: 90, child: Text('Tonalità', style: LK.body(14))),
                        Expanded(child: Slider(min: 0, max: 359, value: custom.hue, activeColor: HSLColor.fromAHSL(1, custom.hue, 0.7, 0.45).toColor(), onChanged: (v) => setState(() => custom = custom.withHue(v)))),
                      ]),
                      Row(children: [
                        SizedBox(width: 90, child: Text('Saturazione', style: LK.body(14))),
                        Expanded(child: Slider(min: 0, max: 1, value: custom.saturation, onChanged: (v) => setState(() => custom = custom.withSaturation(v)))),
                      ]),
                      Row(children: [
                        SizedBox(width: 90, child: Text('Luminosità', style: LK.body(14))),
                        Expanded(child: Slider(min: 0.05, max: 0.95, value: custom.lightness.clamp(0.05, 0.95), onChanged: (v) => setState(() => custom = custom.withLightness(v)))),
                      ]),
                      Row(children: [
                        SizedBox(width: 90, child: Text('Ornamenti', style: LK.body(14))),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [for (final c in SpinePalette.titleColors) _swatch(c, customText == c, () => setState(() => customText = c))]),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                const SectionLabel('Colore dei nomi sul dorso'),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => setState(() => titleColor = null),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: LK.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: titleColor == null ? LK.accent : LK.border, width: titleColor == null ? 2 : 1),
                        ),
                        child: Text('Come gli ornamenti', style: LK.body(12.5)),
                      ),
                    ),
                    for (final c in SpinePalette.titleColors) _swatch(c, titleColor == c, () => setState(() => titleColor = c)),
                  ]),
                ),
                const SizedBox(height: 6),
                Text('"Dalla copertina" usa i colori dominanti dell\'EPUB.', style: LK.body(12, color: LK.muted, style: FontStyle.italic)),
                const SizedBox(height: 20),
                const SectionLabel('Stile del dorso'),
                SizedBox(
                  height: 112,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final st in SpinePalette.styles)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => style = st),
                          child: Container(
                            width: 64,
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                            decoration: BoxDecoration(
                              color: LK.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: style == st ? LK.accent : LK.border, width: style == st ? 2 : 1),
                            ),
                            child: Column(children: [
                              SpineView(title: '', color: Color(bg), textColor: Color(tx), style: st, baseHeight: 64),
                              const SizedBox(height: 6),
                              Text(st, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(11)),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Dimensioni'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: LK.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.line)),
                  child: Column(children: [
                    Row(children: [
                      SizedBox(width: 80, child: Text('Altezza', style: LK.body(14))),
                      Expanded(child: Slider(min: 0.7, max: 1.1, value: height, onChanged: (v) => setState(() => height = v))),
                      Text('${(height * 100).round()}%', style: LK.label(11, spacing: 0)),
                    ]),
                    Row(children: [
                      SizedBox(width: 80, child: Text('Larghezza', style: LK.body(14))),
                      Expanded(child: Slider(min: 0.7, max: 1.3, value: width, onChanged: (v) => setState(() => width = v))),
                      Text('${(width * 100).round()}%', style: LK.label(11, spacing: 0)),
                    ]),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
