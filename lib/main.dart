import 'package:flutter/material.dart';
import 'package:folha_certa/screens/home_shell.dart';
import 'package:folha_certa/screens/login_screen.dart';
import 'package:folha_certa/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FolhaCertaApp());
}

class FolhaCertaApp extends StatelessWidget {
  const FolhaCertaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Folha Certa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: LoginScreen.route,
      routes: {
        LoginScreen.route: (_) => const LoginScreen(),
        HomeShell.route: (_) => const HomeShell(),
      },
    );
  }
}
