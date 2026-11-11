/// Sillabazione italiana semplificata: inserisce trattini "morbidi" (U+00AD)
/// dove la parola può andare a capo. Il testo resta identico a schermo
/// finché la riga non viene spezzata.
class Hyphen {
  static const soft = '­';
  static const _vowels = 'aeiouàèéìíòóùúAEIOUÀÈÉÌÍÒÓÙÚ';
  static const _together = {
    'bl', 'br', 'cl', 'cr', 'dr', 'fl', 'fr', 'gl', 'gr', 'pl', 'pr', 'tr', 'vr', //
    'ch', 'gh', 'gn', 'sc', 'qu', 'ps', 'pn', 'th', 'ph', 'sh', 'wr', 'kr', 'kl',
  };
  static final _word = RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ]{7,}");

  static bool _isV(String c) => _vowels.contains(c);

  static String apply(String text) => text.replaceAllMapped(_word, (m) => _word2(m[0]!));

  static String _word2(String w) {
    final cuts = <int>[];
    var i = 0;
    while (i < w.length) {
      if (!_isV(w[i])) {
        i++;
        continue;
      }
      // fine del gruppo vocalico
      var j = i;
      while (j < w.length && _isV(w[j])) {
        j++;
      }
      // gruppo di consonanti
      var k = j;
      while (k < w.length && !_isV(w[k])) {
        k++;
      }
      if (k >= w.length) break; // consonanti finali: nessun taglio
      final cons = w.substring(j, k).toLowerCase();
      int cut;
      if (cons.length <= 1) {
        cut = j;
      } else if (cons.length == 2) {
        cut = (_together.contains(cons) || cons[0] == 's') ? j : j + 1;
      } else {
        final tail = cons.substring(cons.length - 2);
        cut = cons[0] == 's' ? j : (_together.contains(tail) ? k - 2 : j + 1);
      }
      if (cut >= 2 && w.length - cut >= 3) cuts.add(cut);
      i = k;
    }
    if (cuts.isEmpty) return w;
    final b = StringBuffer();
    var last = 0;
    for (final c in cuts) {
      b.write(w.substring(last, c));
      b.write(soft);
      last = c;
    }
    b.write(w.substring(last));
    return b.toString();
  }
}
