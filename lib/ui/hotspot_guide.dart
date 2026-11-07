import "package:flutter/material.dart";

import "../device_bridge.dart";

class HotspotGuide extends StatelessWidget {
  const HotspotGuide({super.key, required this.brand});

  final String brand;

  static Future<String> detect() async {
    final model = (await DeviceBridge.deviceModel()).toLowerCase();
    if (model.contains("samsung") || model.contains("sm-")) return "samsung";
    if (model.contains("xiaomi") || model.contains("redmi") || model.contains("poco")) return "xiaomi";
    if (model.contains("motorola") || model.contains("moto")) return "motorola";
    if (model.contains("pixel") || model.contains("google")) return "pixel";
    if (model.contains("oppo") || model.contains("realme") || model.contains("honor")) return "oppo";
    return "outro";
  }

  String get _path {
    switch (brand) {
      case "samsung":
        return "Configurações → Conexões → Ponto de acesso móvel e roteamento";
      case "xiaomi":
        return "Configurações → Conexão e compartilhamento → Ponto de acesso pessoal";
      case "motorola":
      case "pixel":
        return "Configurações → Rede e internet → Ponto de acesso e roteamento";
      case "oppo":
        return "Configurações → Conexão e compartilhamento → Ponto de acesso pessoal";
      default:
        return "Configurações → Rede e internet → Ponto de acesso";
    }
  }

  String get _name {
    switch (brand) {
      case "samsung":
        return "Ponto de acesso móvel";
      case "xiaomi":
      case "oppo":
        return "Ponto de acesso pessoal";
      default:
        return "Ponto de acesso Wi-Fi";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Ligue o ponto de acesso neste aparelho", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        Text("1. Abra $_path"),
        const SizedBox(height: 8),
        Text("2. Ligue $_name"),
        const SizedBox(height: 8),
        const Text("3. No outro aparelho, entre nessa rede como um Wi-Fi normal"),
        const SizedBox(height: 8),
        const Text("4. Volte aqui. Os dois na mesma rede, a transferência começa."),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: DeviceBridge.openSettings,
          icon: const Icon(Icons.settings),
          label: const Text("Abrir configurações"),
        ),
        const SizedBox(height: 8),
        const Text("Atalho: puxe a barra de cima duas vezes e toque em Hotspot.", style: TextStyle(fontSize: 13)),
      ],
    );
  }
}
