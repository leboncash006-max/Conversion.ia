import 'package:flutter/material.dart';

import 'data.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const DebatApp());
}

class DebatApp extends StatelessWidget {
  const DebatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Débat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3949AB),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3949AB),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Store.profile == null ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
