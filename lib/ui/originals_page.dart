import "dart:io";

import "package:flutter/material.dart";

import "../history_store.dart";
import "../planner.dart";

class OriginalsPage extends StatefulWidget {
  const OriginalsPage({super.key, required this.history});

  final HistoryStore history;

  @override
  State<OriginalsPage> createState() => _OriginalsPageState();
}

class _OriginalsPageState extends State<OriginalsPage> {
  late Future<List<HistorySession>> _future = widget.history.all();
  final _selected = <String>{};

  Future<void> _reload() async {
    setState(() => _future = widget.history.all());
  }

  List<HistoryFile> _confirmed(List<HistorySession> sessions) {
    final seen = <String>{};
    final files = <HistoryFile>[];
    for (final session in sessions) {
      if (session.sourceDeleted) continue;
      for (final file in session.files) {
        if (seen.add(file.sourcePath)) files.add(file);
      }
    }
    return files;
  }

  Future<void> _delete(List<HistoryFile> files) async {
    if (files.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Apagar originais?"),
        content: Text("Apagar ${files.length} arquivo(s)? Isso não vai para a lixeira."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Apagar")),
        ],
      ),
    );
    if (ok != true) return;
    for (final file in files) {
      final source = File(file.sourcePath);
      if (await source.exists()) await source.delete();
    }
    if (!mounted) return;
    setState(() => _selected.clear());
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Apagar originais")),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? [];
          final files = _confirmed(sessions);
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (files.isEmpty) {
            return const Center(child: Text("Nenhum arquivo confirmado ainda."));
          }
          final allSelected = _selected.length == files.length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Text("${files.length} confirmado(s)"),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(files.map((file) => file.sourcePath));
                        }
                      }),
                      child: Text(allSelected ? "Desmarcar tudo" : "Selecionar tudo"),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final checked = _selected.contains(file.sourcePath);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(file.sourcePath);
                        } else {
                          _selected.remove(file.sourcePath);
                        }
                      }),
                      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(formatBytes(file.bytes)),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _delete(files.where((file) => _selected.contains(file.sourcePath)).toList()),
                  icon: const Icon(Icons.delete_outline),
                  label: Text("Apagar selecionados (${_selected.length})"),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
