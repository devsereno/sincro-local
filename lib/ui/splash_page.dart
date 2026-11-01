import "dart:async";

import "package:flutter/material.dart";

import "brand_mark.dart";

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onDone, required this.onAbout});

  final VoidCallback onDone;
  final VoidCallback onAbout;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _timer;
  double _progress = 0;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || _holding) return;
      setState(() => _progress = (_progress + 0.01).clamp(0, 1));
      if (_progress >= 1) {
        timer.cancel();
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _about() {
    setState(() => _holding = true);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ricardo Works"),
        content: const Text(
          "SincroLocal copia arquivos da memória interna para o cartão SD deste aparelho e também envia para outro aparelho na mesma rede Wi-Fi. Não usa nuvem.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Fechar"),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) setState(() => _holding = false);
    });
    widget.onAbout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF0E3A26)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC0E3A26), Color(0x330E3A26), Color(0xE60E3A26)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                children: [
                  const Text(
                    "SincroLocal",
                    style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Desenvolvedor: RICARDO WORKS",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Sistemas parrudos para problemas reais.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  const BrandMark(size: 168),
                  const Spacer(),
                  const Text("Carregando...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF9FE0BC),
                      foregroundColor: const Color(0xFF10241A),
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: _about,
                    child: const Text(
                      "Saber Mais & Portfólio Ricardo Works",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Inovação para um futuro digital e verde.",
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
