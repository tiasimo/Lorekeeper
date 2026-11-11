import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Promemoria giornaliero per l'obiettivo di lettura.
class Reminders {
  static final _n = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _id = 7;

  static Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final off = DateTime.now().timeZoneOffset.inMilliseconds;
      tz.Location? pick;
      try {
        final rome = tz.getLocation('Europe/Rome');
        if (rome.currentTimeZone.offset == off) pick = rome;
      } catch (_) {}
      pick ??= tz.timeZoneDatabase.locations.values.firstWhere((l) => l.currentTimeZone.offset == off, orElse: () => tz.UTC);
      tz.setLocalLocation(pick);
    } catch (_) {}
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _n.initialize(const InitializationSettings(android: android));
    _ready = true;
  }

  static Future<bool> schedule(int hour, int minute, int goalMinutes) async {
    try {
      await _init();
      final android = _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? true;
      await _n.cancel(_id);
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await _n.zonedSchedule(
        _id,
        'È l\'ora della lettura',
        'Il tuo obiettivo di oggi: $goalMinutes minuti. La lanterna è accesa.',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails('reminder', 'Promemoria lettura', channelDescription: 'Promemoria giornaliero per leggere'),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return granted;
    } catch (e) {
      debugPrint('Promemoria non programmato: $e');
      return false;
    }
  }

  static Future<void> cancel() async {
    try {
      await _init();
      await _n.cancel(_id);
    } catch (_) {}
  }
}
