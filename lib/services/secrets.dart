import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Secrets {
  static const _s = FlutterSecureStorage();
  static Future<String?> geminiKey() => _s.read(key: 'gemini_key');
  static Future<void> setGeminiKey(String? v) =>
      v == null || v.trim().isEmpty ? _s.delete(key: 'gemini_key') : _s.write(key: 'gemini_key', value: v.trim());
}
