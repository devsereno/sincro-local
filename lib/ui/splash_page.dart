import "dart:async";

import "package:flutter/material.dart";

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onDone, required this.onAbout});

  final VoidCallback onDone;
  final VoidCallback onAbout;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  Timer? _timer;
  double _progress = 0;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
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
    _spin.dispose();
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar")),
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
                  const Text("SincroLocal", style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  RotationTransition(turns: _spin, child: const SizedBox(width: 180, height: 180, child: _Pinwheel())),
                  const Spacer(),
                  const Text("Carregando...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _progress, minHeight: 2, color: Colors.white, backgroundColor: Colors.white24),
                  const SizedBox(height: 28),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF9FE0BC), foregroundColor: const Color(0xFF10241A), minimumSize: const Size.fromHeight(56)),
                    onPressed: _about,
                    child: const Text("Saber Mais & Portfólio Ricardo Works", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800)),
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

class _Pinwheel extends StatelessWidget {
  const _Pinwheel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        for (var i = 0; i < 8; i++)
          Transform.rotate(
            angle: i * 0.785,
            child: Transform.translate(
              offset: const Offset(0, -58),
              child: Transform.rotate(
                angle: i.isEven ? -0.25 : 0.18,
                child: Container(
                  width: 36,
                  height: 52,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
