import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/book.dart';
import '../theme.dart';

/// Stili della carta da condividere.
const quoteStyles = ['Pergamena', 'Notte', 'Bordeaux'];

/// Anteprima della citazione e condivisione come immagine.
Future<void> showQuoteShare(BuildContext context, {required Book book, required String text, String? note, String? chapter}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: LK.paper,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _QuoteShare(book: book, text: text, note: note, chapter: chapter),
  );
}

class _QuoteShare extends StatefulWidget {
  final Book book;
  final String text;
  final String? note, chapter;
  const _QuoteShare({required this.book, required this.text, this.note, this.chapter});
  @override
  State<_QuoteShare> createState() => _QuoteShareState();
}

class _QuoteShareState extends State<_QuoteShare> {
  final _key = GlobalKey();
  int _style = 0;
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'citazione_${DateTime.now().millisecondsSinceEpoch}.png'));
      await f.writeAsBytes(data!.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: '«${widget.text}» — ${widget.book.title}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Non riesco a creare l\'immagine: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RepaintBoundary(key: _key, child: QuoteCard(book: widget.book, text: widget.text, chapter: widget.chapter, style: _style)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < quoteStyles.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(quoteStyles[i], style: LK.body(13)),
                  selected: _style == i,
                  selectedColor: LK.accentSoft,
                  onSelected: (_) => setState(() => _style = i),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: LK.accent),
              onPressed: _busy ? null : _share,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.ios_share),
              label: Text('CONDIVIDI COME IMMAGINE', style: LK.label(12, color: LK.onAccent, spacing: 1.2)),
            ),
          ),
        ]),
      ),
    );
  }
}

class QuoteCard extends StatelessWidget {
  final Book book;
  final String text;
  final String? chapter;
  final int style;
  const QuoteCard({super.key, required this.book, required this.text, this.chapter, this.style = 0});

  @override
  Widget build(BuildContext context) {
    final (bg, ink, accent, border) = switch (style) {
      1 => (const Color(0xFF1C1714), const Color(0xFFEFE4D2), const Color(0xFFE2B84B), const Color(0xFF4A3F36)),
      2 => (const Color(0xFF6E1B2A), const Color(0xFFF6EEDC), const Color(0xFFE8C977), const Color(0xFF9A4A55)),
      _ => (const Color(0xFFF3E6C4), const Color(0xFF33281A), const Color(0xFF8A3524), const Color(0xFFD9C48F)),
    };
    final size = text.length > 380 ? 15.0 : (text.length > 200 ? 17.0 : 20.0);
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          image: style == 0 ? const DecorationImage(image: AssetImage('assets/textures/parchment.png'), repeat: ImageRepeat.repeat, opacity: 0.9, scale: 2) : null,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          decoration: BoxDecoration(border: Border.all(color: border, width: 1.2), borderRadius: BorderRadius.circular(3)),
          child: Column(children: [
            Text('✦', style: TextStyle(color: accent, fontSize: 16)),
            const Spacer(),
            Text('“', style: LK.display(58, color: accent).copyWith(height: 0.7)),
            const SizedBox(height: 4),
            Text(text,
                textAlign: TextAlign.center,
                maxLines: 14,
                overflow: TextOverflow.ellipsis,
                style: LK.body(size, color: ink, style: FontStyle.italic, height: 1.5)),
            const Spacer(),
            Container(width: 40, height: 1, color: accent),
            const SizedBox(height: 10),
            Text(book.title, textAlign: TextAlign.center, maxLines: 2, style: LK.display(15, color: ink)),
            if (book.author.isNotEmpty) Text(book.author, textAlign: TextAlign.center, style: LK.body(12, color: ink.withValues(alpha: 0.75), style: FontStyle.italic)),
            if (chapter != null && chapter!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(chapter!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.label(8.5, color: ink.withValues(alpha: 0.6), spacing: 1)),
            ],
            const SizedBox(height: 10),
            Text('LOREKEEPER', style: LK.label(8, color: accent, spacing: 2.4)),
          ]),
        ),
      ),
    );
  }
}
