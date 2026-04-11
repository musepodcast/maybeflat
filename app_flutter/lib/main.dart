import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'screens/admin_screen.dart';
import 'screens/home_screen.dart';
import 'services/client_identity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ClientIdentity.instance.initialize();
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
      home: _resolveHome(),
    );
  }

  Widget _resolveHome() {
    final path = Uri.base.path;
    if (kIsWeb && (path == '/admin' || path.startsWith('/admin/'))) {
      return const AdminScreen();
    }
    return const HomeScreen();
  }
}
