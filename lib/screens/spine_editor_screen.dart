import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/spine.dart';

class SpineEditorScreen extends StatefulWidget {
  final Book book;
  const SpineEditorScreen({super.key, required this.book});
  @override
  State<SpineEditorScreen> createState() => _SpineEditorScreenState();
}

class _SpineEditorScreenState extends State<SpineEditorScreen> {
  late String palette = widget.book.spinePalette;
  late String style = widget.book.spineStyle;
  late double height = widget.book.spineHeight;
  late double width = widget.book.spineWidth;
  late final TextEditingController _title = TextEditingController(text: widget.book.title);

  (int, int) get colors {
    if (palette == 'cover') return (widget.book.coverSpineColor, widget.book.coverSpineTextColor);
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
      ..spineTextColor = tx;
    if (_title.text.trim().isNotEmpty) b.title = _title.text.trim();
    LibraryStore.I.updateBook(b);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Widget _chip(String label, int bg, int tx, bool on, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? LK.accent : const Color(0xFFE6DED3), width: on ? 2 : 1),
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
          const Divider(height: 1, color: LK.line),
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
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE6DED3))),
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
                  ],
                ),
                const SizedBox(height: 6),
                Text('"Dalla copertina" usa i colori dominanti dell\'EPUB.', style: LK.body(12, color: LK.muted, style: FontStyle.italic)),
                const SizedBox(height: 20),
                const SectionLabel('Stile del dorso'),
                Row(children: [
                  for (final s in SpinePalette.styles)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => style = s),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: style == s ? LK.accent : const Color(0xFFE6DED3), width: style == s ? 2 : 1),
                            ),
                            child: Column(children: [
                              SpineView(title: '', color: Color(bg), textColor: Color(tx), style: s, baseHeight: 64),
                              const SizedBox(height: 6),
                              Text(s, style: LK.body(11)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 20),
                const SectionLabel('Dimensioni'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.line)),
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
