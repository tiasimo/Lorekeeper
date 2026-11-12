import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'services/ambience.dart';
import 'services/crash_log.dart';
import 'services/drive_sync.dart';
import 'services/library_store.dart';
import 'theme.dart';
import 'tv/tv_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await detectTv();
  await CrashLog.init();
  final flutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    CrashLog.add('${details.exceptionAsString()} @ ${details.stack.toString().split('\n').take(4).join(' | ')}');
    flutterError?.call(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (e, st) {
    CrashLog.add('$e @ ${st.toString().split('\n').take(4).join(' | ')}');
    return true;
  };
  if (tvMode) {
    // la TV ha poca memoria: meno immagini tenute in RAM
    PaintingBinding.instance.imageCache
      ..maximumSize = 60
      ..maximumSizeBytes = 40 << 20;
  }
  // se una schermata va in errore, mostro il motivo invece di un riquadro grigio
  ErrorWidget.builder = (details) => Container(
        color: const Color(0xFF2A1E1A),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: Text('Qualcosa è andato storto qui:\n${details.exceptionAsString()}',
            textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF3E7CF), fontSize: 13, decoration: TextDecoration.none)),
      );
  final prefs = await SharedPreferences.getInstance();
  LibraryStore.I.appTheme = prefs.getString('appTheme') ?? 'Sistema';
  runApp(const LorekeeperApp());
}

class LorekeeperApp extends StatefulWidget {
  const LorekeeperApp({super.key});
  @override
  State<LorekeeperApp> createState() => _LorekeeperAppState();
}

class _LorekeeperAppState extends State<LorekeeperApp> with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LibraryStore.I.addListener(_onStore);
    LK.dark = _wantDark();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LibraryStore.I.removeListener(_onStore);
    super.dispose();
  }

  bool _wantDark() {
    // sulla TV, salvo scelta diversa, sempre il tema scuro ("home cinema")
    if (tvMode && LibraryStore.I.appTheme == 'Sistema') return true;
    switch (LibraryStore.I.appTheme) {
      case 'Notte':
        return true;
      case 'Giorno':
        return false;
      default:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
  }

  void _onStore() => _refresh();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) Ambience.I.pause();
    if (state == AppLifecycleState.resumed) Ambience.I.resume();
    if (!DriveSync.I.enabled) return;
    if (state == AppLifecycleState.paused) {
      // sulla TV si segna "da caricare" solo quando cambiano davvero gli anime
      if (tvMode) {
        DriveSync.I.sync(quiet: true);
      } else {
        DriveSync.I.markDirty().then((_) => DriveSync.I.sync(quiet: true));
      }
    } else if (state == AppLifecycleState.resumed) {
      DriveSync.I.sync(quiet: true);
    }
  }

  @override
  void didChangePlatformBrightness() => _refresh();

  void _refresh() {
    final d = _wantDark();
    if (d == LK.dark) return;
    LK.dark = d;
    setState(() {});
    // I colori sono letti direttamente: ridisegno tutta l'interfaccia.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _navKey.currentContext;
      if (ctx == null) return;
      void rebuild(Element e) {
        e.markNeedsBuild();
        e.visitChildren(rebuild);
      }

      (ctx as Element).visitChildren(rebuild);
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: LK.dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: LK.paper,
      systemNavigationBarIconBrightness: LK.dark ? Brightness.light : Brightness.dark,
    ));
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Lorekeeper',
      debugShowCheckedModeBanner: false,
      theme: tvMode ? LK.tvTheme() : LK.theme(),
      // sulla TV i testi sono più grandi, perché si guarda da lontano
      home: const SplashScreen(),
    );
  }
}
