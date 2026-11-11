import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Stati della lista AniList, con il nome in italiano.
const alStatuses = {
  'CURRENT': 'In lettura',
  'PLANNING': 'Da leggere',
  'COMPLETED': 'Completato',
  'PAUSED': 'In pausa',
  'DROPPED': 'Abbandonato',
  'REPEATING': 'Rilettura',
};

class AlMedia {
  final int id;
  final String title;
  final String? english, romaji, cover;
  final int? chapters, year;
  final String? format, status;
  AlMedia({required this.id, required this.title, this.english, this.romaji, this.cover, this.chapters, this.year, this.format, this.status});

  factory AlMedia.fromJson(Map j) {
    final t = (j['title'] as Map?) ?? const {};
    return AlMedia(
      id: j['id'] as int,
      title: (t['userPreferred'] ?? t['romaji'] ?? t['english'] ?? '') as String,
      english: t['english'] as String?,
      romaji: t['romaji'] as String?,
      cover: ((j['coverImage'] as Map?)?['large'] ?? (j['coverImage'] as Map?)?['medium']) as String?,
      chapters: j['chapters'] as int?,
      year: (j['startDate'] as Map?)?['year'] as int?,
      format: j['format'] as String?,
      status: j['status'] as String?,
    );
  }

  /// Titoli con cui cercarlo nelle sorgenti.
  List<String> get titles => {title, if (english != null) english!, if (romaji != null) romaji!}.where((t) => t.isNotEmpty).toList();
}

class AlEntry {
  final AlMedia media;
  String status;
  int progress;
  double score; // 0–10
  AlEntry(this.media, this.status, this.progress, this.score);
}

/// Sincronizzazione con AniList: accesso, lista manga, progressi, stato e voto.
class AniList extends ChangeNotifier {
  AniList._();
  static final I = AniList._();

  static const _secure = FlutterSecureStorage();
  static const redirect = 'lorekeeper://anilist';
  static const _api = 'https://graphql.anilist.co';

  String? _token;
  int? userId;
  String? userName, avatar;
  bool _loaded = false;

  bool get loggedIn => _token != null && userId != null;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _token = await _secure.read(key: 'anilist_token');
    final p = await SharedPreferences.getInstance();
    userId = p.getInt('anilist.user');
    userName = p.getString('anilist.name');
    avatar = p.getString('anilist.avatar');
    notifyListeners();
  }

  Future<String?> clientId() async => (await SharedPreferences.getInstance()).getString('anilist.client');

  Future<void> setClientId(String id) async => (await SharedPreferences.getInstance()).setString('anilist.client', id.trim());

  /// Accesso con il browser (flusso "implicit" di AniList: niente segreti nell'app).
  Future<void> login() async {
    final id = await clientId();
    if (id == null || id.isEmpty) throw Exception('Inserisci prima l\'ID client di AniList');
    final url = 'https://anilist.co/api/v2/oauth/authorize?client_id=$id&response_type=token';
    final result = await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: 'lorekeeper');
    final frag = Uri.parse(result).fragment;
    final token = Uri.splitQueryString(frag)['access_token'];
    if (token == null || token.isEmpty) throw Exception('AniList non ha restituito il token');
    _token = token;
    final v = await _query('query { Viewer { id name avatar { medium } } }');
    final viewer = v['Viewer'] as Map;
    userId = viewer['id'] as int;
    userName = viewer['name'] as String?;
    avatar = (viewer['avatar'] as Map?)?['medium'] as String?;
    await _secure.write(key: 'anilist_token', value: token);
    final p = await SharedPreferences.getInstance();
    await p.setInt('anilist.user', userId!);
    if (userName != null) await p.setString('anilist.name', userName!);
    if (avatar != null) await p.setString('anilist.avatar', avatar!);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    userId = null;
    userName = null;
    avatar = null;
    await _secure.delete(key: 'anilist_token');
    final p = await SharedPreferences.getInstance();
    await p.remove('anilist.user');
    await p.remove('anilist.name');
    await p.remove('anilist.avatar');
    notifyListeners();
  }

  Future<Map> _query(String q, [Map<String, dynamic>? vars]) async {
    final r = await http.post(
      Uri.parse(_api),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'query': q, 'variables': vars ?? {}}),
    );
    final j = jsonDecode(r.body) as Map;
    if (r.statusCode == 401 || r.statusCode == 400 && '${j['errors']}'.contains('Invalid token')) {
      await logout();
      throw Exception('Accesso ad AniList scaduto: rientra');
    }
    if (j['errors'] != null) throw Exception((j['errors'] as List).map((e) => (e as Map)['message']).join(', '));
    return j['data'] as Map;
  }

  static const _mediaFields = 'id title { userPreferred romaji english } coverImage { large medium } chapters format status startDate { year }';

  Future<List<AlMedia>> search(String text) async {
    final d = await _query('query (\$s: String) { Page(perPage: 15) { media(search: \$s, type: MANGA, sort: SEARCH_MATCH) { $_mediaFields } } }', {'s': text});
    return ((d['Page'] as Map)['media'] as List).map((m) => AlMedia.fromJson(m as Map)).toList();
  }

  /// La tua lista manga, divisa per stato.
  Future<List<AlEntry>> myList() async {
    if (!loggedIn) return [];
    final d = await _query(
      'query (\$u: Int) { MediaListCollection(userId: \$u, type: MANGA) { lists { entries { status progress score(format: POINT_10_DECIMAL) media { $_mediaFields } } } } }',
      {'u': userId},
    );
    final out = <AlEntry>[];
    for (final l in ((d['MediaListCollection'] as Map)['lists'] as List)) {
      for (final e in ((l as Map)['entries'] as List)) {
        final m = e as Map;
        out.add(AlEntry(AlMedia.fromJson(m['media'] as Map), m['status'] as String? ?? 'PLANNING', m['progress'] as int? ?? 0, ((m['score'] as num?) ?? 0).toDouble()));
      }
    }
    return out;
  }

  /// Voce della tua lista per un manga (null se non c'è).
  Future<AlEntry?> entry(int mediaId) async {
    if (!loggedIn) return null;
    final d = await _query('query (\$id: Int) { Media(id: \$id) { $_mediaFields mediaListEntry { status progress score(format: POINT_10_DECIMAL) } } }', {'id': mediaId});
    final m = d['Media'] as Map;
    final e = m['mediaListEntry'] as Map?;
    if (e == null) return null;
    return AlEntry(AlMedia.fromJson(m), e['status'] as String? ?? 'PLANNING', e['progress'] as int? ?? 0, ((e['score'] as num?) ?? 0).toDouble());
  }

  Future<void> save(int mediaId, {String? status, int? progress, double? score}) async {
    await _query(
      'mutation (\$id: Int, \$st: MediaListStatus, \$p: Int, \$s: Int) { SaveMediaListEntry(mediaId: \$id, status: \$st, progress: \$p, scoreRaw: \$s) { id } }',
      {
        'id': mediaId,
        if (status != null) 'st': status,
        if (progress != null) 'p': progress,
        if (score != null) 's': (score * 10).round(),
      },
    );
  }
}
