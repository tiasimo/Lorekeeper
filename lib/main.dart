import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'services/ambience.dart';
import 'services/drive_sync.dart';
import 'services/library_store.dart';
import 'theme.dart';
import 'tv/tv_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await detectTv();
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
      DriveSync.I.markDirty().then((_) => DriveSync.I.sync(quiet: true));
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
      theme: LK.theme(),
      home: const SplashScreen(),
    );
  }
}
