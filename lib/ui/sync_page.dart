import "dart:async";

import "package:battery_plus/battery_plus.dart";
import "package:flutter/material.dart";
import "package:mobile_scanner/mobile_scanner.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:wakelock_plus/wakelock_plus.dart";

import "../device_bridge.dart";
import "../history_store.dart";
import "../planner.dart";
import "../scanner.dart";
import "../settings_store.dart";
import "../sync.dart";
import "file_groups.dart";

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
    await DeviceBridge.multicast(true);
    try {
      final peers = await Sender.listen(duration: const Duration(seconds: 6));
      if (mounted) {
        setState(() {
          _peers = peers;
          _looking = false;
        });
      }
    } finally {
      await DeviceBridge.multicast(false);
    }
  }

  Future<void> _choosePeer(FoundPeer peer) async {
    setState(() => _peer = peer);
  }

  Future<void> _openCamera() async {
    final raw = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _QrScanPage()));
    if (!mounted || raw == null) return;
    final peer = _peerFromQr(raw);
    if (peer == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Esse QR não é do SincroLocal.")));
      return;
    }
    setState(() {
      _peer = peer;
      _manual.text = "${peer.address}:${peer.port}";
    });
  }

  FoundPeer? _peerFromQr(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != "sincro" || uri.host.isEmpty || uri.hasPort == false) return null;
    return FoundPeer(name: "o outro aparelho", address: uri.host, port: uri.port);
  }

  Future<void> _submitCode(String code) async {
    final peer = _peer;
    if (peer == null || _busy) return;
    setState(() {
      _busy = true;
      _status = "Conferindo o código...";
    });
    try {
      final token = await Sender.pair(peer, code);
      if (!mounted) return;
      await _loadLibrary(token);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Não pareou: $error")));
      }
    }
  }

  Future<void> _loadLibrary(String token) async {
    setState(() {
      _token = token;
      _busy = true;
      _status = "Pedindo permissão para ler fotos e vídeos...";
    });
    var access = await DeviceBridge.mediaAccess();
    if (access != "all") access = await DeviceBridge.requestMediaAccess() ? await DeviceBridge.mediaAccess() : access;
    if (!mounted) return;
    if (access == "none") {
      setState(() {
        _busy = false;
        _files = [];
        _status = "Sem permissão para a galeria. Toque em Permitir fotos e vídeos e escolha Permitir tudo.";
      });
      return;
    }
    setState(() => _status = "Lendo a galeria deste aparelho...");
    final files = await scanFiles(await DeviceBridge.volumes());
    if (!mounted) return;
    final photos = files.where((file) => file.category == "Fotos").length;
    final videos = files.where((file) => file.category == "Vídeos").length;
    setState(() {
      _files = files;
      _busy = false;
      _status = files.isEmpty
          ? "Não achei fotos nem vídeos. Se o Android perguntou, escolha Permitir tudo."
          : "Pareado. $photos fotos e $videos vídeos.";
    });
  }

  Future<void> _allowGallery() async {
    final granted = await DeviceBridge.requestMediaAccess();
    final access = await DeviceBridge.mediaAccess();
    if (!granted && access == "none") {
      await DeviceBridge.openSettings();
      return;
    }
    final token = _token;
    if (token != null) await _loadLibrary(token);
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
        await Sender.upload(peer, token, item.offer, await readableFile(item.file), (sent) {
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

  Future<void> _end() async {
    await _room?.close();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sincronizar"),
        actions: [
          if (_role != null)
            TextButton.icon(
              onPressed: _end,
              icon: const Icon(Icons.link_off),
              label: const Text("Encerrar"),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _role == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Os dois aparelhos precisam estar na mesma rede Wi-Fi."),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _receive,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text("Receber neste aparelho"),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _role = "send");
                      _scanPeers();
                    },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text("Enviar para o outro"),
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
        Text("Código deste aparelho", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          const Text("Aponte a câmera para o QR do aparelho que está recebendo. Depois digite só o código de 3 letras."),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _openCamera, child: const Text("Abrir câmera e ler o QR")),
          const SizedBox(height: 16),
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
              _choosePeer(FoundPeer(name: "o outro aparelho", address: parts[0], port: port));
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
              onPressed: _busy || _code.text.trim().length < 3 ? null : () => _submitCode(_code.text.trim().toUpperCase()),
              child: Text(_busy ? "Conferindo..." : "Parear"),
            ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          ],
        ],
      );
    }
    return Column(
      children: [
        Text(_status),
        const SizedBox(height: 8),
        if (_busy && _files.isEmpty) const LinearProgressIndicator(),
        if (_busy && _total > 0) ...[
          LinearProgressIndicator(value: _sent / _total),
          Text("${formatBytes(_sent)} de ${formatBytes(_total)}"),
        ],
        if (_files.isEmpty && !_busy)
          FilledButton.icon(
            onPressed: _allowGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text("Permitir fotos e vídeos"),
          ),
        Expanded(
          child: GroupedFileList(
            files: _files,
            selected: _selected,
            enabled: !_busy,
            onChanged: (next) => setState(() {
              _selected
                ..clear()
                ..addAll(next);
            }),
          ),
        ),
        Row(
          children: [
            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _end, icon: const Icon(Icons.close), label: const Text("Encerrar"))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: _busy || _selected.isEmpty ? null : _send, icon: const Icon(Icons.send), label: const Text("Enviar"))),
          ],
        ),
      ],
    );
  }
}

class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _done = false;

  void _found(String? raw) {
    if (_done || raw == null || !raw.startsWith("sincro://")) return;
    _done = true;
    Navigator.pop(context, raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ler QR")),
      body: MobileScanner(onDetect: (capture) => _found(capture.barcodes.firstOrNull?.rawValue)),
    );
  }
}
