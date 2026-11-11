import 'package:flutter/material.dart';

import '../services/gemini.dart';
import '../services/library_store.dart';
import '../theme.dart';

/// Pannello che si apre tenendo premuta una parola: significato o traduzione con Gemini.
Future<void> showWordSheet(BuildContext context, {required String word, required String sentence, required String bookTitle}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: LK.paper,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _WordSheet(word: word, sentence: sentence, bookTitle: bookTitle),
  );
}

class _WordSheet extends StatefulWidget {
  final String word, sentence, bookTitle;
  const _WordSheet({required this.word, required this.sentence, required this.bookTitle});
  @override
  State<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<_WordSheet> {
  int _mode = 0; // 0 significato, 1 traduzione
  final Map<int, String> _results = {};
  final Map<int, String> _errors = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_results.containsKey(_mode)) return;
    setState(() => _loading = true);
    final lang = LibraryStore.I.app.language;
    final prompt = _mode == 0
        ? 'Sei un dizionario per un lettore di romanzi. Spiega in italiano, in massimo 3 frasi brevi, il significato di «${widget.word}» '
            'come è usato in questo passo del libro «${widget.bookTitle}»:\n«${widget.sentence}»\n'
            'Se è un nome proprio o un termine inventato dell\'opera, dillo e spiega cosa sembra indicare solo in base al passo, senza anticipare eventi futuri. '
            'Non usare markdown.'
        : 'Traduci in $lang «${widget.word}» come è usato in questo passo:\n«${widget.sentence}»\n'
            'Rispondi con la traduzione sulla prima riga e una breve nota d\'uso sulla seconda. Non usare markdown.';
    try {
      final r = await Gemini.ask(prompt, maxTokens: 300);
      _results[_mode] = r;
    } catch (e) {
      _errors[_mode] = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final lang = LibraryStore.I.app.language;
    final text = _results[_mode];
    final err = _errors[_mode];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.word, style: LK.display(26)),
          const SizedBox(height: 12),
          Row(children: [
            for (final (i, l) in [(0, 'Significato'), (1, 'Traduci in $lang')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(l),
                  selected: _mode == i,
                  selectedColor: LK.accent,
                  labelStyle: LK.body(13, color: _mode == i ? LK.onAccent : LK.ink),
                  onSelected: (_) {
                    setState(() => _mode = i);
                    _run();
                  },
                ),
              ),
          ]),
          const SizedBox(height: 16),
          if (_loading && text == null)
            Padding(padding: const EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: LK.accent)))
          else if (err != null && text == null)
            Text(err, style: LK.body(14, color: LK.accent))
          else
            Text(text ?? '', style: LK.body(16, height: 1.5)),
        ]),
      ),
    );
  }
}
