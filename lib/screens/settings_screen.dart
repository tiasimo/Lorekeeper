import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup.dart';
import '../services/library_store.dart';
import '../services/reminders.dart';
import '../services/secrets.dart';
import '../services/updater.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shelf_backdrop.dart';
import '../widgets/spine.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController(text: LibraryStore.I.readerName);
  final _key = TextEditingController();
  bool _checking = false;
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
      body: TabletSafeArea(
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
            const SizedBox(height: 22),
            const SectionLabel('Divisori dello scaffale'),
            ListenableBuilder(
              listenable: LibraryStore.I,
              builder: (context, _) {
                const opts = ['Scelti da me', 'Automatici'];
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Segmented(
                    labels: opts,
                    selected: opts.indexOf(LibraryStore.I.app.dividers).clamp(0, 1),
                    onChanged: (i) {
                      LibraryStore.I.app.dividers = opts[i];
                      LibraryStore.I.saveAppPrefs();
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            const SectionLabel('Sfondo degli scaffali'),
            ListenableBuilder(
              listenable: LibraryStore.I,
              builder: (context, _) {
                final app = LibraryStore.I.app;
                Widget picker(String label, String current, ValueChanged<String> on) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: LK.body(14))),
                      SizedBox(
                        height: 116,
                        child: ListView(scrollDirection: Axis.horizontal, children: [
                          for (final k in shelfBackdrops)
                            GestureDetector(
                              onTap: () => on(k),
                              child: Container(
                                width: 72,
                                margin: const EdgeInsets.only(right: 8),
                                child: Column(children: [
                                  Container(
                                    height: 86,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: LK.paper,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: current == k ? LK.accent : LK.border, width: current == k ? 2.5 : 1),
                                    ),
                                    child: Stack(children: [
                                      ShelfBackdrop(k),
                                      const Positioned(left: 6, right: 6, bottom: 14, child: ShelfBoard()),
                                    ]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(11)),
                                ]),
                              ),
                            ),
                        ]),
                      ),
                    ]);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  picker('Novel', app.shelfBg, (k) {
                    app.shelfBg = k;
                    LibraryStore.I.saveAppPrefs();
                  }),
                  const SizedBox(height: 10),
                  picker('Manga', app.mangaShelfBg, (k) {
                    app.mangaShelfBg = k;
                    LibraryStore.I.saveAppPrefs();
                  }),
                ]);
              },
            ),
            const SizedBox(height: 22),
            const SectionLabel('Decorazioni degli scaffali'),
            ListenableBuilder(
              listenable: LibraryStore.I,
              builder: (context, _) {
                final app = LibraryStore.I.app;
                const mesi = ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'];
                String label() {
                  final b = app.birthday;
                  if (b == null) return 'Non impostato';
                  final parts = b.split('-');
                  if (parts.length == 3) return '${int.parse(parts[2])} ${mesi[int.parse(parts[1]) - 1]} ${parts[0]}';
                  return '${int.parse(parts[1])} ${mesi[int.parse(parts[0]) - 1]}';
                }

                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: LK.accent,
                    value: app.seasonal,
                    onChanged: (v) {
                      app.seasonal = v;
                      LibraryStore.I.saveAppPrefs();
                    },
                    title: Text('Feste e stagioni sugli scaffali', style: LK.body(14.5)),
                    subtitle: Text('Natale, Capodanno, Befana, San Valentino, Carnevale, Pasqua, 2 giugno, Halloween, le stagioni, il tuo compleanno e altro.', style: LK.body(12.5, color: LK.muted)),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cake_outlined, color: LK.accent),
                    title: Text('Il tuo compleanno', style: LK.body(14.5)),
                    subtitle: Text(label(), style: LK.body(12.5, color: LK.muted)),
                    trailing: app.birthday == null
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close, color: LK.muted, size: 18),
                            onPressed: () {
                              app.birthday = null;
                              LibraryStore.I.saveAppPrefs();
                            },
                          ),
                    onTap: () async {
                      final now = DateTime.now();
                      final cur = DateTime.tryParse(app.birthday ?? '');
                      final d = await showDatePicker(
                        context: context,
                        initialDate: cur ?? DateTime(now.year - 25, now.month, now.day),
                        firstDate: DateTime(1920, 1, 1),
                        lastDate: now,
                        helpText: 'LA TUA DATA DI NASCITA',
                        initialDatePickerMode: DatePickerMode.year,
                      );
                      if (d == null) return;
                      app.birthday = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                      LibraryStore.I.saveAppPrefs();
                    },
                  ),
                ]);
              },
            ),
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
            const SectionLabel('Backup'),
            Text(
              'Android salva in automatico su Google Drive libreria, progressi, wiki, note e statistiche '
              '(Impostazioni del telefono → Google → Backup). Gli EPUB non sono inclusi: dopo un ripristino '
              'basta reimportarli e ogni libro ritrova i suoi dati.',
              style: LK.body(13, color: LK.muted),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(side: BorderSide(color: LK.border), backgroundColor: LK.card),
                onPressed: () async {
                  try {
                    final f = await Backup.export();
                    await Share.shareXFiles([XFile(f.path, mimeType: 'application/zip')], text: 'Backup di Lorekeeper');
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup non riuscito: $e')));
                  }
                },
                icon: Icon(Icons.cloud_upload_outlined, color: LK.accent),
                label: Text('Salva backup (Drive…)', style: LK.body(14)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(side: BorderSide(color: LK.border), backgroundColor: LK.card),
                onPressed: () async {
                  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
                  final path = r?.files.single.path;
                  if (path == null || !mounted) return;
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: LK.paper,
                      title: Text('Ripristinare il backup?', style: LK.display(20)),
                      content: const Text('Libreria, wiki, note e statistiche verranno sostituite con quelle del backup.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
                        FilledButton(style: FilledButton.styleFrom(backgroundColor: LK.accent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ripristina')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    final missing = await Backup.restore(path);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(missing == 0 ? 'Backup ripristinato' : 'Backup ripristinato. Reimporta $missing EPUB dalla libreria per riaprirli.'),
                    ));
                    setState(() {});
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ripristino non riuscito: $e')));
                  }
                },
                icon: Icon(Icons.restore, color: LK.accent),
                label: Text('Ripristina', style: LK.body(14)),
              ),
            ]),
            const SizedBox(height: 30),
            const SectionLabel('Informazioni'),
            Text('Lorekeeper 0.8 · il custode delle tue storie', style: LK.body(14)),
            FutureBuilder<String>(
              future: Updater.currentVersion(),
              builder: (_, s) => Text(s.data ?? '', style: LK.body(12.5, color: LK.muted)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(side: BorderSide(color: LK.border), backgroundColor: LK.card),
              onPressed: _checking
                  ? null
                  : () async {
                      setState(() => _checking = true);
                      try {
                        final u = await Updater.check();
                        if (!mounted) return;
                        if (u == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hai già l\'ultima versione')));
                        } else {
                          await showUpdateDialog(context, u);
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Controllo non riuscito: $e')));
                      } finally {
                        if (mounted) setState(() => _checking = false);
                      }
                    },
              icon: _checking ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: LK.accent)) : Icon(Icons.system_update_alt, color: LK.accent),
              label: Text('Cerca aggiornamenti', style: LK.body(14)),
            ),
          ],
        ),
      ),
    );
  }
}
