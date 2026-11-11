/// Un capitolo può essere diviso in più file dentro l'EPUB.
class Chapter {
  final String title;
  final List<String> hrefs;
  const Chapter(this.title, this.hrefs);
  String get href => hrefs.first;

  Map<String, dynamic> toJson() => {'t': title, 'hs': hrefs};
  factory Chapter.fromJson(Map<String, dynamic> j) =>
      Chapter(j['t'] as String, j['hs'] != null ? (j['hs'] as List).cast<String>() : [j['h'] as String]);
}

class Book {
  final String id;
  String title;
  String author;
  String? series;
  double? seriesIndex;
  final String filePath;
  String? coverPath;
  List<Chapter> chapters;
  List<int>? chapterChars; // lunghezza del testo di ogni capitolo (per il tempo stimato)
  int format; // 3 = capitoli raggruppati dall'indice + entità decodificate

  // Dorso
  int spineColor;
  int spineTextColor;
  int coverSpineColor; // colori calcolati dalla copertina, per tornare a "Dalla copertina"
  int coverSpineTextColor;
  String spinePalette; // 'cover' oppure nome di una palette
  String spineStyle; // Tomo, Classico, Liscio, Nervato, Grimorio
  double spineHeight; // 0.7 – 1.1
  double spineWidth; // 0.7 – 1.3

  // Progressi
  int lastChapter;
  double lastOffset; // 0..1 nel capitolo
  final DateTime addedAt;
  DateTime? lastReadAt;

  Book({
    required this.id,
    required this.title,
    required this.author,
    this.series,
    this.seriesIndex,
    required this.filePath,
    this.coverPath,
    required this.chapters,
    this.format = 3,
    this.chapterChars,
    required this.spineColor,
    required this.spineTextColor,
    required this.coverSpineColor,
    required this.coverSpineTextColor,
    this.spinePalette = 'cover',
    this.spineStyle = 'Tomo',
    this.spineHeight = 1.0,
    this.spineWidth = 1.0,
    this.lastChapter = 0,
    this.lastOffset = 0,
    required this.addedAt,
    this.lastReadAt,
  });

  double get progress {
    if (chapters.isEmpty) return 0;
    return ((lastChapter + lastOffset) / chapters.length).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'series': series,
        'seriesIndex': seriesIndex,
        'filePath': filePath,
        'coverPath': coverPath,
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'format': format,
        'chapterChars': chapterChars,
        'spineColor': spineColor,
        'spineTextColor': spineTextColor,
        'coverSpineColor': coverSpineColor,
        'coverSpineTextColor': coverSpineTextColor,
        'spinePalette': spinePalette,
        'spineStyle': spineStyle,
        'spineHeight': spineHeight,
        'spineWidth': spineWidth,
        'lastChapter': lastChapter,
        'lastOffset': lastOffset,
        'addedAt': addedAt.toIso8601String(),
        'lastReadAt': lastReadAt?.toIso8601String(),
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        author: (j['author'] as String?) ?? '',
        series: j['series'] as String?,
        seriesIndex: (j['seriesIndex'] as num?)?.toDouble(),
        filePath: j['filePath'] as String,
        coverPath: j['coverPath'] as String?,
        chapters: ((j['chapters'] as List?) ?? []).map((c) => Chapter.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
        format: (j['format'] as int?) ?? 1,
        chapterChars: (j['chapterChars'] as List?)?.cast<int>(),
        spineColor: j['spineColor'] as int,
        spineTextColor: j['spineTextColor'] as int,
        coverSpineColor: (j['coverSpineColor'] as int?) ?? j['spineColor'] as int,
        coverSpineTextColor: (j['coverSpineTextColor'] as int?) ?? j['spineTextColor'] as int,
        spinePalette: (j['spinePalette'] as String?) ?? 'cover',
        spineStyle: (j['spineStyle'] as String?) ?? 'Tomo',
        spineHeight: ((j['spineHeight'] as num?) ?? 1).toDouble(),
        spineWidth: ((j['spineWidth'] as num?) ?? 1).toDouble(),
        lastChapter: (j['lastChapter'] as int?) ?? 0,
        lastOffset: ((j['lastOffset'] as num?) ?? 0).toDouble(),
        addedAt: DateTime.tryParse((j['addedAt'] as String?) ?? '') ?? DateTime.now(),
        lastReadAt: DateTime.tryParse((j['lastReadAt'] as String?) ?? ''),
      );
}

class SpinePalette {
  final String name;
  final int bg;
  final int text;
  const SpinePalette(this.name, this.bg, this.text);

  static const presets = [
    SpinePalette('Bordeaux', 0xFF7A1E2E, 0xFFC9A55A),
    SpinePalette('Foresta', 0xFF2F4A3A, 0xFFE6D3A3),
    SpinePalette('Mezzanotte', 0xFF26364A, 0xFFD8E0EA),
    SpinePalette('Reale', 0xFF4A2F63, 0xFFE2C46B),
    SpinePalette('Grimorio', 0xFF2B2B2B, 0xFFC9A55A),
    SpinePalette('Pelle', 0xFF8A4A22, 0xFFF1D9A8),
    SpinePalette('Pergamena', 0xFFE6D3A3, 0xFF5A3A22),
    SpinePalette('Deserto', 0xFFC08A3E, 0xFF3A2416),
  ];

  static const styles = ['Tomo', 'Classico', 'Liscio', 'Nervato', 'Grimorio'];
}
