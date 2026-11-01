import "package:flutter/material.dart";

import "../planner.dart";
import "../settings_store.dart";

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Mode _mode = widget.settings.mode;
  late double _internal = widget.settings.internalBufferGb;
  late double _sd = widget.settings.sdBufferMb.toDouble();

  Future<void> _save() async {
    widget.settings.mode = _mode;
    widget.settings.internalBufferGb = _internal;
    widget.settings.sdBufferMb = _sd.round();
    await widget.settings.save();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ajustes")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Destino padrão", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final mode in Mode.values)
            RadioListTile<Mode>(
              value: mode,
              groupValue: _mode,
              title: Text(modeLabel(mode)),
              subtitle: Text(modeHint(mode)),
              onChanged: (value) => setState(() => _mode = value ?? _mode),
            ),
          const SizedBox(height: 12),
          Text("Reserva da interna: ${_internal.toStringAsFixed(0)} GB"),
          Slider(min: 1, max: 20, divisions: 19, value: _internal, onChanged: (value) => setState(() => _internal = value)),
          Text("Reserva do cartão: ${_sd.round()} MB"),
          Slider(min: 100, max: 2000, divisions: 19, value: _sd, onChanged: (value) => setState(() => _sd = value)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text("Guardar")),
        ],
      ),
    );
  }
}
