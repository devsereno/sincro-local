import "dart:io";

import "package:flutter/material.dart";

import "../device_bridge.dart";
import "../planner.dart";
import "../scanner.dart";

class CardPage extends StatefulWidget {
  const CardPage({super.key});

  @override
  State<CardPage> createState() => _CardPageState();
}

class _CardPageState extends State<CardPage> {
  List<VolumeInfo> _volumes = [];
  final _items = <_CardFile>[];
  bool _loading = true;
  String _status = "Lendo o cartão...";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _items.clear();
      _status = "Lendo o cartão...";
    });
    final volumes = await DeviceBridge.volumes();
    final found = <_CardFile>[];
    for (final volume in volumes) {
      final root = Directory("${volume.path}/SincroLocal");
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final stat = await entity.stat();
          if (stat.size <= 0) continue;
          found.add(_CardFile(
            path: entity.path,
            name: entity.path.split("/").last,
            bytes: stat.size,
            folder: entity.parent.path.split("/").last,
            volume: volume.removable ? "Cartão" : "Interna",
          ));
        }
      } catch (_) {}
    }
    found.sort((a, b) => b.bytes.compareTo(a.bytes));
    if (!mounted) return;
    setState(() {
      _volumes = volumes;
      _items.addAll(found);
      _loading = false;
      _status = found.isEmpty ? "Nada copiado ainda." : "${found.length} arquivo(s) em SincroLocal.";
    });
  }

  Future<void> _delete(_CardFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Apagar do cartão?"),
        content: Text("Apagar ${file.name}? Isso não vai para a lixeira."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Apagar")),
        ],
      ),
    );
    if (ok != true) return;
    final target = File(file.path);
    if (await target.exists()) await target.delete();
    if (!mounted) return;
    setState(() => _items.remove(file));
  }

  @override
  Widget build(BuildContext context) {
    final sd = _volumes.where((item) => item.removable).toList();
    final total = _items.fold<int>(0, (sum, file) => sum + file.bytes);
    return Scaffold(
      appBar: AppBar(
        title: const Text("No cartão"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              sd.isEmpty
                  ? "Não achei cartão SD. Mostrando o que está na memória interna."
                  : "Cartão: ${formatBytes(sd.first.freeBytes)} livres. Copiados: ${formatBytes(total)}.",
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(_status, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text("Nenhum arquivo em SincroLocal ainda."))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final file = _items[index];
                      return ListTile(
                        leading: Icon(_icon(file.folder)),
                        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text("${file.volume} · ${file.folder} · ${formatBytes(file.bytes)}"),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(file),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _icon(String folder) {
    if (folder == "Imagens") return Icons.photo;
    if (folder == "Vídeos") return Icons.videocam;
    return Icons.insert_drive_file;
  }
}

class _CardFile {
  _CardFile({required this.path, required this.name, required this.bytes, required this.folder, required this.volume});

  final String path;
  final String name;
  final int bytes;
  final String folder;
  final String volume;
}
