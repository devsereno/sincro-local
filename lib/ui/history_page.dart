import "dart:io";

import "package:flutter/material.dart";

import "../history_store.dart";
import "../planner.dart";

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.history});

  final HistoryStore history;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<HistorySession>> _future = widget.history.all();

  Future<void> _delete(HistorySession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Apagar originais?"),
        content: const Text("Isto apaga os arquivos de origem de verdade. Não vão para a lixeira."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Apagar")),
        ],
      ),
    );
    if (ok != true) return;
    for (final file in session.files) {
      final source = File(file.sourcePath);
      if (await source.exists()) await source.delete();
    }
    await widget.history.markDeleted(session.id);
    setState(() => _future = widget.history.all());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Histórico")),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? [];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (sessions.isEmpty) {
            return const Center(child: Text("Nenhuma sessão verificada ainda."));
          }
          return ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final when = DateTime.fromMillisecondsSinceEpoch(session.at);
              final bytes = session.files.fold<int>(0, (sum, file) => sum + file.bytes);
              return ListTile(
                title: Text(session.job == "copy" ? "Cópia local" : "Sincronização"),
                subtitle: Text("${session.files.length} arquivo(s) · ${formatBytes(bytes)}\n${when.day}/${when.month}/${when.year} ${when.hour}:${when.minute.toString().padLeft(2, "0")}"),
                isThreeLine: true,
                trailing: session.sourceDeleted || session.job != "copy"
                    ? const Icon(Icons.verified, color: Color(0xFF1C6B45))
                    : TextButton(onPressed: () => _delete(session), child: const Text("Apagar")),
              );
            },
          );
        },
      ),
    );
  }
}
