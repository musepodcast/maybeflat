import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const MaybeflatApp());
}

class MaybeflatApp extends StatelessWidget {
  const MaybeflatApp({super.key});

  @override
  Widget build(BuildContext context) {
    const sand = Color(0xFFF1E7D0);
    const ink = Color(0xFF112A46);
    const sea = Color(0xFF2E557A);
    final scheme = ColorScheme.fromSeed(
      seedColor: sea,
      brightness: Brightness.light,
    ).copyWith(
      primary: ink,
      surface: sand,
    );

    return MaterialApp(
      title: 'Maybeflat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: sand,
        cardTheme: const CardThemeData(
          color: Color(0xFFF8F3E8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
