# Lorekeeper

*Il custode delle tue storie.* Lettore di novel EPUB per Android, con scaffale illustrato, dorsi generati dalle copertine e (in arrivo) una wiki dei personaggi costruita con Gemini man mano che leggi.

## Come ottenere l'APK

Ogni push su `main` avvia la build in **Actions → Build APK**. A fine build scarica l'artifact **Lorekeeper-apk** e installa `app-release.apk`.

L'APK è firmato sempre con la stessa chiave (`android-signing/debug.keystore`), così ogni nuova versione si installa sopra la precedente senza perdere libreria e progressi.

## Struttura

- `lib/services/epub.dart` – lettura dei file EPUB (metadati, serie, indice, copertina, capitoli)
- `lib/services/cover_colors.dart` – colori del dorso calcolati dalla copertina
- `lib/services/library_store.dart` – libreria, scaffale, progressi e statistiche (salvati in locale)
- `lib/screens/` – caricamento con lanterna, libreria, scheda novel, lettore, modifica dorso, impostazioni
- `assets/dividers/` – le 32 illustrazioni dei divisori dello scaffale

La cartella `android/` non è nel repository: la genera il workflow con `flutter create`.

## Roadmap

- [x] Fase 1 – scaffale, import EPUB, dorsi automatici e modificabili, lettore con temi, diario di lettura
- [ ] Fase 2 – wiki con Gemini (personaggi, luoghi, termini) condivisa tra i volumi della serie, anti-spoiler, schede con foto, grafo delle relazioni, "chi era questo?" toccando un nome, riassunto dei capitoli precedenti
- [ ] Fase 3 – evidenziazioni e note, lettura ad alta voce, tasti volume, filtro luce calda, backup, widget "continua a leggere"
