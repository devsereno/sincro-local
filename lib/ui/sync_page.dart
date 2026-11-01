import "dart:async";

import "package:battery_plus/battery_plus.dart";
import "package:flutter/material.dart";
import "package:mobile_scanner/mobile_scanner.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:wakelock_plus/wakelock_plus.dart";

import "../device_bridge.dart";
import "../history_store.dart";
import "../planner.dart";
import "../resume_store.dart";
import "../scanner.dart";
import "../settings_store.dart";
import "../sync.dart";
import "file_groups.dart";
import "battery_meter.dart";
import "transfer_panel.dart";

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
  bool _pauseHere = false;
  bool _pauseThere = false;
  bool _stop = false;
  bool _loadingLibrary = false;
  bool _followAll = false;
  String _currentName = "";
  int _fileIndex = 0;
  int _fileCount = 0;
  int _part = 1;
  int _parts = 1;
  int? _otherNow;
  int _myBattery = -1;
  DateTime? _batteryAt;
  String _peerLabel = "";
  LastTransfer? _resume;
  bool _goHome = false;
  Timer? _poll;

  VolumeInfo? get _internal => _volumes.where((item) => !item.removable).cast<VolumeInfo?>().firstOrNull;

  VolumeInfo? get _sd {
    final cards = _volumes.where((item) => item.removable).toList()
      ..sort((a, b) => b.freeBytes.compareTo(a.freeBytes));
    return cards.firstOrNull;
  }

  @override
  void dispose() {
    _stop = true;
    _poll?.cancel();
    _room?.cancel.cancelled = true;
    _room?.close();
    WakelockPlus.disable();
    DeviceBridge.release();
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
    }, internalPath: _internal?.path ?? "/storage/emulated/0", sdPath: _sd?.path);
    room.addListener(() {
      if (!mounted) return;
      if (room.ended) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("O outro aparelho encerrou.")));
        _backToStart();
        return;
      }
      setState(() {});
      if (room.finished) _saveReceive(room);
    });
    await DeviceBridge.hold();
    await WakelockPlus.enable();
    setState(() {
      _role = "receive";
      _room = room;
    });
  }

  final _savedPaths = <String>{};

  Future<void> _saveReceive(IncomingRoom room) async {
    final fresh = [
      for (final file in room.saved)
        if (_savedPaths.add(file.sourcePath))
          HistoryFile(name: file.name, bytes: file.bytes, dest: file.dest, sourcePath: file.sourcePath),
    ];
    if (fresh.isEmpty) return;
    await widget.history.add(job: "sync", mode: widget.settings.mode.name, peer: "Outro aparelho", files: fresh);
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
      final paired = await Sender.pair(peer, code);
      if (!mounted) return;
      _peerLabel = paired.name;
      _resume = await ResumeStore.loadSession();
      await _loadLibrary(paired.token);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Não pareou: $error")));
      }
    }
  }

  Future<void> _loadLibrary(String token) async {
    final cached = await ResumeStore.loadLibrary();
    setState(() {
      _token = token;
      _busy = false;
      _loadingLibrary = true;
      if (cached.isNotEmpty) {
        _files = cached;
        _status = "Lista salva. Atualizando fotos, vídeos, zip e documentos...";
      } else {
        _files = [];
        _status = "Buscando os primeiros arquivos...";
      }
    });
    var access = await DeviceBridge.mediaAccess();
    if (access != "all") access = await DeviceBridge.requestMediaAccess() ? await DeviceBridge.mediaAccess() : access;
    if (!mounted || _token != token) return;
    if (access == "none") {
      setState(() {
        _loadingLibrary = false;
        _status = _files.isEmpty
            ? "Sem permissão para a galeria. Toque em Permitir fotos e vídeos e escolha Permitir tudo."
            : "Sem permissão para atualizar. Mostrando a lista salva.";
      });
      return;
    }
    for (final kind in ["images", "videos", "files"]) {
      var offset = 0;
      while (mounted && _token == token && !_stop) {
        final page = await loadGalleryChunk(kind, offset);
        if (!mounted || _token != token) return;
        setState(() {
          final seen = _files.map((file) => file.path).toSet();
          for (final file in page.files) {
            if (!seen.add(file.path)) continue;
            _files.add(file);
            if (_followAll) _selected.add(file.path);
          }
          if (_busy) return;
          _status = _libraryStatus();
        });
        if (page.done || page.next <= offset) break;
        offset = page.next;
      }
    }
    if (!mounted || _token != token) return;
    final extras = await scanDocuments(await DeviceBridge.volumes());
    if (!mounted || _token != token) return;
    final known = _files.map((file) => file.path).toSet();
    final fresh = extras.where((file) => known.add(file.path));
    setState(() {
      for (final file in fresh) {
        _files.add(file);
        if (_followAll) _selected.add(file.path);
      }
      _loadingLibrary = false;
      if (!_busy) _status = _files.isEmpty ? "Não achei arquivos. Se o Android perguntou, escolha Permitir tudo." : _libraryStatus();
    });
    if (_files.isNotEmpty) await ResumeStore.saveLibrary(_files);
  }

  String _libraryStatus() {
    final photos = _files.where((file) => file.category == "Fotos").length;
    final videos = _files.where((file) => file.category == "Vídeos").length;
    final others = _files.length - photos - videos;
    return "$photos fotos, $videos vídeos e $others outros arquivos.";
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

  Future<int> _level() async {
    final now = DateTime.now();
    if (_myBattery >= 0 && _batteryAt != null && now.difference(_batteryAt!).inSeconds < 20) return _myBattery;
    _myBattery = await Battery().batteryLevel.catchError((_) => _myBattery < 0 ? 100 : _myBattery);
    _batteryAt = now;
    return _myBattery;
  }

  Future<void> _send() async {
    final peer = _peer;
    final token = _token;
    if (peer == null || token == null) return;
    final picked = _files.where((file) => _selected.contains(file.path)).toList();
    if (picked.isEmpty) return;
    final have = await Sender.present(peer, token, picked);
    final chosen = picked.where((file) => !have.contains("${file.name}|${file.bytes}")).toList();
    if (chosen.isEmpty) {
      if (mounted) {
        setState(() => _status = "Esses arquivos já estão completos no outro aparelho. Nada novo para enviar.");
      }
      return;
    }
    final doneKeys = {...have};
    if (have.isNotEmpty && mounted) {
      setState(() => _status = "Vou pular ${have.length} arquivo(s) que já chegaram completos.");
    }
    final jobBytes = chosen.fold<int>(0, (sum, file) => sum + file.bytes);
    var batches = [chosen];
    const limit = 5 * gb;
    if (jobBytes > limit && chosen.length > 1) {
      final split = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Dividir a transferência?"),
          content: Text(
            "São ${formatBytes(jobBytes)}. Posso enviar em partes de cerca de 5 GB. Quando uma acaba, você escolhe se continua.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Voltar")),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Enviar tudo")),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Dividir em partes")),
          ],
        ),
      );
      if (!mounted || split == null) return;
      if (split) batches = _splitFiles(chosen, limit);
    }
    final level = await _level();
    final outlook = chargeForecast(level: level, bytes: jobBytes);
    if (!mounted) return;
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Antes de começar"),
        content: Text(
          "Tempo estimado: ${formatEta(outlook.seconds)}, a cerca de 2 MB/s.\n\n"
          "Neste aparelho a bateria está em ${outlook.now}%. Ao terminar deve ficar em torno de ${outlook.atEnd}%.\n\n"
          "${outlook.needsCharger ? "Conecte o carregador neste aparelho." : "A bateria deste aparelho deve aguentar."}\n\n"
          "O outro aparelho também mostra o tempo e a bateria dele antes de aceitar.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Voltar")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Começar")),
        ],
      ),
    );
    if (start != true || !mounted) return;
    setState(() {
      _busy = true;
      _pauseHere = false;
      _pauseThere = false;
      _stop = false;
      _sent = 0;
      _total = jobBytes;
      _fileIndex = 0;
      _fileCount = chosen.length;
      _part = 1;
      _parts = batches.length;
      _currentName = "";
      _otherNow = null;
      _status = "O outro aparelho está escolhendo o destino.";
    });
    await DeviceBridge.hold();
    await WakelockPlus.enable();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_stop || _peer == null || _token == null) return;
      try {
        final state = await Sender.pulse(_peer!, _token!, await _level());
        if (!mounted) return;
        final remote = state["battery"];
        final got = state["received"];
        setState(() {
          _pauseThere = state["here"] == true;
          if (remote is num && remote >= 0) _otherNow = remote.toInt();
          if ((_pauseHere || _pauseThere) && got is num && _total > 0) {
            final value = got.toInt();
            if (value >= 0 && value <= _total) _sent = value;
          }
        });
      } catch (_) {}
    });
    try {
      await ResumeStore.saveSession(LastTransfer(peer: _peerLabel, files: picked, done: doneKeys));
      var jobDone = 0;
      var sentFiles = 0;
      for (var part = 0; part < batches.length; part++) {
        if (_stop) throw StateError("interrompido");
        final batch = batches[part];
        final offers = [
          for (var i = 0; i < batch.length; i++) Offer(id: "$i", name: batch[i].name, bytes: batch[i].bytes),
        ];
        setState(() {
          _part = part + 1;
          _parts = batches.length;
          _status = batches.length > 1
              ? "Parte ${part + 1} de ${batches.length}. O outro aparelho confirma."
              : "O outro aparelho está escolhendo o destino.";
        });
        await Sender.manifest(
          peer,
          token,
          offers,
          battery: await _level(),
          part: part + 1,
          parts: batches.length,
          jobBytes: jobBytes,
          jobDone: jobDone,
        );
        Map<String, dynamic> decision = {"ready": false};
        for (var i = 0; i < 150; i++) {
          if (_stop) throw StateError("interrompido");
          await _waitIfPaused();
          decision = await Sender.decision(peer, token);
          if (decision["ready"] == true) break;
          await Future.delayed(const Duration(seconds: 1));
        }
        if (decision["ready"] != true) throw StateError("o outro aparelho não confirmou");
        final remote = (decision["battery"] as num?)?.toInt();
        if (remote != null && remote >= 0 && part == 0 && mounted) {
          final other = chargeForecast(level: remote, bytes: jobBytes);
          setState(() => _otherNow = remote);
          if (other.needsCharger) {
            final cont = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Bateria do outro aparelho"),
                content: Text(
                  "Lá está em ${other.now}% e deve terminar perto de ${other.atEnd}%.\n\nConecte o carregador no aparelho que vai receber.",
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Parar")),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Continuar mesmo assim")),
                ],
              ),
            );
            if (cont != true) {
              await Sender.finish(peer, token);
              if (mounted) setState(() => _status = "Parou. Ligue o carregador no outro aparelho e envie de novo.");
              return;
            }
          }
        }
        final accepted = <String>{
          for (final item in decision["placements"] as List<dynamic>)
            if (item["dest"] != null) item["id"].toString(),
        };
        final todo = [
          for (var i = 0; i < offers.length; i++)
            if (accepted.contains(offers[i].id)) (offer: offers[i], file: batch[i]),
        ];
        setState(() => _status = "Enviando");
        final saved = <HistoryFile>[];
        for (final item in todo) {
          if (_stop) throw StateError("interrompido");
          sentFiles += 1;
          final base = jobDone;
          setState(() {
            _currentName = item.offer.name;
            _fileIndex = sentFiles;
            _status = item.offer.name;
          });
          await Sender.upload(peer, token, item.offer, await readableFile(item.file), (sent) {
            if (mounted) setState(() => _sent = base + sent);
          }, _waitIfPaused);
          jobDone += item.offer.bytes;
          if (mounted) setState(() => _sent = jobDone);
          doneKeys.add("${item.offer.name}|${item.offer.bytes}");
          await ResumeStore.saveSession(LastTransfer(peer: _peerLabel, files: picked, done: doneKeys));
          saved.add(HistoryFile(name: item.offer.name, bytes: item.offer.bytes, dest: "remoto", sourcePath: item.file.path));
        }
        final hasNext = part + 1 < batches.length;
        var more = false;
        if (hasNext && mounted) {
          final nextBytes = batches[part + 1].fold<int>(0, (sum, file) => sum + file.bytes);
          final next = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text("Parte ${part + 1} de ${batches.length} concluída"),
              content: Text("A próxima tem ${formatBytes(nextBytes)}. Continuar?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Parar")),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Próxima parte")),
              ],
            ),
          );
          more = next == true;
        }
        await Sender.finish(peer, token, more: more);
        await widget.history.add(job: "sync", mode: widget.settings.mode.name, peer: peer.name, files: saved);
        if (!more) {
          if (mounted) {
            setState(() => _status = hasNext ? "Parou entre as partes. O que já chegou ficou salvo." : "Enviado e verificado.");
          }
          return;
        }
      }
    } catch (error) {
      final text = error.toString();
      final remoteClosed = text.contains("Connection refused") ||
          text.contains("errno = 111") ||
          text.contains("SocketException") ||
          text.contains("encerrou");
      if (remoteClosed) {
        _goHome = true;
      } else if (mounted) {
        setState(() => _status = _plainError(error));
      }
    } finally {
      _poll?.cancel();
      await WakelockPlus.disable();
      await DeviceBridge.release();
      if (_goHome && mounted) {
        _goHome = false;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("O outro aparelho encerrou. Voltando ao início.")));
        _backToStart();
      } else if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _waitIfPaused() async {
    while ((_pauseHere || _pauseThere) && !_stop) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_stop) throw StateError("interrompido");
  }

  Future<void> _togglePause() async {
    final next = !_pauseHere;
    setState(() => _pauseHere = next);
    final peer = _peer;
    final token = _token;
    if (peer == null || token == null) return;
    try {
      await Sender.setPause(peer, token, next);
    } catch (_) {}
  }

  Future<void> _end() async {
    final room = _room;
    final transferring = _busy || (room != null && room.decided && !room.finished);
    if (transferring && mounted) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Encerrar sincronização?"),
          content: const Text(
            "Isso encerra nos dois aparelhos e interrompe a transferência. O que já chegou fica salvo.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Continuar")),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Encerrar")),
          ],
        ),
      );
      if (leave != true) return;
    }
    _stop = true;
    final peer = _peer;
    final token = _token;
    if (peer != null && token != null) {
      try {
        await Sender.bye(peer, token);
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Conexão encerrada nos dois aparelhos.")));
    }
    _backToStart();
  }

  void _backToStart() {
    if (!mounted) return;
    _stop = true;
    _poll?.cancel();
    final room = _room;
    _room = null;
    room?.cancel.cancelled = true;
    room?.close();
    WakelockPlus.disable();
    DeviceBridge.release();
    setState(() {
      _role = null;
      _peer = null;
      _token = null;
      _busy = false;
      _sent = 0;
      _total = 0;
      _pauseHere = false;
      _pauseThere = false;
      _currentName = "";
      _status = "";
    });
  }

  Future<void> _resumeLast() async {
    final session = _resume;
    if (session == null || _busy) return;
    final known = _files.map((file) => file.path).toSet();
    setState(() {
      for (final file in session.files) {
        if (known.add(file.path)) _files.add(file);
      }
      _selected
        ..clear()
        ..addAll(session.files.map((file) => file.path));
    });
    await _send();
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
    final live = room.keepGoing || (room.decided && !room.finished);
    if (live) {
      final done = room.jobDone + room.receivedBytes;
      final total = room.jobBytes > 0 ? room.jobBytes : room.totalBytes;
      final heading = room.finished
          ? (room.part < room.parts ? "Parte concluída" : "Concluído")
          : room.paused
              ? "Pausado"
              : room.parts > 1
                  ? "Recebendo · parte ${room.part} de ${room.parts}"
                  : "Recebendo";
      return ListView(
        children: [
          Text(room.current.isEmpty ? room.status : room.current, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TransferPanel(
            heading: heading,
            fileName: room.current,
            done: done,
            total: total,
            paused: room.paused,
            index: room.saved.length + (room.current.isEmpty || room.finished ? 0 : 1),
            count: room.offers.isEmpty ? 1 : room.offers.length,
            onTogglePause: room.finished ? () {} : () => room.setLocalPause(!room.pauseHere),
          ),
          const SizedBox(height: 12),
          BatteryMeter(done: done, total: total, otherNow: room.peerBattery),
        ],
      );
    }
    final previewBytes = room.jobBytes > 0 ? room.jobBytes : room.plan.fold<int>(0, (sum, item) => sum + item.bytes);
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
          Text("${room.plan.length} arquivos · ${formatBytes(previewBytes)}"),
          if (room.parts > 1) Text("Parte ${room.part} de ${room.parts}"),
          const SizedBox(height: 8),
          BatteryMeter(done: 0, total: previewBytes, otherNow: room.peerBattery),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => room.accept(_internal?.path ?? "/storage/emulated/0", _sd?.path),
            child: const Text("Receber o que cabe"),
          ),
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
        if (_loadingLibrary) const LinearProgressIndicator(),
        if (_resume != null && _resume!.peer.isNotEmpty && _resume!.peer == _peerLabel && !_busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: _resumeLast,
              icon: const Icon(Icons.restore),
              label: Text("Retomar última transferência · faltam ${_resume!.remaining}"),
            ),
          ),
        if (_busy)
          Expanded(
            child: ListView(
              children: [
                if (_currentName.isNotEmpty) Text(_currentName, textAlign: TextAlign.center),
                TransferPanel(
                  heading: _sent == 0 && _currentName.isEmpty
                      ? "Aguardando"
                      : _pauseThere && !_pauseHere
                          ? "O outro aparelho pausou"
                          : _parts > 1
                              ? "Enviando · parte $_part de $_parts"
                              : "Enviando",
                  fileName: _currentName.isEmpty ? "Toque em Receber o que cabe no outro aparelho" : _currentName,
                  done: _sent,
                  total: _total,
                  paused: _pauseHere || _pauseThere,
                  index: _fileIndex,
                  count: _fileCount,
                  onTogglePause: _togglePause,
                ),
                const SizedBox(height: 12),
                BatteryMeter(done: _sent, total: _total, otherNow: _otherNow),
              ],
            ),
          )
        else ...[
          if (_files.isEmpty && !_loadingLibrary)
            FilledButton.icon(
              onPressed: _allowGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text("Permitir fotos e vídeos"),
            ),
          Expanded(
            child: GroupedFileList(
              files: _files,
              selected: _selected,
              enabled: true,
              onChanged: (next) => setState(() {
                _selected
                  ..clear()
                  ..addAll(next);
                _followAll = _files.isNotEmpty && next.length >= _files.length;
              }),
            ),
          ),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: _end, icon: const Icon(Icons.close), label: const Text("Encerrar"))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: _selected.isEmpty ? null : _send, icon: const Icon(Icons.send), label: const Text("Enviar"))),
            ],
          ),
        ],
      ],
    );
  }
}

List<List<LocalFile>> _splitFiles(List<LocalFile> files, int limit) {
  final parts = <List<LocalFile>>[];
  var current = <LocalFile>[];
  var size = 0;
  for (final file in files) {
    if (current.isNotEmpty && size + file.bytes > limit) {
      parts.add(current);
      current = <LocalFile>[];
      size = 0;
    }
    current.add(file);
    size += file.bytes;
  }
  if (current.isNotEmpty) parts.add(current);
  return parts;
}

String _plainError(Object error) {
  final text = error.toString();
  if (text.contains("Content size below") || text.contains("contentLength")) {
    return "O arquivo saiu pela metade e a transferência parou. Envie de novo com este aplicativo atualizado.";
  }
  if (text.contains("Connection refused") || text.contains("errno = 111")) {
    return "O outro aparelho fechou a recepção. Deixe ele na tela Receber, na mesma rede Wi-Fi, e toque em Enviar de novo.";
  }
  if (text.contains("interrompido")) return "Transferência interrompida.";
  if (text.contains("não confirmou")) return "No outro aparelho, toque em Receber o que cabe.";
  return "Parou: $text";
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
