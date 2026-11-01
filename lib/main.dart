import "package:flutter/material.dart";

import "history_store.dart";
import "settings_store.dart";
import "ui/copy_page.dart";
import "ui/history_page.dart";
import "ui/settings_page.dart";
import "ui/splash_page.dart";
import "ui/sync_page.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SincroApp());
}

class SincroApp extends StatefulWidget {
  const SincroApp({super.key});

  @override
  State<SincroApp> createState() => _SincroAppState();
}

class _SincroAppState extends State<SincroApp> {
  SettingsStore? settings;
  final history = HistoryStore();
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    SettingsStore.load().then((value) {
      if (mounted) setState(() => settings = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loaded = settings;
    return MaterialApp(
      title: "SincroLocal",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1C6B45)),
        scaffoldBackgroundColor: const Color(0xFFF4F7F2),
        useMaterial3: true,
      ),
      home: loaded == null || !_splashDone
          ? SplashPage(onDone: () => setState(() => _splashDone = true), onAbout: () {})
          : HomePage(settings: loaded, history: history),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.settings, required this.history});

  final SettingsStore settings;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SincroLocal")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Sem nuvem. Os arquivos ficam neste aparelho ou vão direto para o outro, na mesma rede."),
          const SizedBox(height: 20),
          ListTile(title: const Text("Copiar para o cartão SD"), onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => CopyPage(settings: settings, history: history)));
          }),
          ListTile(title: const Text("Sincronizar com o outro aparelho"), onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => SyncPage(settings: settings, history: history)));
          }),
          ListTile(title: const Text("Histórico"), onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryPage(history: history)));
          }),
        ],
      ),
    );
  }
}
