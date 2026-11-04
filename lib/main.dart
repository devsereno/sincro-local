import "package:flutter/material.dart";

import "device_bridge.dart";
import "history_store.dart";
import "settings_store.dart";
import "ui/brand_mark.dart";
import "ui/copy_page.dart";
import "ui/history_page.dart";
import "ui/originals_page.dart";
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeviceBridge.requestMediaAccess();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loaded = settings;
    return MaterialApp(
      title: "SincroLocal",
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: loaded == null || !_splashDone
          ? SplashPage(onDone: () => setState(() => _splashDone = true), onAbout: () {})
          : HomePage(settings: loaded, history: history),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1F8A57), brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.settings, required this.history});

  final SettingsStore settings;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SincroLocal"),
        actions: [
          IconButton(
            tooltip: "Ajustes",
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(settings: settings)));
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const BrandMark(size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Sem nuvem. Os arquivos ficam neste aparelho ou vão direto para o outro, na mesma rede.",
                  style: TextStyle(fontSize: 15, height: 1.35, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Action(
            icon: Icons.sd_card,
            title: "Copiar para o cartão SD",
            subtitle: "Deste aparelho. Híbrido, só SD ou só interna.",
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CopyPage(settings: settings, history: history)),
              );
            },
          ),
          _Action(
            icon: Icons.sync_alt,
            title: "Sincronizar com o outro aparelho",
            subtitle: "Quem recebe escolhe o destino e a reserva.",
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SyncPage(settings: settings, history: history)),
              );
            },
          ),
          _Action(
            icon: Icons.delete_outline,
            title: "Apagar originais",
            subtitle: "Só o que já foi confirmado 100%. Um a um ou tudo.",
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => OriginalsPage(history: history)));
            },
          ),
          _Action(
            icon: Icons.history,
            title: "Histórico",
            subtitle: "Transferências concluídas ou interrompidas.",
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryPage(history: history)));
            },
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: scheme.onPrimaryContainer, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
