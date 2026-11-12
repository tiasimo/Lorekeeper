import 'package:audioplayers/audioplayers.dart';

import 'library_store.dart';
import 'weather.dart';

/// Suoni d'ambiente in sottofondo mentre leggi.
class Ambience {
  Ambience._();
  static final I = Ambience._();

  static const sounds = {
    'Automatico': null,
    'Pioggia': 'pioggia',
    'Camino': 'camino',
    'Taverna': 'taverna',
    'Vento': 'vento',
    'Mare': 'mare',
    'Notte': 'notte',
  };

  AudioPlayer? _player;
  String? _playing;
  bool _active = false;

  /// Con "Automatico" il suono segue il meteo vero e l'ora.
  String _pick() {
    final a = LibraryStore.I.app;
    final chosen = sounds[a.ambientSound];
    if (chosen != null) return chosen;
    final w = Weather.I.now;
    if (w != null) {
      switch (w.sky) {
        case Sky.rain:
        case Sky.storm:
          return 'pioggia';
        case Sky.snow:
          return 'camino';
        case Sky.fog:
          return 'vento';
        default:
      }
    }
    final h = DateTime.now().hour;
    if (h >= 22 || h < 6) return 'notte';
    if (h >= 18) return 'camino';
    return 'taverna';
  }

  /// Da chiamare quando si apre il lettore.
  Future<void> start() async {
    _active = true;
    await update();
  }

  /// Applica le impostazioni attuali (attivo, suono, volume).
  Future<void> update() async {
    final a = LibraryStore.I.app;
    if (!_active || !a.ambient) {
      await _stop();
      return;
    }
    Weather.I.refresh();
    final name = _pick();
    try {
      final p = _player ??= AudioPlayer();
      await p.setAudioContext(AudioContext(
          android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none, usageType: AndroidUsageType.media, contentType: AndroidContentType.music),
      ));
      await p.setReleaseMode(ReleaseMode.loop);
      if (_playing != name) {
        _playing = name;
        await p.stop();
        await p.setVolume(0);
        await p.play(AssetSource('sounds/$name.ogg'));
        // dissolvenza in entrata
        for (var i = 1; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 120));
          if (_playing != name) return;
          await p.setVolume(a.ambientVolume * i / 10);
        }
      } else {
        await p.setVolume(a.ambientVolume);
      }
    } catch (_) {}
  }

  /// Da chiamare quando si chiude il lettore.
  Future<void> stop() async {
    _active = false;
    await _stop();
  }

  Future<void> _stop() async {
    _playing = null;
    final p = _player;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
  }

  /// In pausa quando l'app va in background.
  Future<void> pause() async {
    try {
      await _player?.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    if (!_active || _playing == null) return;
    try {
      await _player?.resume();
    } catch (_) {}
  }
}
