import 'package:flutter/material.dart';

import '../services/library_store.dart';
import '../services/reminders.dart';
import '../services/secrets.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
            const SectionLabel('Obiettivo di lettura'),
            ListenableBuilder(
              listenable: LibraryStore.I,
              builder: (context, _) {
                final app = LibraryStore.I.app;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${app.goalMinutes} minuti al giorno', style: LK.body(15)),
                  Slider(
                    min: 5,
                    max: 120,
                    divisions: 23,
                    value: app.goalMinutes.toDouble(),
                    onChanged: (v) {
                      app.goalMinutes = v.round();
                      LibraryStore.I.saveAppPrefs();
                    },
                    onChangeEnd: (_) {
                      if (app.reminder) Reminders.schedule(app.reminderHour, app.reminderMinute, app.goalMinutes);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: LK.accent,
                    title: Text('Promemoria giornaliero', style: LK.body(15)),
                    subtitle: Text(
                      'Ogni giorno alle ${app.reminderHour.toString().padLeft(2, '0')}:${app.reminderMinute.toString().padLeft(2, '0')}',
                      style: LK.body(12, color: LK.muted),
                    ),
                    value: app.reminder,
                    onChanged: (v) async {
                      app.reminder = v;
                      LibraryStore.I.saveAppPrefs();
                      if (v) {
                        final ok = await Reminders.schedule(app.reminderHour, app.reminderMinute, app.goalMinutes);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Consenti le notifiche a Lorekeeper per ricevere il promemoria')));
                        }
                      } else {
                        Reminders.cancel();
                      }
                    },
                  ),
                  if (app.reminder)
                    TextButton.icon(
                      icon: Icon(Icons.schedule, color: LK.accent),
                      label: Text('Cambia orario', style: LK.body(14, color: LK.accent)),
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: app.reminderHour, minute: app.reminderMinute));
                        if (t == null) return;
                        app.reminderHour = t.hour;
                        app.reminderMinute = t.minute;
                        LibraryStore.I.saveAppPrefs();
                        Reminders.schedule(t.hour, t.minute, app.goalMinutes);
                      },
                    ),
                ]);
              },
            ),
            const SizedBox(height: 26),
            const SectionLabel('Wiki e Gemini'),
            ListenableBuilder(
              listenable: LibraryStore.I,
              builder: (context, _) {
                final app = LibraryStore.I.app;
                const spoil = ['Pagina', 'Capitolo', 'Libro'];
                const langs = ['Inglese', 'Italiano', 'Spagnolo', 'Francese', 'Tedesco', 'Portoghese', 'Giapponese'];
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Anti-spoiler: la wiki mostra informazioni fino a…', style: LK.body(14)),
                  const SizedBox(height: 8),
                  Segmented(
                    labels: spoil,
                    selected: spoil.indexOf(app.spoiler).clamp(0, 2),
                    onChanged: (i) {
                      app.spoiler = spoil[i];
                      LibraryStore.I.saveAppPrefs();
                    },
                  ),
                  const SizedBox(height: 4),
                  Text('Pagina: fin dove sei arrivato · Capitolo: fino alla fine del capitolo · Libro: tutto il volume',
                      style: LK.body(12, color: LK.muted, style: FontStyle.italic)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Text('Lingua delle traduzioni', style: LK.body(14))),
                    DropdownButton<String>(
                      value: langs.contains(app.language) ? app.language : langs.first,
                      dropdownColor: LK.card,
                      items: [for (final l in langs) DropdownMenuItem(value: l, child: Text(l, style: LK.body(14)))],
                      onChanged: (v) {
                        if (v == null) return;
                        app.language = v;
                        LibraryStore.I.saveAppPrefs();
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Tieni premuta una parola mentre leggi per avere significato o traduzione.', style: LK.body(12, color: LK.muted, style: FontStyle.italic)),
                  const SizedBox(height: 16),
                  Text('Modello Gemini', style: LK.body(14)),
                  const SizedBox(height: 6),
                  TextFormField(
                    initialValue: app.geminiModel,
                    decoration: _dec('gemini-3.5-flash-lite'),
                    onChanged: (v) {
                      app.geminiModel = v.trim().isEmpty ? 'gemini-3.5-flash-lite' : v.trim();
                      LibraryStore.I.saveAppPrefs();
                    },
                  ),
                ]);
              },
            ),
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
            Text('Lorekeeper 0.3 · il custode delle tue storie', style: LK.body(14)),
            const SizedBox(height: 4),
            Text('In arrivo: wiki con Gemini, evidenziazioni e note, lettura ad alta voce, backup e widget.',
                style: LK.body(13, color: LK.muted)),
          ],
        ),
      ),
    );
  }
}
