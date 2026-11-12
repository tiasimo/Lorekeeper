import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Colori della versione TV ("home cinema").
class TV {
  static const bg = Color(0xFF1C1714);
  static const bgDeep = Color(0xFF141110);
  static const ink = Color(0xFFF3E7CF);
  static const muted = Color(0xFFA89A86);
  static const soft = Color(0xFFCDBFA6);
  static const accent = Color(0xFFE0703F);
  static const gold = Color(0xFFE2B95C);
  static const peach = Color(0xFFF0A27A);
}

/// Un elemento che si seleziona con il telecomando: quando è a fuoco si ingrandisce
/// e prende il bordo arancione; OK (o il tocco) lo apre.
class TvFocus extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;
  final double scale;
  final BorderRadius radius;
  final FocusNode? focusNode;
  const TvFocus({
    super.key,
    required this.child,
    this.onSelect,
    this.onFocus,
    this.autofocus = false,
    this.scale = 1.08,
    this.radius = const BorderRadius.all(Radius.circular(10)),
    this.focusNode,
  });

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onSelect?.call();
          return null;
        }),
      },
      onShowFocusHighlight: (v) {
        setState(() => _focused = v);
        widget.onFocus?.call(v);
        if (v) {
          Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        }
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: widget.radius,
              boxShadow: _focused
                  ? const [
                      BoxShadow(color: TV.bg, spreadRadius: 3),
                      BoxShadow(color: TV.accent, spreadRadius: 6),
                      BoxShadow(color: Color(0x73E0703F), blurRadius: 30, spreadRadius: 4, offset: Offset(0, 12)),
                    ]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Pulsante a pillola per la TV.
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
        scale: 1.05,
        radius: BorderRadius.circular(28),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: primary ? TV.ink : const Color(0x1FF3E7CF), borderRadius: BorderRadius.circular(28)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: primary ? TV.bg : TV.ink, size: 19), const SizedBox(width: 7)],
            Text(label.toUpperCase(), style: tvLabel(12, color: primary ? TV.bg : TV.ink, spacing: 1)),
          ]),
        ),
      );
}

TextStyle tvDisplay(double size, {Color color = TV.ink, FontStyle? style}) => LK.display(size, color: color, style: style).copyWith(height: 1.1);
TextStyle tvBody(double size, {Color color = TV.soft}) => LK.body(size, color: color, height: 1.4);
TextStyle tvLabel(double size, {Color color = TV.muted, double spacing = 1.6}) => LK.label(size, color: color, spacing: spacing);
