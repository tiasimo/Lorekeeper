import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const LorekeeperApp());
}

class LorekeeperApp extends StatelessWidget {
  const LorekeeperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lorekeeper',
      debugShowCheckedModeBanner: false,
      theme: LK.theme(),
      home: const SplashScreen(),
    );
  }
}
