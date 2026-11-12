import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'library_store.dart';

/// Che tempo fa, in forma semplice.
enum Sky { clear, cloudy, fog, rain, snow, storm }

class WeatherNow {
  final Sky sky;
  final bool day;
  final double temp;
  final int code;
  const WeatherNow(this.sky, this.day, this.temp, this.code);

  String get label => switch (sky) {
        Sky.clear => day ? 'Sereno' : 'Cielo stellato',
        Sky.cloudy => 'Nuvoloso',
        Sky.fog => 'Nebbia',
        Sky.rain => 'Pioggia',
        Sky.snow => 'Neve',
        Sky.storm => 'Temporale',
      };
}

/// Meteo reale da Open-Meteo (gratuito, senza chiave), per la città scelta.
class Weather extends ChangeNotifier {
  Weather._();
  static final I = Weather._();

  WeatherNow? now;
  DateTime? _at;

  static Sky _sky(int code) {
    if (code >= 95) return Sky.storm;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return Sky.snow;
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return Sky.rain;
    if (code == 45 || code == 48) return Sky.fog;
    if (code >= 2) return Sky.cloudy;
    return Sky.clear;
  }

  /// Aggiorna se sono passati più di 30 minuti.
  Future<void> refresh({bool force = false}) async {
    final a = LibraryStore.I.app;
    if (a.weatherLat == null || a.weatherLon == null) {
      if (now != null) {
        now = null;
        notifyListeners();
      }
      return;
    }
    if (!force && _at != null && DateTime.now().difference(_at!).inMinutes < 30) return;
    try {
      final r = await http
          .get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${a.weatherLat}&longitude=${a.weatherLon}&current=weather_code,is_day,temperature_2m'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final c = (jsonDecode(r.body) as Map)['current'] as Map;
      final code = (c['weather_code'] as num).toInt();
      now = WeatherNow(_sky(code), c['is_day'] == 1, (c['temperature_2m'] as num).toDouble(), code);
      _at = DateTime.now();
      notifyListeners();
    } catch (_) {}
  }

  /// Cerca le città con questo nome.
  static Future<List<(String, double, double)>> search(String q) async {
    final r = await http.get(Uri.parse('https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeQueryComponent(q)}&count=6&language=it'));
    if (r.statusCode != 200) return [];
    final res = ((jsonDecode(r.body) as Map)['results'] as List?) ?? const [];
    return [
      for (final x in res.cast<Map>())
        (
          [x['name'], x['admin1'], x['country']].whereType<String>().toSet().join(', '),
          (x['latitude'] as num).toDouble(),
          (x['longitude'] as num).toDouble(),
        ),
    ];
  }
}
