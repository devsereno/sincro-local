import "package:flutter/material.dart";

import "../device_bridge.dart";
import "hotspot_guide.dart";

class FlowPage extends StatefulWidget {
  const FlowPage({super.key, required this.onReceive, required this.onSend});

  final VoidCallback onReceive;
  final VoidCallback onSend;

  @override
  State<FlowPage> createState() => _FlowPageState();
}

class _FlowPageState extends State<FlowPage> with SingleTickerProviderStateMixin {
  String? _method;
  int _step = 0;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06140C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("SincroLocal"),
        leading: _step > 0
            ? IconButton(onPressed: () => setState(() => _step--), icon: const Icon(Icons.arrow_back))
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _step == 0 ? _choice() : _method == "hotspot" ? _hotspot() : _wifi(),
      ),
    );
  }

  Widget _choice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.sync, size: 72, color: Color(0xFF1F8A57)),
        const SizedBox(height: 16),
        const Text("Como deseja se conectar?", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text("Escolha o método de conexão", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 32),
        _Card(
          icon: Icons.wifi,
          title: "Wi-Fi",
          subtitle: "Rede de casa",
          onTap: () => setState(() {
            _method = "wifi";
            _step = 1;
          }),
        ),
        const SizedBox(height: 12),
        _Card(
          icon: Icons.wifi_tethering,
          title: "Hotspot",
          subtitle: "Conexão rápida",
          onTap: () => setState(() {
            _method = "hotspot";
            _step = 1;
          }),
        ),
      ],
    );
  }

  Widget _hotspot() {
    return FutureBuilder<String>(
      future: HotspotGuide.detect(),
      builder: (context, snapshot) {
        final brand = snapshot.data ?? "outro";
        return ListView(
          children: [
            const Text("Tutorial do Hotspot", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text("Siga o passo a passo para ativar o ponto de acesso.", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            HotspotGuide(brand: brand),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _step = 2),
              child: const Text("Entendi, continuar"),
            ),
          ],
        );
      },
    );
  }

  Widget _wifi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Os dois no mesmo Wi-Fi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text("Quem recebe mostra o QR. Quem envia lê e já entra.", style: TextStyle(color: Colors.white70)),
        const Spacer(),
        FilledButton.icon(onPressed: widget.onReceive, icon: const Icon(Icons.qr_code_2), label: const Text("Receber")),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: widget.onSend, icon: const Icon(Icons.photo_camera_outlined), label: const Text("Enviar")),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D2418),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1F8A57), width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF1F8A57), size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(subtitle, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF1F8A57)),
            ],
          ),
        ),
      ),
    );
  }
}
