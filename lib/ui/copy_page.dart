import "dart:io";

import "package:battery_plus/battery_plus.dart";
import "package:flutter/material.dart";
import "package:wakelock_plus/wakelock_plus.dart";

import "../device_bridge.dart";
import "../history_store.dart";
import "../planner.dart";
import "../scanner.dart";
import "../settings_store.dart";
import "../transfer.dart";
import "file_groups.dart";

class CopyPage extends StatefulWidget {
  const CopyPage({super.key, required this.settings, required this.history});

  final SettingsStore settings;
  final HistoryStore history;

  @override
  State<CopyPage> createState() => _CopyPageState();
}

class _CopyPageState extends State<CopyPage> {
  bool _busy = true;
  bool _allowed = false;
  List<VolumeInfo> _volumes = [];
  List<LocalFile> _files = [];
  final _selected = <String>{};
  List<Placement> _plan = [];
  String _status = "Lendo os volumes";
  int _written = 0;
  int _total = 0;
  String _current = "";
  DateTime? _started;
  bool _done = false;
  final _cancel = CancelFlag();
  List<HistoryFile> _saved = [];

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    await DeviceBridge.requestMediaAccess();
    _allowed = await DeviceBridge.hasAllFilesAccess();
    _volumes = await DeviceBridge.volumes();
    _files = await scanFiles(_volumes);
    if (mounted) setState(() => _busy = false);
  }

  VolumeInfo? get _internal => _volumes.cast<VolumeInfo?>().firstWhere((item) => item?.removable == false, orElse: () => null);

  VolumeInfo? get _sd {
    final cards = _volumes.where((item) => item.removable).toList()
      ..sort((a, b) => b.freeBytes.compareTo(a.freeBytes));
    return cards.isEmpty ? null : cards.first;
  }

  void _buildPlan() {
    final chosen = _files.where((file) => _selected.contains(file.path)).toList();
    _plan = placeFiles(
      files: [
        for (final file in chosen) (name: file.name, bytes: file.bytes, path: file.path),
      ],
      mode: widget.settings.mode,
      internalFree: _internal?.freeBytes ?? 0,
      sdFree: _sd?.freeBytes ?? 0,
      fat32: _sd?.fat32 ?? false,
      internalBufferGb: widget.settings.internalBufferGb,
      sdBufferMb: widget.settings.sdBufferMb,
    );
  }

  Future<void> _run() async {
    final level = await Battery().batteryLevel.catchError((_) => 100);
    if (level <= 20 && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Bateria baixa"),
          content: Text("Está em $level%. Uma cópia longa pode parar no meio. Ligue o carregador se puder."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Voltar")),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Continuar")),
          ],
        ),
      );
      if (go != true) return;
    }
    final accepted = _plan.where((item) => item.dest != null).toList();
    setState(() {
      _busy = true;
      _done = false;
      _written = 0;
      _total = accepted.fold(0, (sum, item) => sum + item.bytes);
      _started = DateTime.now();
      _saved = [];
    });
    await DeviceBridge.hold();
    await WakelockPlus.enable();
    try {
      for (final item in accepted) {
        if (_cancel.cancelled) break;
        final root = item.dest == Dest.sd ? _sd?.path : _internal?.path;
        if (root == null) continue;
        setState(() => _current = item.name);
        final local = _files.cast<LocalFile?>().firstWhere((file) => file?.path == item.sourcePath, orElse: () => null);
        final source = local == null ? File(item.sourcePath) : await readableFile(local);
        final dest = await uniqueFile(Directory("$root/SincroLocal"), item.name);
        await copyHashed(
          source: source,
          dest: dest,
          cancel: _cancel,
          onProgress: (written) {
            final done = _saved.fold<int>(0, (sum, file) => sum + file.bytes);
            if (mounted) setState(() => _written = done + written);
          },
        );
        _saved.add(HistoryFile(name: item.name, bytes: item.bytes, dest: item.dest!.name, sourcePath: item.sourcePath));
      }
      if (_saved.isNotEmpty) {
        await widget.history.add(
          job: "copy",
          mode: widget.settings.mode.name,
          peer: "Este aparelho",
          files: _saved,
        );
      }
      if (mounted) setState(() => _done = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("A cópia parou: $error")));
      }
    } finally {
      await WakelockPlus.disable();
      await DeviceBridge.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _files.isEmpty && !_done) {
      return Scaffold(appBar: AppBar(title: const Text("Copiar")), body: const Center(child: Text("Lendo a galeria...")));
    }
    if (_plan.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Escolher arquivos")),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                _files.isEmpty
                    ? "Nenhuma foto ou vídeo. Toque em Permitir e escolha Permitir tudo."
                    : _sd == null
                        ? "Nenhum cartão SD encontrado. No modo híbrido ou só interna, a cópia usa a memória interna."
                        : "Cartão ${_sd!.label}: ${formatBytes(_sd!.freeBytes)} livres. Interna: ${formatBytes(_internal?.freeBytes ?? 0)}.",
              ),
            ),
            if (_files.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.icon(
                  onPressed: () async {
                    final granted = await DeviceBridge.requestMediaAccess();
                    if (!granted && await DeviceBridge.mediaAccess() == "none") {
                      await DeviceBridge.openSettings();
                    }
                    await _prepare();
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text("Permitir fotos e vídeos"),
                ),
              ),
            if (!_allowed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await DeviceBridge.requestAllFilesAccess();
                    await _prepare();
                  },
                  icon: const Icon(Icons.sd_card),
                  label: const Text("Autorizar gravação no cartão SD"),
                ),
              ),
            Expanded(
              child: _files.isEmpty
                  ? const Center(child: Text("Nada encontrado em Fotos, Vídeos, Documentos ou Downloads."))
                  : GroupedFileList(
                      files: _files,
                      selected: _selected,
                      onChanged: (next) => setState(() {
                        _selected
                          ..clear()
                          ..addAll(next);
                      }),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty ? null : () => setState(_buildPlan),
                icon: const Icon(Icons.sd_card),
                label: Text("Ver destino (${_selected.length})"),
              ),
            ),
          ],
        ),
      );
    }
    if (_done) {
      return Scaffold(
        appBar: AppBar(title: const Text("Concluído")),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${_saved.length} arquivo(s) copiados e verificados.", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text("Os originais continuam no lugar. Você pode apagá-los agora ou pelo histórico."),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  for (final file in _saved) {
                    final source = File(file.sourcePath);
                    if (await source.exists()) await source.delete();
                  }
                  if (mounted) Navigator.pop(context);
                },
                child: const Text("Apagar originais"),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Manter originais")),
            ],
          ),
        ),
      );
    }
    if (_busy) {
      final elapsed = DateTime.now().difference(_started ?? DateTime.now()).inMilliseconds / 1000;
      final speed = elapsed <= 0 ? 0 : _written / elapsed;
      final remaining = speed <= 0 ? 0 : (_total - _written) / speed;
      return Scaffold(
        appBar: AppBar(title: const Text("Copiando")),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: _total == 0 ? null : _written / _total),
              const SizedBox(height: 16),
              Text(_current, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text("${formatBytes(_written)} de ${formatBytes(_total)}"),
              Text("${formatBytes(speed.round())}/s · ${formatEta(remaining.toDouble())}"),
              const Spacer(),
              OutlinedButton(onPressed: () => _cancel.cancelled = true, child: const Text("Cancelar")),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Destino")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("${modeLabel(widget.settings.mode)}. ${modeHint(widget.settings.mode)}"),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final item in _plan)
                  ListTile(
                    title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text("${formatBytes(item.bytes)} · ${placementLabel(item)}"),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _plan.any((item) => item.dest != null) ? _run : null,
              child: const Text("Iniciar cópia"),
            ),
          ),
        ],
      ),
    );
  }
}
