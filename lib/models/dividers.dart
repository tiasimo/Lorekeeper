class DividerArt {
  final String id;
  final String name;
  const DividerArt(this.id, this.name);
  String get asset => 'assets/dividers/$id.webp';

  static const all = [
    DividerArt('elendrath', 'Guglia di Elendrath'),
    DividerArt('kazmorr', 'Porta di Kazmorr'),
    DividerArt('corvogrigio', 'Rocca di Corvogrigio'),
    DividerArt('drago', 'Torre del Drago Assopito'),
    DividerArt('brinaluce', 'Soglia di Brinaluce'),
    DividerArt('albamare', 'Faro di Albamare'),
    DividerArt('vellumbra', 'Osservatorio di Vellumbra'),
    DividerArt('quillon', 'Bottega di Mastra Quillon'),
    DividerArt('orrinvel', 'Avamposto di Orrin-Vel'),
    DividerArt('corvina', 'La Corvina Stellare'),
    DividerArt('rosenhallow', 'Villa di Rosenhallow'),
    DividerArt('tempo', 'Torre del Tempo Spezzato'),
    DividerArt('crepuscolo', 'Portale del Crepuscolo'),
    DividerArt('kuroshiro', 'Dojo di Kuroshiro'),
    DividerArt('kirihana', 'Ponte di Kirihana'),
    DividerArt('lanterne', 'Locanda delle Cento Lanterne'),
    DividerArt('azzurro', 'Varco Azzurro'),
    DividerArt('obelisco', 'Obelisco dell\'Ombra'),
    DividerArt('thalassa', 'Tempio di Thalassa'),
    DividerArt('ninfe', 'Fonte delle Ninfe'),
    DividerArt('riflettori', 'Città dei Riflettori'),
    DividerArt('ultimofuoco', 'Bivacco dell\'Ultimo Fuoco'),
    DividerArt('altoforte', 'Accademia Altoforte'),
    DividerArt('tettoeroico', 'Tetti di Città Eroica'),
    DividerArt('grimori', 'Torre dei Grimori'),
    DividerArt('noctalis', 'Basilica di Noctalis'),
    DividerArt('mezzanotte', 'Campanile della Mezzanotte'),
    DividerArt('scrittoio', 'Scrittoio del Silenzio'),
    DividerArt('stellaforte', 'Torre Stellaforte'),
    DividerArt('fucina', 'Fucina delle Stelle'),
    DividerArt('ombragrigia', 'Ombragrigia'),
    DividerArt('farosolare', 'Torre del Faro Solare'),
  ];

  static DividerArt? byId(String id) {
    for (final d in all) {
      if (d.id == id) return d;
    }
    return null;
  }
}
