import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

class Secrets {
  static const _s = FlutterSecureStorage();
  static Future<String?> geminiKey() => _s.read(key: 'gemini_key');
  static Future<void> setGeminiKey(String? v) =>
      v == null || v.trim().isEmpty ? _s.delete(key: 'gemini_key') : _s.write(key: 'gemini_key', value: v.trim());
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController(text: LibraryStore.I.readerName);
  final _key = TextEditingController();
  bool _show = false;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    Secrets.geminiKey().then((k) {
      if (!mounted) return;
      setState(() {
        _hasKey = k != null && k.isNotEmpty;
        _key.text = k ?? '';
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: LK.card,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: LK.border)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            const Align(alignment: Alignment.centerLeft, child: BackLink(trail: 'Libreria')),
            Text('Impostazioni', style: LK.display(28)),
            const SizedBox(height: 22),
            const SectionLabel('Il tuo nome'),
            TextField(
              controller: _name,
              decoration: _dec('Come vuoi essere salutato?'),
              onSubmitted: LibraryStore.I.setReaderName,
              onChanged: LibraryStore.I.setReaderName,
            ),
            const SizedBox(height: 26),
            const SectionLabel('Aspetto'),
            ListenableBuilder(
              listenable: LibraryStore.I,
              builder: (context, _) {
                const opts = ['Giorno', 'Notte', 'Sistema'];
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Segmented(
                    labels: opts,
                    selected: opts.indexOf(LibraryStore.I.appTheme).clamp(0, 2),
                    onChanged: (i) => LibraryStore.I.setAppTheme(opts[i]),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Text('Sistema segue la modalità chiara o scura del telefono. Di notte anche la lettura passa al tema Notte.',
                style: LK.body(12, color: LK.muted, style: FontStyle.italic)),
            const SizedBox(height: 26),
            const SectionLabel('Chiave API Gemini'),
            Text(
              'Serve per la wiki e i riassunti. La chiave resta cifrata solo su questo telefono. '
              'Puoi crearla gratis da Google AI Studio (aistudio.google.com → Get API key).',
              style: LK.body(13, color: LK.muted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _key,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _dec('Incolla qui la chiave',
                  suffix: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show))),
            ),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: LK.accent),
                onPressed: () async {
                  await Secrets.setGeminiKey(_key.text);
                  if (!mounted) return;
                  setState(() => _hasKey = _key.text.trim().isNotEmpty);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_hasKey ? 'Chiave salvata' : 'Chiave rimossa')));
                },
                child: const Text('Salva chiave'),
              ),
              const SizedBox(width: 12),
              Icon(_hasKey ? Icons.check_circle : Icons.radio_button_unchecked, color: _hasKey ? const Color(0xFF2F6B46) : LK.muted, size: 18),
              const SizedBox(width: 6),
              Text(_hasKey ? 'Chiave presente' : 'Nessuna chiave', style: LK.body(13, color: LK.muted)),
            ]),
            const SizedBox(height: 30),
            const SectionLabel('Informazioni'),
            Text('Lorekeeper 0.1 · il custode delle tue storie', style: LK.body(14)),
            const SizedBox(height: 4),
            Text('Fase 1: libreria, scaffale, dorsi e lettore. In arrivo: wiki con Gemini, evidenziazioni, lettura ad alta voce, backup e widget.',
                style: LK.body(13, color: LK.muted)),
          ],
        ),
      ),
    );
  }
}
