import 'package:flutter/material.dart';

import '../services/updater.dart';
import '../theme.dart';

/// Finestra "nuova versione": scarica l'APK e apre l'installazione.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo u) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _UpdateDialog(u),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo u;
  const _UpdateDialog(this.u);
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await Updater.install(widget.u, (v) {
        if (mounted) setState(() => _progress = v);
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Aggiornamento non riuscito: $e\nSe Android lo chiede, consenti a Lorekeeper di installare app.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final mb = u.size > 0 ? ' · ${(u.size / 1048576).toStringAsFixed(1)} MB' : '';
    return AlertDialog(
      backgroundColor: LK.paper,
      title: Text('Nuova versione', style: LK.display(21)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('È disponibile la build ${u.build}$mb.', style: LK.body(14.5)),
        if (u.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(child: Text(u.notes.trim(), style: LK.body(13, color: LK.muted))),
          ),
        ],
        if (_progress != null) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(value: _progress, color: LK.accent, backgroundColor: LK.line),
          const SizedBox(height: 6),
          Text('Scarico… ${(_progress! * 100).round()}%', style: LK.label(10, spacing: 0.4)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: LK.body(13, color: LK.accent)),
        ],
      ]),
      actions: [
        if (_progress == null) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Più tardi')),
        if (_progress == null)
          FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: _go, child: const Text('Aggiorna')),
      ],
    );
  }
}
