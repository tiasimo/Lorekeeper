import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// true quando l'app gira su una Android TV (interfaccia da telecomando).
bool tvMode = false;

Future<void> detectTv() async {
  if (!Platform.isAndroid) return;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    tvMode = info.systemFeatures.contains('android.software.leanback') || info.systemFeatures.contains('android.hardware.type.television');
  } catch (_) {}
}
