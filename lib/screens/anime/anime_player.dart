import 'dart:async';
import 'dart:convert';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart' as br;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/anime_store.dart';
import '../../services/crash_log.dart';
import '../../services/library_store.dart';
import '../../services/manga_store.dart';
import '../../theme.dart';
import '../../tv/tv_mode.dart';
import '../../tv/tv_widgets.dart';

/// Player degli episodi: qualità, sottotitoli, velocità, salta sigla (AniSkip),
/// episodio successivo automatico e AniList aggiornato a fine episodio.
class AnimePlayer extends StatefulWidget {
  final SavedAnime anime;
  final br.Source source;
  final MChapter episode;
  const AnimePlayer({super.key, required this.anime, required this.source, required this.episode});
  @override
  State<AnimePlayer> createState() => _AnimePlayerState();
}

class _AnimePlayerState extends State<AnimePlayer> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final store = AnimeStore.I;
  late MChapter _ep = widget.episode;
  List<br.Video> _videos = [];
  br.Video? _current;
  String? _error;
  bool _loading = true, _ui = true, _markedThis = false;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false, _buffering = true;
  double _rate = 1.0;
  Timer? _hide, _saveTick;
  final List<StreamSubscription> _subs = [];
  List<(String, Duration, Duration)> _skips = []; // tipo, inizio, fine
  int? _nextIn; // secondi al prossimo episodio
  Timer? _nextTimer;
  int _run = 0;

  SavedAnime get a => widget.anime;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _subs.addAll([
      _player.stream.position.listen((p) {
        _pos = p;
        _checkWatched();
        if (mounted && _ui) setState(() {});
        if (mounted && _activeSkip() != null) setState(() {});
      }),
      _player.stream.duration.listen((d) => setState(() => _dur = d)),
      _player.stream.playing.listen((v) => setState(() => _playing = v)),
      _player.stream.buffering.listen((v) => setState(() => _buffering = v)),
      _player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      _player.stream.error.listen((e) {
        if (mounted && _current != null && _pos == Duration.zero) setState(() => _error = e);
      }),
    ]);
    _saveTick = Timer.periodic(const Duration(seconds: 5), (_) {
      _savePos();
      if (_playing && !_buffering) LibraryStore.I.addAnimeTime(5);
    });
    _open(_ep);
  }

  Future<void> _open(MChapter ep) async {
    final my = ++_run;
    _savePos();
    _nextTimer?.cancel();
    setState(() {
      _ep = ep;
      _loading = true;
      _error = null;
      _videos = [];
      _skips = [];
      _nextIn = null;
      _markedThis = false;
      _pos = Duration.zero;
    });
    try {
      final before = MangaStore.bridgeLogs.length;
      var list = await widget.source.methods.getVideoList(ep.toEpisode());
      if (list.isEmpty) {
        // a volte la sorgente risponde al secondo tentativo
        await Future.delayed(const Duration(milliseconds: 600));
        list = await widget.source.methods.getVideoList(ep.toEpisode());
      }
      if (my != _run || !mounted) return;
      if (list.isEmpty) {
        final logs = MangaStore.bridgeLogs.length > before ? MangaStore.bridgeLogs.sublist(before) : const <String>[];
        final why = logs.where((l) => l.contains('getVideoList') || l.toLowerCase().contains('error') || l.contains('Exception')).lastOrNull;
        throw Exception('la sorgente non ha restituito nessun video per questo episodio${why == null ? '' : '\n\nDettagli: $why'}');
      }
      _videos = list;
      final prefs = await SharedPreferences.getInstance();
      final want = prefs.getString('anime.quality') ?? 'alta';
      _current = _pick(list, want);
      await _play(_current!, start: a.positions[ep.url] ?? 0);
      _loadSkips(ep);
    } catch (e) {
      if (tvMode) CrashLog.add('Player · ${a.sourceName} · ep. ${a.numberOf(ep)}: $e');
      if (my == _run && mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (my == _run && mounted) setState(() => _loading = false);
    }
  }

  static int _res(br.Video v) {
    final m = RegExp(r'(\d{3,4})p').firstMatch('${v.quality} ${v.title ?? ''}');
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  br.Video _pick(List<br.Video> list, String want) {
    final sorted = [...list]..sort((x, y) => _res(y).compareTo(_res(x)));
    if (want == 'bassa') return sorted.last;
    if (want == 'media') return sorted[sorted.length ~/ 2];
    return sorted.first;
  }

  Future<void> _play(br.Video v, {int start = 0}) async {
    _current = v;
    await _player.open(
      Media(v.url, httpHeaders: v.headers, start: start > 5 ? Duration(seconds: start - 3) : null),
      play: true,
    );
    await _player.setRate(_rate);
    // sottotitoli: prima l'italiano, se c'è
    final subs = v.subtitles ?? const [];
    final ita = subs.where((t) => '${t.label}'.toLowerCase().contains('ital')).firstOrNull;
    final pick = ita ?? (subs.isNotEmpty ? subs.first : null);
    if (pick?.file != null) {
      await _player.setSubtitleTrack(SubtitleTrack.uri(pick!.file!, title: pick.label, language: pick.label));
    }
    if ((v.audios ?? const []).isNotEmpty && v.audios!.first.file != null) {
      await _player.setAudioTrack(AudioTrack.uri(v.audios!.first.file!, title: v.audios!.first.label));
    }
    _bumpUi();
  }

  /// Tempi di sigla e chiusura da AniSkip (serve l'id di MyAnimeList, da AniList).
  Future<void> _loadSkips(MChapter ep) async {
    final mal = a.malId;
    if (mal == null) return;
    try {
      final n = a.numberOf(ep);
      final r = await http
          .get(Uri.parse('https://api.aniskip.com/v2/skip-times/$mal/$n?types%5B%5D=op&types%5B%5D=ed&types%5B%5D=recap&episodeLength=0'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map;
      if (j['found'] != true) return;
      final out = <(String, Duration, Duration)>[];
      for (final x in (j['results'] as List).cast<Map>()) {
        final iv = x['interval'] as Map;
        out.add((x['skipType'] as String, Duration(milliseconds: ((iv['startTime'] as num) * 1000).round()), Duration(milliseconds: ((iv['endTime'] as num) * 1000).round())));
      }
      if (mounted && ep.url == _ep.url) setState(() => _skips = out);
    } catch (_) {}
  }

  (String, Duration, Duration)? _activeSkip() {
    for (final s in _skips) {
      if (_pos >= s.$2 && _pos < s.$3 - const Duration(seconds: 1)) return s;
    }
    return null;
  }

  void _savePos() {
    if (_pos.inSeconds < 5 || _markedThis) return;
    store.setPosition(a, _ep, _pos.inSeconds);
  }

  void _checkWatched() {
    if (_markedThis || _dur.inSeconds < 60) return;
    if (_pos.inMilliseconds >= _dur.inMilliseconds * 0.85) {
      _markedThis = true;
      store.markWatched(a, _ep);
      store.setPosition(a, _ep, 0);
    }
  }

  MChapter? get _nextEp {
    final o = a.ordered;
    final i = o.indexWhere((e) => e.url == _ep.url);
    return i >= 0 && i + 1 < o.length ? o[i + 1] : null;
  }

  MChapter? get _prevEp {
    final o = a.ordered;
    final i = o.indexWhere((e) => e.url == _ep.url);
    return i > 0 ? o[i - 1] : null;
  }

  void _onCompleted() {
    if (!_markedThis) {
      _markedThis = true;
      store.markWatched(a, _ep);
    }
    final n = _nextEp;
    if (n == null || !mounted) return;
    setState(() => _nextIn = 6);
    _nextTimer?.cancel();
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if ((_nextIn ?? 0) <= 1) {
        t.cancel();
        _open(n);
      } else {
        setState(() => _nextIn = _nextIn! - 1);
      }
    });
  }

  void _bumpUi() {
    _hide?.cancel();
    if (!mounted) return;
    setState(() => _ui = true);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _ui = false);
    });
  }

  void _seek(Duration d) {
    final t = d < Duration.zero ? Duration.zero : (d > _dur ? _dur : d);
    _player.seek(t);
    _bumpUi();
  }

  Future<void> _toggleFull() async {
    final land = MediaQuery.orientationOf(context) == Orientation.landscape;
    await SystemChrome.setPreferredOrientations(
      land ? [DeviceOrientation.portraitUp] : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }

  @override
  void dispose() {
    _savePos();
    _hide?.cancel();
    _saveTick?.cancel();
    _nextTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _keyFocus.dispose();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  // ---------- pannelli ----------
  Future<void> _sheet(String title, List<(String, bool, VoidCallback)> items) => showModalBottomSheet(
        context: context,
        backgroundColor: LK.paper,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: ListView(
                shrinkWrap: true,
                // sulla TV l'elenco parte dalla voce scelta, che prende la selezione del telecomando
                controller: ScrollController(initialScrollOffset: tvMode && items.indexWhere((x) => x.$2) > 3 ? (items.indexWhere((x) => x.$2) - 2) * 56.0 : 0),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
              Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(title, style: LK.display(19))),
              for (final (label, sel, onTap) in items)
                ListTile(
                  autofocus: tvMode && (items.any((x) => x.$2) ? sel : identical(label, items.first.$1)),
                  title: Text(label, style: LK.body(14.5)),
                  trailing: sel ? Icon(Icons.check, color: LK.accent) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onTap();
                  },
                ),
            ]),
          ),
        ),
      );

  void _qualitySheet() => _sheet('Qualità e server', [
        for (final v in _videos)
          (
            [v.quality, if ((v.title ?? '').isNotEmpty && v.title != v.quality) v.title].join(' · '),
            identical(v, _current),
            () => _play(v, start: _pos.inSeconds),
          ),
      ]);

  void _subsSheet() {
    final subs = _current?.subtitles ?? const <br.Track>[];
    _sheet('Sottotitoli', [
      ('Nessuno', false, () => _player.setSubtitleTrack(SubtitleTrack.no())),
      for (final t in _player.state.tracks.subtitle.where((t) => t.id != 'no' && t.id != 'auto'))
        ('${t.title ?? t.language ?? t.id} (nel video)', _player.state.track.subtitle.id == t.id, () => _player.setSubtitleTrack(t)),
      for (final t in subs)
        if (t.file != null) (t.label ?? 'Sottotitoli', false, () => _player.setSubtitleTrack(SubtitleTrack.uri(t.file!, title: t.label, language: t.label))),
    ]);
  }

  void _audioSheet() => _sheet('Audio', [
        for (final t in _player.state.tracks.audio.where((t) => t.id != 'no'))
          (
            t.id == 'auto' ? 'Automatico' : (t.title ?? t.language ?? 'Traccia ${t.id}'),
            _player.state.track.audio.id == t.id,
            () => _player.setAudioTrack(t),
          ),
      ]);

  /// Sulla TV: un solo menu (▲) per audio, sottotitoli, qualità e velocità.
  void _tvOptions() => _sheet('Audio e sottotitoli', [
        ('Sottotitoli', false, _subsSheet),
        ('Audio', false, _audioSheet),
        if (_videos.isNotEmpty) ('Qualità e server · ${_current?.quality ?? ''}', false, _qualitySheet),
        ('Velocità · ${_rate}x', false, _speedSheet),
      ]);

  void _speedSheet() => _sheet('Velocità', [
        for (final r in const [0.75, 1.0, 1.25, 1.5, 2.0])
          (
            '${r}x',
            r == _rate,
            () {
              setState(() => _rate = r);
              _player.setRate(r);
            }
          ),
      ]);

  void _episodesSheet() => _sheet('Episodi', [
        for (final e in a.ordered)
          (
            '${a.numberOf(e)}. ${e.name}${a.isWatched(e) ? '  ✓' : ''}',
            e.url == _ep.url,
            () => _open(e),
          ),
      ]);

  // ---------- interfaccia ----------
  Widget _controls(bool land) {
    final skip = _activeSkip();
    const white = Colors.white;
    return Stack(children: [
      // tocco: mostra/nasconde; doppio tocco ai lati: ±10 s
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _ui ? setState(() => _ui = false) : _bumpUi(),
          onDoubleTapDown: (d) {
            final w = context.size?.width ?? 400;
            _seek(_pos + Duration(seconds: d.localPosition.dx < w / 2 ? -10 : 10));
          },
          onDoubleTap: () {},
        ),
      ),
      if ((_buffering || _loading) && _error == null) const Center(child: CircularProgressIndicator(color: Colors.white)),
      if (_error != null)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Non riesco a riprodurre l\'episodio.', style: LK.display(17, color: white)),
              const SizedBox(height: 6),
              Text(_error!, maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: LK.body(12.5, color: Colors.white70)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                if (_videos.length > 1) OutlinedButton(onPressed: _qualitySheet, style: OutlinedButton.styleFrom(foregroundColor: white), child: const Text('Cambia server')),
                OutlinedButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${a.sourceName} · ${_ep.url}\n$_error\n\n${MangaStore.bridgeLogs.reversed.take(15).join('\n')}'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dettagli copiati: incollameli in chat')));
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: white),
                  child: const Text('Copia dettagli'),
                ),
                FilledButton(onPressed: () => _open(_ep), style: FilledButton.styleFrom(backgroundColor: LK.accent), child: const Text('Riprova')),
              ]),
            ]),
          ),
        ),
      IgnorePointer(
        ignoring: !_ui,
        child: AnimatedOpacity(
          opacity: _ui ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xAA000000)],
                      stops: const [0, 0.3, 0.6, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              right: 4,
              top: land ? 8 : 4,
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: white), onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (land) Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.display(15, color: white)),
                    Text('Ep. ${a.numberOf(_ep)} · ${_ep.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(12.5, color: Colors.white70)),
                  ]),
                ),
                IconButton(tooltip: 'Sottotitoli', icon: const Icon(Icons.subtitles_outlined, color: white), onPressed: _subsSheet),
                TextButton(onPressed: _speedSheet, child: Text('${_rate}x', style: LK.label(11, color: white, spacing: 0.4))),
                if (_videos.isNotEmpty)
                  TextButton(onPressed: _qualitySheet, child: Text(_current?.quality ?? 'Qualità', maxLines: 1, style: LK.label(11, color: white, spacing: 0.4))),
                if (land) IconButton(tooltip: 'Episodi', icon: const Icon(Icons.format_list_bulleted, color: white), onPressed: _episodesSheet),
              ]),
            ),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (land)
                  IconButton(iconSize: 30, onPressed: _prevEp == null ? null : () => _open(_prevEp!), icon: Icon(Icons.skip_previous, color: _prevEp == null ? Colors.white30 : white)),
                IconButton(iconSize: 34, onPressed: () => _seek(_pos - const Duration(seconds: 10)), icon: const Icon(Icons.replay_10, color: white)),
                const SizedBox(width: 18),
                Material(
                  color: const Color(0xEEFAF7F2),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      _player.playOrPause();
                      _bumpUi();
                    },
                    child: SizedBox(width: 64, height: 64, child: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 34, color: LK.accent)),
                  ),
                ),
                const SizedBox(width: 18),
                IconButton(iconSize: 34, onPressed: () => _seek(_pos + const Duration(seconds: 10)), icon: const Icon(Icons.forward_10, color: white)),
                if (land) IconButton(iconSize: 30, onPressed: _nextEp == null ? null : () => _open(_nextEp!), icon: Icon(Icons.skip_next, color: _nextEp == null ? Colors.white30 : white)),
              ]),
            ),
            Positioned(
              left: 12,
              right: 4,
              bottom: land ? 10 : 2,
              child: Row(children: [
                Text(_fmt(_pos), style: LK.label(10, color: white, spacing: 0.3)),
                Expanded(
                  child: Stack(alignment: Alignment.center, children: [
                    // sigle segnate sulla barra
                    if (_dur.inMilliseconds > 0)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: LayoutBuilder(builder: (context, c) {
                            return Stack(children: [
                              for (final s in _skips)
                                Positioned(
                                  left: c.maxWidth * s.$2.inMilliseconds / _dur.inMilliseconds,
                                  width: c.maxWidth * (s.$3 - s.$2).inMilliseconds / _dur.inMilliseconds,
                                  top: c.maxHeight / 2 - 2,
                                  height: 4,
                                  child: Container(color: const Color(0xFFE2B95C)),
                                ),
                            ]);
                          }),
                        ),
                      ),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: const Color(0xFFE06A4F),
                        inactiveTrackColor: Colors.white24,
                        thumbColor: white,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _dur.inMilliseconds == 0 ? 0 : _pos.inMilliseconds.clamp(0, _dur.inMilliseconds).toDouble(),
                        max: _dur.inMilliseconds == 0 ? 1 : _dur.inMilliseconds.toDouble(),
                        onChanged: (v) => setState(() => _pos = Duration(milliseconds: v.round())),
                        onChangeEnd: (v) => _seek(Duration(milliseconds: v.round())),
                      ),
                    ),
                  ]),
                ),
                Text(_fmt(_dur), style: LK.label(10, color: white, spacing: 0.3)),
                IconButton(
                  tooltip: land ? 'Esci dallo schermo intero' : 'Schermo intero',
                  icon: Icon(land ? Icons.fullscreen_exit : Icons.fullscreen, color: white),
                  onPressed: _toggleFull,
                ),
              ]),
            ),
          ]),
        ),
      ),
      if (skip != null)
        Positioned(
          right: 16,
          bottom: land ? 64 : 46,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xF2FAF7F2), foregroundColor: LK.ink),
            onPressed: () => _seek(skip.$3),
            child: Text(skip.$1 == 'ed' ? 'SALTA SIGLA FINALE ›' : skip.$1 == 'recap' ? 'SALTA RIASSUNTO ›' : 'SALTA SIGLA ›', style: LK.label(10.5, color: LK.ink, spacing: 0.8)),
          ),
        ),
      if (_nextIn != null && _nextEp != null)
        Positioned(
          right: 16,
          bottom: land ? 64 : 46,
          child: Material(
            color: const Color(0xDD140E18),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _open(_nextEp!),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('TRA $_nextIn S', style: LK.label(9, color: Colors.white70, spacing: 1)),
                    Text('Ep. ${a.numberOf(_nextEp!)} · ${_nextEp!.name}', style: LK.body(13, color: white)),
                  ]),
                  IconButton(
                    onPressed: () {
                      _nextTimer?.cancel();
                      setState(() => _nextIn = null);
                    },
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // telecomando: ◀ ▶ ±10 s, OK pausa (o salta la sigla), ▲ ▼ mostra i comandi
  final _keyFocus = FocusNode();
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (tvMode) return _onKeyTv(k, e is KeyRepeatEvent);
    if (_ui && (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown)) return KeyEventResult.ignored;
    if (_ui && (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter)) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seek(_pos + const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seek(_pos - const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
      final skip = _activeSkip();
      if (skip != null) {
        _seek(skip.$3);
      } else if (_nextIn != null && _nextEp != null) {
        _open(_nextEp!);
      } else {
        _player.playOrPause();
        _bumpUi();
      }
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _bumpUi();
    } else if (k == LogicalKeyboardKey.mediaTrackNext && _nextEp != null) {
      _open(_nextEp!);
    } else if (k == LogicalKeyboardKey.mediaTrackPrevious && _prevEp != null) {
      _open(_prevEp!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Telecomando della TV: ◀ ▶ ±10 s, OK pausa (o salta la sigla / riprova), ▲ audio e sottotitoli, ▼ episodi.
  KeyEventResult _onKeyTv(LogicalKeyboardKey k, bool repeat) {
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seek(_pos + const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seek(_pos - const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause ||
        k == LogicalKeyboardKey.space) {
      if (repeat) return KeyEventResult.handled;
      final skip = _activeSkip();
      if (_error != null) {
        _open(_ep);
      } else if (skip != null) {
        _seek(skip.$3);
      } else if (_nextIn != null && _nextEp != null) {
        _open(_nextEp!);
      } else {
        _player.playOrPause();
        _bumpUi();
      }
    } else if (k == LogicalKeyboardKey.arrowUp) {
      if (!repeat) _tvOptions();
    } else if (k == LogicalKeyboardKey.arrowDown) {
      if (!repeat) _episodesSheet();
    } else if (k == LogicalKeyboardKey.mediaTrackNext && _nextEp != null) {
      _open(_nextEp!);
    } else if (k == LogicalKeyboardKey.mediaTrackPrevious && _prevEp != null) {
      _open(_prevEp!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// I comandi sulla TV: scritte da lettore DVD, niente pulsanti da toccare.
  Widget _tvControls() {
    final skip = _activeSkip();
    final total = a.alTotal ?? a.episodes.length;
    String two(int n) => n.toString().padLeft(2, '0');
    String clock(Duration d) => '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    final frac = _dur.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);
    final left = _dur - _pos;
    final show = _ui || !_playing || _error != null;
    Widget pill(String text) => Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: TV.accent, boxShadow: [BoxShadow(color: TV.ink, spreadRadius: 6), BoxShadow(color: TV.bg, spreadRadius: 3)]),
          child: Text(text, style: tvDisplay(18, color: TV.bg, spacing: 2)),
        );
    return TvCanvas(
      color: null,
      child: Stack(children: [
        if ((_buffering || _loading) && _error == null) const Center(child: CircularProgressIndicator(color: TV.accent)),
        if (_error != null)
          Center(
            child: Container(
              width: 760,
              padding: const EdgeInsets.all(26),
              color: const Color(0xF217181C),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('NON RIESCO A RIPRODURRE L\'EPISODIO', style: tvDisplay(26, weight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(_error!, maxLines: 6, overflow: TextOverflow.ellipsis, style: tvBody(14)),
                const SizedBox(height: 16),
                Text('OK RIPROVA   ▲ CAMBIA SERVER   ▼ ALTRO EPISODIO   INDIETRO ESCI', style: tvMono(12, color: TV.peach, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Il dettaglio resta in Impostazioni › Errori recenti.', style: tvBody(12, color: TV.muted)),
              ]),
            ),
          ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Stack(children: [
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 170,
                child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC0A0A0B), Color(0x000A0A0B)]))),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 300,
                child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x000A0A0B), Color(0xF00A0A0B)], stops: [0, 0.7]))),
              ),
              Positioned(
                left: 48,
                top: 34,
                child: Row(children: [
                  Icon(_playing ? Icons.play_arrow : Icons.pause, color: TV.peach, size: 26),
                  const SizedBox(width: 6),
                  Text(_playing ? 'PLAY' : 'PAUSA', style: tvMono(22, color: TV.peach, weight: FontWeight.w700).copyWith(letterSpacing: 2)),
                  if (_rate != 1.0) Padding(padding: const EdgeInsets.only(left: 14), child: Text('${_rate}x', style: tvMono(16, color: TV.ink))),
                ]),
              ),
              Positioned(
                right: 48,
                top: 30,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('EP ${two(a.numberOf(_ep))}${total > 0 ? '/${two(total)}' : ''}', style: tvMono(22, color: TV.ink, weight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(clock(_pos), style: tvMono(15, color: const Color(0xFFD6D9DD))),
                ]),
              ),
              Positioned(
                left: 48,
                right: 48,
                bottom: 34,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Flexible(child: Text(a.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: tvDisplay(24, spacing: 1.5))),
                    const SizedBox(width: 14),
                    Flexible(child: Text('${a.numberOf(_ep)} · ${_ep.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tvBody(15, color: const Color(0xFFD6D9DD)))),
                  ]),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 20,
                    child: LayoutBuilder(builder: (context, c) {
                      final w = c.maxWidth;
                      return Stack(clipBehavior: Clip.none, children: [
                        Positioned(left: 0, right: 0, top: 0, height: 6, child: Container(color: const Color(0x42F3F4F5))),
                        Positioned(left: 0, top: 0, width: w * frac, height: 6, child: Container(color: TV.accent)),
                        Positioned(left: w * frac - 2, top: -5, width: 4, height: 16, child: Container(color: Colors.white)),
                        // le sigle, segnate sotto la barra
                        if (_dur.inMilliseconds > 0)
                          for (final s in _skips)
                            Positioned(
                              left: w * s.$2.inMilliseconds / _dur.inMilliseconds,
                              width: w * (s.$3 - s.$2).inMilliseconds / _dur.inMilliseconds,
                              top: 10,
                              height: 3,
                              child: Container(color: TV.ink),
                            ),
                      ]);
                    }),
                  ),
                  Row(children: [
                    Text(_fmt(_pos), style: tvMono(14, color: TV.ink)),
                    const SizedBox(width: 18),
                    if (_skips.isNotEmpty) Text('SIGLE SEGNATE SOTTO LA BARRA', style: tvMono(12, color: TV.soft)),
                    const Spacer(),
                    Text([a.sourceName, if ((_current?.quality ?? '').isNotEmpty) _current!.quality].join(' · ').toUpperCase(), maxLines: 1, style: tvMono(12, color: TV.soft)),
                    const SizedBox(width: 18),
                    Text('-${_fmt(left.isNegative ? Duration.zero : left)}', style: tvMono(14, color: TV.ink)),
                  ]),
                ]),
              ),
              const Positioned(left: 28, bottom: 8, child: TvHints(['◀▶ ±10 S', 'OK PAUSA', '▲ AUDIO E SOTTOTITOLI', '▼ EPISODI'])),
            ]),
          ),
        ),
        if (skip != null && _error == null)
          Positioned(right: 48, bottom: 132, child: pill(skip.$1 == 'ed' ? 'OK · SALTA SIGLA FINALE' : skip.$1 == 'recap' ? 'OK · SALTA RIASSUNTO' : 'OK · SALTA SIGLA'))
        else if (_nextIn != null && _nextEp != null && _error == null)
          Positioned(right: 48, bottom: 132, child: pill('EP. ${two(a.numberOf(_nextEp!))} TRA $_nextIn S · OK PARTE SUBITO')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _keyFocus, autofocus: true, onKeyEvent: _onKey, child: _buildPlayer(context));

  Widget _buildPlayer(BuildContext context) {
    final land = MediaQuery.orientationOf(context) == Orientation.landscape;
    final player = Stack(children: [
      Positioned.fill(child: Video(controller: _video, controls: NoVideoControls, fill: Colors.black)),
      Positioned.fill(child: tvMode ? _tvControls() : _controls(land)),
    ]);
    if (land || tvMode) return Scaffold(backgroundColor: Colors.black, body: player);
    final o = a.ordered;
    final i = o.indexWhere((e) => e.url == _ep.url);
    final upcoming = i < 0 ? <MChapter>[] : o.sublist(i + 1, (i + 6).clamp(0, o.length));
    return Scaffold(
      backgroundColor: LK.paper,
      body: Column(children: [
        Container(
          color: Colors.black,
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: AspectRatio(aspectRatio: 16 / 9, child: player),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 30), children: [
            Text(a.title, style: LK.display(21)),
            const SizedBox(height: 2),
            Text('Episodio ${a.numberOf(_ep)} · ${a.sourceName}', style: LK.body(13, color: LK.muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(Icons.subtitles_outlined, 'Sottotitoli', _subsSheet),
              _chip(Icons.high_quality_outlined, _current?.quality ?? 'Qualità', _qualitySheet),
              _chip(Icons.speed, '${_rate}x', _speedSheet),
            ]),
            if (a.anilistId != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: LK.parchment, borderRadius: BorderRadius.circular(12), border: Border.all(color: LK.parchmentBorder)),
                child: Text(
                  _skips.isEmpty
                      ? 'Alla fine dell\'episodio AniList segna il ${a.numberOf(_ep)} come visto.'
                      : 'Alla fine dell\'episodio AniList segna il ${a.numberOf(_ep)} come visto. Le sigle sono segnate in giallo sulla barra.',
                  style: LK.body(12.5, color: LK.parchmentInk),
                ),
              ),
            ],
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('PROSSIMI EPISODI', style: LK.label(10)),
              const SizedBox(height: 8),
              for (final e in upcoming)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: LK.accentSoft, child: Text('${a.numberOf(e)}', style: LK.label(11, color: LK.accentDark, spacing: 0))),
                  title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LK.body(14.5)),
                  trailing: Icon(Icons.play_arrow, color: LK.accent),
                  onTap: () => _open(e),
                ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 16, color: LK.accent),
        label: Text(label, style: LK.body(13)),
        backgroundColor: LK.card,
        side: BorderSide(color: LK.border),
        onPressed: onTap,
      );
}
