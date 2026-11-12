import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'tv_mode.dart';

/// Tastiera a schermo per la TV, comandata con il telecomando (la tastiera di
/// sistema delle TV non sempre funziona bene con l'app). Indietro la chiude e basta.
Future<String?> showTvKeyboard(BuildContext context, {String initial = '', String title = '', bool url = false}) {
  return showDialog<String>(
    context: context,
    barrierColor: const Color(0xCC000000),
    builder: (_) => _TvKeyboard(initial: initial, title: title, url: url),
  );
}

class _TvKeyboard extends StatefulWidget {
  final String initial, title;
  final bool url;
  const _TvKeyboard({required this.initial, required this.title, required this.url});
  @override
  State<_TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<_TvKeyboard> {
  late String _text = widget.initial;
  bool _upper = false;

  static const _rows = ['1234567890', 'qwertyuiop', 'asdfghjkl\'', 'zxcvbnm,.-'];
  static const _urlKeys = ['https://', '/', ':', '.com', '.json', '_', '?', '=', '&', '@'];

  void _type(String s) => setState(() => _text += _upper && s.length == 1 ? s.toUpperCase() : s);
  void _back() => setState(() => _text = _text.isEmpty ? '' : _text.substring(0, _text.length - 1));

  // tastiera fisica o telecomando con tasti numerici
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32 && e.logicalKey != LogicalKeyboardKey.select && e.logicalKey != LogicalKeyboardKey.enter) {
      setState(() => _text += ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _key(String label, VoidCallback onTap, {double width = 54, bool accent = false, bool autofocus = false, IconData? icon}) => Padding(
        padding: const EdgeInsets.all(3),
        child: SizedBox(
          width: width,
          height: 48,
          child: TextButton(
            autofocus: autofocus,
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(accent ? LK.accent : const Color(0x1FF3E7CF)),
              foregroundColor: const WidgetStatePropertyAll(Color(0xFFF3E7CF)),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused) ? const BorderSide(color: Color(0xFFE0703F), width: 3) : BorderSide.none),
              overlayColor: const WidgetStatePropertyAll(Color(0x33E0703F)),
            ),
            onPressed: onTap,
            child: icon != null ? Icon(icon, size: 22) : Text(label, style: LK.label(label.length > 3 ? 12 : 17, color: const Color(0xFFF3E7CF), spacing: 0.3)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF241D19),
      insetPadding: const EdgeInsets.symmetric(horizontal: 120, vertical: 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Focus(
        onKeyEvent: _onKey,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.title.isNotEmpty) Text(widget.title, style: LK.display(20, color: const Color(0xFFF3E7CF))),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(color: const Color(0x14F3E7CF), borderRadius: BorderRadius.circular(12)),
              child: Text(_text.isEmpty ? ' ' : '$_text▏', maxLines: 2, overflow: TextOverflow.ellipsis, style: LK.body(22, color: const Color(0xFFF3E7CF))),
            ),
            const SizedBox(height: 12),
            for (var r = 0; r < _rows.length; r++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < _rows[r].length; i++)
                  _key(_upper ? _rows[r][i].toUpperCase() : _rows[r][i], () => _type(_rows[r][i]), autofocus: r == 1 && i == 0),
              ]),
            if (widget.url)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final k in _urlKeys) _key(k, () => setState(() => _text += k), width: k.length > 2 ? 84 : 54),
              ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _key('', () => setState(() => _upper = !_upper), width: 70, icon: _upper ? Icons.keyboard_capslock : Icons.arrow_upward),
              _key('SPAZIO', () => setState(() => _text += ' '), width: 260),
              _key('', _back, width: 80, icon: Icons.backspace_outlined),
              _key('PULISCI', () => setState(() => _text = ''), width: 100),
              _key('OK', () => Navigator.pop(context, _text), width: 110, accent: true),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Campo di testo che sulla TV apre la tastiera a schermo; sul telefono è un TextField normale.
class TvTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool url, autofocus;
  final ValueChanged<String>? onChanged, onSubmitted;
  final InputDecoration? decoration;
  final TextStyle? style;
  const TvTextField({super.key, required this.controller, this.hint = '', this.url = false, this.autofocus = false, this.onChanged, this.onSubmitted, this.decoration, this.style});

  @override
  Widget build(BuildContext context) {
    if (!tvMode) {
      return TextField(
        controller: controller,
        autofocus: autofocus,
        style: style,
        keyboardType: url ? TextInputType.url : null,
        decoration: decoration ?? InputDecoration(hintText: hint),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => InkWell(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final v = await showTvKeyboard(context, initial: controller.text, title: hint, url: url);
          if (v == null) return;
          controller.text = v;
          onChanged?.call(v);
          onSubmitted?.call(v);
        },
        child: InputDecorator(
          decoration: (decoration ?? InputDecoration(hintText: hint)).copyWith(hintText: controller.text.isEmpty ? (decoration?.hintText ?? hint) : null),
          child: Text(controller.text, style: style ?? LK.body(15)),
        ),
      ),
    );
  }
}
