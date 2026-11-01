import "dart:async";
import "dart:io";

import "package:battery_plus/battery_plus.dart";
import "package:flutter/material.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:wakelock_plus/wakelock_plus.dart";

import "../device_bridge.dart";
import "../history_store.dart";
import "../planner.dart";
import "../scanner.dart";
import "../settings_store.dart";
import "../sync.dart";

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.settings, required this.history});

  final SettingsStore settings;
  final HistoryStore history;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  String? _role;
  IncomingRoom? _room;
  List<VolumeInfo> _volumes = [];
  List<FoundPeer> _peers = [];
  FoundPeer? _peer;
  bool _looking = false;
  final _manual = TextEditingController();
  final _code = TextEditingController();
  String? _token;
  List<LocalFile> _files = [];
  final _selected = <String>{};
  String _status = "";
  int _sent = 0;
  int _total = 0;
  bool _busy = false;

  VolumeInfo? get _internal => _volumes.where((item) => !item.removable).cast<VolumeInfo?>().firstOrNull;

  VolumeInfo? get _sd {
    final cards = _volumes.where((item) => item.removable).toList()
      ..sort((a, b) => b.freeBytes.compareTo(a.freeBytes));
    return cards.firstOrNull;
  }

  @override
  void dispose() {
    _room?.close();
    _manual.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _receive() async {
    final allowed = await DeviceBridge.hasAllFilesAccess();
    if (!allowed) {
      await DeviceBridge.requestAllFilesAccess();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Autorize o acesso aos arquivos e toque de novo em Receber.")),
        );
      }
      return;
    }
    _volumes = await DeviceBridge.volumes();
    final room = IncomingRoom(deviceName: await DeviceBridge.deviceModel());
    await room.start((offers) {
      return placeFiles(
        files: [
          for (final offer in offers) (name: offer.name, bytes: offer.bytes, path: offer.id),
        ],
        mode: widget.settings.mode,
        internalFree: _internal?.freeBytes ?? 0,
        sdFree: _sd?.freeBytes ?? 0,
        fat32: _sd?.fat32 ?? false,
        internalBufferGb: widget.settings.internalBufferGb,
        sdBufferMb: widget.settings.sdBufferMb,
      );
    });
    room.addListener(() {
      if (mounted) setState(() {});
      if (room.finished) _saveReceive(room);
    });
    setState(() {
      _role = "receive";
      _room = room;
    });
  }

  bool _savedReceive = false;

  Future<void> _saveReceive(IncomingRoom room) async {
    if (_savedReceive) return;
    _savedReceive = true;
    await widget.history.add(
      job: "sync",
      mode: widget.settings.mode.name,
      peer: "Outro aparelho",
      files: [
        for (final file in room.saved)
          HistoryFile(name: file.name, bytes: file.bytes, dest: file.dest, sourcePath: file.sourcePath),
      ],
    );
  }

  Future<void> _scanPeers() async {
    setState(() => _looking = true);
    final peers = await Sender.listen();
    if (mounted) {
      setState(() {
        _peers = peers;
        _looking = false;
      });
    }
  }

  Future<void> _choosePeer(FoundPeer peer) async {
    setState(() => _peer = peer);
  }

  Future<void> _submitCode(String code) async {
    final peer = _peer;
    if (peer == null) return;
    try {
      final token = await Sender.pair(peer, code);
      final files = await scanFiles(await DeviceBridge.volumes());
      setState(() {
        _token = token;
        _files = files;
        _status = "Pareado com ${peer.name}. Escolha o que enviar.";
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Não pareou: $error")));
      }
    }
  }

  Future<void> _send() async {
    final peer = _peer;
    final token = _token;
    if (peer == null || token == null) return;
    final level = await Battery().batteryLevel.catchError((_) => 100);
    if (level <= 20 && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Bateria baixa"),
          content: Text("Está em $level%. Ligue o carregador se a transferência for longa."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Voltar")),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Continuar")),
          ],
        ),
      );
      if (go != true) return;
    }
    final chosen = _files.where((file) => _selected.contains(file.path)).toList();
    final offers = [
      for (var i = 0; i < chosen.length; i++) Offer(id: "$i", name: chosen[i].name, bytes: chosen[i].bytes),
    ];
    setState(() {
      _busy = true;
      _status = "O outro aparelho está escolhendo o destino.";
    });
    await DeviceBridge.hold();
    await WakelockPlus.enable();
    try {
      await Sender.manifest(peer, token, offers);
      Map<String, dynamic> decision = {"ready": false};
      for (var i = 0; i < 150; i++) {
        decision = await Sender.decision(peer, token);
        if (decision["ready"] == true) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      if (decision["ready"] != true) throw StateError("o outro aparelho não confirmou");
      final accepted = <String>{
        for (final item in decision["placements"] as List<dynamic>)
          if (item["dest"] != null) item["id"].toString(),
      };
      final todo = [
        for (var i = 0; i < offers.length; i++)
          if (accepted.contains(offers[i].id)) (offer: offers[i], file: chosen[i]),
      ];
      final total = todo.fold<int>(0, (sum, item) => sum + item.offer.bytes);
      setState(() => _total = total);
      var done = 0;
      final saved = <HistoryFile>[];
      for (final item in todo) {
        setState(() => _status = item.offer.name);
        await Sender.upload(peer, token, item.offer, File(item.file.path), (sent) {
          if (mounted) setState(() => _sent = done + sent);
        });
        done += item.offer.bytes;
        saved.add(HistoryFile(name: item.offer.name, bytes: item.offer.bytes, dest: "remoto", sourcePath: item.file.path));
      }
      await Sender.finish(peer, token);
      await widget.history.add(job: "sync", mode: widget.settings.mode.name, peer: peer.name, files: saved);
      if (mounted) setState(() => _status = "Enviado e verificado.");
    } catch (error) {
      if (mounted) setState(() => _status = "Parou: $error");
    } finally {
      await WakelockPlus.disable();
      await DeviceBridge.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      appBar: AppBar(title: const Text("Sincronizar")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _role == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Os dois aparelhos precisam estar na mesma rede Wi-Fi."),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _receive, child: const Text("Receber neste aparelho")),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      setState(() => _role = "send");
                      _scanPeers();
                    },
                    child: const Text("Enviar para o outro"),
                  ),
                ],
              )
            : room != null
                ? _receiveBody(room)
                : _sendBody(),
      ),
    );
  }

  Widget _receiveBody(IncomingRoom room) {
    final link = room.ip == null ? "" : "sincro://${room.ip}:${room.port}";
    return ListView(
      children: [
        Text(room.status, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        const Text("Código deste aparelho", style: TextStyle(color: Colors.black54)),
        Text(room.code, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: 8)),
        if (link.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(child: QrImageView(data: link, size: 160, backgroundColor: Colors.white)),
          Text(link, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 12),
        Text("Modo ${modeLabel(widget.settings.mode)}. ${modeHint(widget.settings.mode)}"),
        if (room.offers.isNotEmpty && !room.decided) ...[
          const SizedBox(height: 12),
          for (final item in room.plan)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              subtitle: Text("${formatBytes(item.bytes)} · ${placementLabel(item)}"),
            ),
          FilledButton(
            onPressed: () => room.accept(_internal?.path ?? "/storage/emulated/0", _sd?.path),
            child: const Text("Receber o que cabe"),
          ),
        ],
        if (room.decided) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: room.totalBytes == 0 ? null : room.receivedBytes / room.totalBytes),
          Text("${formatBytes(room.receivedBytes)} de ${formatBytes(room.totalBytes)}"),
          Text(room.current),
        ],
      ],
    );
  }

  Widget _sendBody() {
    if (_token == null) {
      return ListView(
        children: [
          const Text("Escolha o aparelho que está recebendo e toque no código que aparece na tela dele."),
          const SizedBox(height: 12),
          if (_looking) const LinearProgressIndicator(),
          for (final peer in _peers)
            ListTile(
              title: Text(peer.name),
              subtitle: Text("${peer.address}:${peer.port}"),
              onTap: () => _choosePeer(peer),
            ),
          TextField(
            controller: _manual,
            decoration: const InputDecoration(labelText: "Se o radar falhar: IP:porta"),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              final parts = _manual.text.split(":");
              final port = parts.length == 2 ? int.tryParse(parts[1]) : null;
              if (port == null) return;
              _choosePeer(FoundPeer(name: "Manual", address: parts[0], port: port));
            },
            child: const Text("Usar este endereço"),
          ),
          if (_peer != null) ...[
            const SizedBox(height: 16),
            Text("Digite o código de 3 caracteres que está na tela de ${_peer!.name}."),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: "Código"),
            ),
            FilledButton(
              onPressed: _code.text.trim().length < 3 ? null : () => _submitCode(_code.text.trim().toUpperCase()),
              child: const Text("Parear"),
            ),
          ],
        ],
      );
    }
    return Column(
      children: [
        Text(_status),
        const SizedBox(height: 8),
        if (_busy) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _sent / _total),
          Text("${formatBytes(_sent)} de ${formatBytes(_total)}"),
        ],
        Expanded(
          child: ListView(
            children: [
              for (final file in _files)
                CheckboxListTile(
                  value: _selected.contains(file.path),
                  title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text("${file.category} · ${formatBytes(file.bytes)}"),
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(file.path);
                            } else {
                              _selected.remove(file.path);
                            }
                          });
                        },
                ),
            ],
          ),
        ),
        FilledButton(onPressed: _busy || _selected.isEmpty ? null : _send, child: const Text("Enviar")),
      ],
    );
  }
}
