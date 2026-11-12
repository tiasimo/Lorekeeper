import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../services/crash_log.dart';
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
  int _logged = 0;
  static final _arrows = {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight};
  // tastiera del sistema (anche quella del telefono dall'app Google Home / Google TV)
  bool _system = false;
  late final _sysCtrl = TextEditingController();

  @override
  void dispose() {
    _sysCtrl.dispose();
    super.dispose();
  }

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
    // per capire che tasti manda il telecomando (si vede in Impostazioni → Errori recenti)
    if (e is KeyDownEvent && !_arrows.contains(e.logicalKey) && _logged++ < 6) {
      CrashLog.add('Tastiera TV: tasto ${e.logicalKey.debugName ?? e.logicalKey.keyId} (fisico ${e.physicalKey.debugName ?? e.physicalKey.usbHidUsage})');
    }
    return KeyEventResult.ignored;
  }

  Widget _key(String label, VoidCallback onTap, {double width = 54, bool accent = false, bool autofocus = false, IconData? icon}) =>
      _KbKey(label: label, onTap: onTap, width: width, accent: accent, autofocus: autofocus, icon: icon);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF241D19),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      // questo Focus serve solo ad ascoltare i tasti: non deve mai prendersi la selezione
      // (prima il cursore ci finiva sopra e "spariva")
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        // su Chromecast lo schermo "logico" è piccolo: la tastiera si rimpicciolisce per starci tutta
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.title.isNotEmpty) Text(widget.title, style: LK.display(20, color: const Color(0xFFF3E7CF))),
            const SizedBox(height: 10),
            if (_system) ...[
              SizedBox(
                width: 640,
                child: TextField(
                  controller: _sysCtrl,
                  autofocus: true,
                  keyboardType: widget.url ? TextInputType.url : TextInputType.text,
                  textInputAction: TextInputAction.done,
                  style: LK.body(22, color: const Color(0xFFF3E7CF)),
                  decoration: const InputDecoration(filled: true, fillColor: Color(0x14F3E7CF), hintText: 'Scrivi con la tastiera della TV o del telefono'),
                  onSubmitted: (v) => Navigator.pop(context, v),
                ),
              ),
              const SizedBox(height: 12),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _key('TASTIERA A SCHERMO', () => setState(() {
                      _text = _sysCtrl.text;
                      _system = false;
                    }), width: 220),
                _key('OK', () => Navigator.pop(context, _sysCtrl.text), width: 110, accent: true),
              ]),
            ] else ...[
            Container(
              width: 640,
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
            Row(mainAxisSize: MainAxisSize.min, children: [
              _key('USA LA TASTIERA DEL TELEFONO O DELLA TV', () => setState(() {
                    _sysCtrl.text = _text;
                    _system = true;
                  }), width: 420, icon: Icons.keyboard_alt_outlined),
            ]),
            ],
          ]),
          ),
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

/// Tasto della tastiera a schermo: OK / Invio / tasto centrale del telecomando lo premono
/// direttamente (senza passare dalle scorciatoie dell'app, che su alcuni telecomandi non arrivano).
class _KbKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final double width;
  final bool accent, autofocus;
  final IconData? icon;
  const _KbKey({required this.label, required this.onTap, required this.width, required this.accent, required this.autofocus, this.icon});
  @override
  State<_KbKey> createState() => _KbKeyState();
}

class _KbKeyState extends State<_KbKey> {
  bool _focused = false, _pressed = false;
  static final _activate = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.mediaPlayPause,
  };

  void _press() {
    widget.onTap();
    setState(() => _pressed = true);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFF3E7CF);
    final label = widget.label;
    final child = widget.icon != null && label.isNotEmpty
        ? Row(mainAxisSize: MainAxisSize.min, children: [Icon(widget.icon, size: 20, color: ink), const SizedBox(width: 8), Text(label, style: LK.label(12, color: ink, spacing: 0.3))])
        : widget.icon != null
            ? Icon(widget.icon, size: 22, color: ink)
            : Text(label, style: LK.label(label.length > 3 ? 12 : 17, color: ink, spacing: 0.3));
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: (node, e) {
          if (!_activate.contains(e.logicalKey)) return KeyEventResult.ignored;
          if (e is KeyDownEvent) _press();
          return KeyEventResult.handled;
        },
        child: GestureDetector(
          onTap: _press,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: widget.width,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _pressed
                  ? const Color(0xFFE0703F)
                  : widget.accent
                      ? LK.accent
                      : _focused
                          ? const Color(0x55E0703F)
                          : const Color(0xFF3A302A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _focused ? const Color(0xFFE0703F) : Colors.transparent, width: 3),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
