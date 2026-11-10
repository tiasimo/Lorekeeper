import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sfoglia le pagine come un libro: il foglio si solleva dal bordo destro,
/// ruota sul dorso e scopre la pagina sotto, che esce dall'ombra.
class PageTurner extends StatefulWidget {
  final int count;
  final int index;
  final Widget Function(int index) builder; // riceve anche -1 e count (bordi del capitolo)
  final ValueChanged<int> onChanged;
  final VoidCallback onBeforeFirst;
  final VoidCallback onAfterLast;
  final bool canGoBefore;
  final bool canGoAfter;
  final VoidCallback onCenterTap;
  final Color background;

  const PageTurner({
    super.key,
    required this.count,
    required this.index,
    required this.builder,
    required this.onChanged,
    required this.onBeforeFirst,
    required this.onAfterLast,
    required this.canGoBefore,
    required this.canGoAfter,
    required this.onCenterTap,
    required this.background,
  });

  @override
  State<PageTurner> createState() => _PageTurnerState();
}

class _PageTurnerState extends State<PageTurner> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  int _dir = 0; // 1 avanti, -1 indietro
  double _w = 1;

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  bool _allowed(int dir) {
    final target = widget.index + dir;
    if (target < 0) return widget.canGoBefore;
    if (target >= widget.count) return widget.canGoAfter;
    return true;
  }

  Future<void> _complete() async {
    final remaining = 1 - _a.value;
    await _a.animateTo(1, duration: Duration(milliseconds: (300 * remaining).round() + 40), curve: Curves.easeOutCubic);
    if (!mounted) return;
    final target = widget.index + _dir;
    setState(() {
      _dir = 0;
      _a.value = 0;
    });
    if (target < 0) {
      widget.onBeforeFirst();
    } else if (target >= widget.count) {
      widget.onAfterLast();
    } else {
      widget.onChanged(target);
    }
  }

  Future<void> _cancel() async {
    await _a.animateTo(0, duration: Duration(milliseconds: (260 * _a.value).round() + 40), curve: Curves.easeOut);
    if (mounted) setState(() => _dir = 0);
  }

  void turn(int dir) {
    if (_a.isAnimating || _dir != 0 || !_allowed(dir)) return;
    setState(() => _dir = dir);
    _a.value = 0;
    _complete();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_a.isAnimating) return;
    if (_dir == 0) {
      if (d.delta.dx == 0) return;
      final dir = d.delta.dx < 0 ? 1 : -1;
      if (!_allowed(dir)) return;
      setState(() => _dir = dir);
    }
    _a.value = (_a.value + (-d.delta.dx * _dir) / _w).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dir == 0 || _a.isAnimating) return;
    final v = -(d.primaryVelocity ?? 0) * _dir; // positivo = verso il completamento
    if (v > 350 || (_a.value > 0.3 && v > -350)) {
      _complete();
    } else {
      _cancel();
    }
  }

  Widget _page(int i) => ColoredBox(color: widget.background, child: SizedBox.expand(child: widget.builder(i)));

  Widget _turning(Widget child, double t) {
    final angle = -t * math.pi / 2;
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0011)
        ..rotateY(angle),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.black.withValues(alpha: 0.05 * t), Colors.black.withValues(alpha: 0.40 * t)],
          ),
          boxShadow: t > 0.001 ? [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18 * (1 - t) + 4, offset: const Offset(4, 0))] : null,
        ),
        child: child,
      ),
    );
  }

  Widget _under(Widget child, double shade) => Stack(fit: StackFit.expand, children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.black.withValues(alpha: 0.45 * shade), Colors.black.withValues(alpha: 0.10 * shade)],
              ),
            ),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _w = c.maxWidth <= 0 ? 1 : c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onTapUp: (d) {
          final x = d.localPosition.dx / _w;
          if (x < 0.3) {
            turn(-1);
          } else if (x > 0.7) {
            turn(1);
          } else {
            widget.onCenterTap();
          }
        },
        child: AnimatedBuilder(
          animation: _a,
          builder: (context, _) {
            final t = _a.value;
            if (_dir == 1) {
              return Stack(fit: StackFit.expand, children: [
                _under(_page(widget.index + 1), 1 - t),
                _turning(_page(widget.index), t),
              ]);
            }
            if (_dir == -1) {
              return Stack(fit: StackFit.expand, children: [
                _under(_page(widget.index), t),
                _turning(_page(widget.index - 1), 1 - t),
              ]);
            }
            return _page(widget.index);
          },
        ),
      );
    });
  }
}
