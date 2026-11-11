import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'library_store.dart';
import 'secrets.dart';

class GeminiError implements Exception {
  final String message;
  GeminiError(this.message);
  @override
  String toString() => message;
}

/// Chiamate a Gemini (piano gratuito). Ritenta da solo se si supera il limite al minuto.
class Gemini {
  static Future<String> ask(String prompt, {int maxTokens = 700, double temperature = 0.3, bool json = false}) async {
    final key = await Secrets.geminiKey();
    if (key == null || key.isEmpty) {
      throw GeminiError('Manca la chiave API di Gemini: aggiungila in Impostazioni.');
    }
    final model = LibraryStore.I.app.geminiModel;
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
        if (json) 'responseMimeType': 'application/json',
      },
    });
    for (var attempt = 0; attempt < 4; attempt++) {
      http.Response r;
      try {
        r = await http
            .post(url, headers: {'Content-Type': 'application/json', 'x-goog-api-key': key}, body: body)
            .timeout(const Duration(seconds: 60));
      } on TimeoutException {
        throw GeminiError('Gemini non risponde: controlla la connessione.');
      } catch (_) {
        throw GeminiError('Nessuna connessione a internet.');
      }
      if (r.statusCode == 429 || r.statusCode == 503) {
        await Future.delayed(Duration(seconds: 8 * (attempt + 1)));
        continue;
      }
      if (r.statusCode == 400 || r.statusCode == 403) {
        throw GeminiError('Chiave API non valida o modello non disponibile (${r.statusCode}).');
      }
      if (r.statusCode != 200) {
        throw GeminiError('Errore di Gemini (${r.statusCode}).');
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final cands = (j['candidates'] as List?) ?? const [];
      if (cands.isEmpty) throw GeminiError('Gemini non ha dato una risposta.');
      final parts = (((cands.first as Map)['content'] as Map?)?['parts'] as List?) ?? const [];
      final text = parts.map((p) => (p as Map)['text'] ?? '').join().trim();
      if (text.isEmpty) throw GeminiError('Gemini non ha dato una risposta.');
      return text;
    }
    throw GeminiError('Limite di richieste raggiunto: riprova tra un minuto.');
  }
}
