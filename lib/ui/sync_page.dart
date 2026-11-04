import "dart:async";

import "package:battery_plus/battery_plus.dart";
import "package:flutter/material.dart";
import "package:mobile_scanner/mobile_scanner.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:wakelock_plus/wakelock_plus.dart";

import "../catalog_store.dart";
import "../device_bridge.dart";
import "../history_store.dart";
import "../planner.dart";
import "../resume_store.dart";
import "../scanner.dart";
import "../settings_store.dart";
import "../sync.dart";
import "../transfer.dart";
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

class _SyncPageState extends State<SyncPage> with WidgetsBindingObserver {
  String? _role;
  String? _link; // "casa" or "direta"
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
  bool _leaving = false;
  bool _left = false;
  Timer? _poll;

  VolumeInfo? get _internal => _volumes.where((item) => !item.removable).cast<VolumeInfo?>().firstOrNull;

  VolumeInfo? get _sd {
    final cards = _volumes.where((item) => item.removable).toList()
      ..sort((a, b) => b.freeBytes.compareTo(a.freeBytes));
    return cards.firstOrNull;
  }

  final _catalog = CatalogStore();
  Set<String> _remoteKeys = {};
  bool _needAllFiles = false;
  bool _loadingOthers = false;
  bool _hearing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString("directName");
      if (!mounted || saved == null || saved.isEmpty) return;
      _name.text = saved;
    });
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
    _name.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final token = _token;
    if (state == AppLifecycleState.resumed && _needAllFiles && token != null && !_loadingOthers) {
      _loadOtherFiles(token);
    }
  }

  Future<void> _receive({required bool direct}) async {
    await DeviceBridge.p2pStop();
    if (direct) {
      final ok = await DeviceBridge.p2pName(_name.text.trim().isEmpty ? "Sincro" : _name.text.trim());
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permita aparelhos próximos e toque de novo em Receber.")),
        );
        return;
      }
    }
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
    }, internalPath: _internal?.path ?? "/storage/emulated/0", sdPath: _sd?.path, announce: !direct);
    room.addListener(() {
      if (!mounted) return;
      if (room.ended) {
        _backToStart();
        return;
      }
      setState(() {});
      if (room.finished) _saveReceive(room);
    });
    await DeviceBridge.hold();
    await WakelockPlus.enable();
    setState(() {
      _link = direct ? "direta" : "casa";
      _role = "receive";
      _room = room;
      _direct = "";
      _directSsid = "";
      _directPass = "";
    });
    _indexRoom(room);
    if (direct) await _ownDirect();
  }

  Future<void> _indexRoom(IncomingRoom room) async {
    final saved = await _catalog.loadKeys();
    room.knownKeys.addAll(saved);
    room.noteIndexed(
      saved.length,
      saved.isEmpty
          ? "Lendo a memória interna e o cartão para montar o banco..."
          : "Banco deste aparelho: ${saved.length} arquivos. Atualizando a leitura...",
    );
    final rows = <({String name, int bytes, String category, String path})>[];
    var seen = 0;
    final total = await indexStorage(_volumes, (path, name, bytes) {
      final category = categoryFor(path);
      room.knownKeys.add("$name|$bytes");
      room.knownKeys.add("${safeName(name)}|$bytes");
      rows.add((name: name, bytes: bytes, category: category, path: path));
      seen++;
      if (seen % 400 == 0) {
        room.noteIndexed(seen, "Conferindo interna e cartão: $seen arquivos");
      }
    });
    if (rows.isNotEmpty) await _catalog.saveAll(rows);
    if (!mounted) return;
    room.noteIndexed(total, "Banco pronto: $total arquivos na interna e no cartão. O que já existir não será enviado de novo.");
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

  String _direct = "";
  String _directSsid = "";
  String _directPass = "";
  final _name = TextEditingController();

  Future<void> _ownDirect() async {
    final name = _name.text.trim().isEmpty ? "Sincro" : _name.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("directName", name);
    await DeviceBridge.p2pName(name);
    final ok = await DeviceBridge.p2pOwn();
    if (!ok && mounted) {
      setState(() => _direct = "Permita aparelhos próximos para criar a rede direta.");
      return;
    }
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final status = await DeviceBridge.p2pStatus();
      final ip = status["ip"]?.toString();
      final ssid = status["ssid"]?.toString() ?? "";
      final pass = status["passphrase"]?.toString() ?? "";
      if (!mounted) return;
      if (ip != null && ip.isNotEmpty && ip != "null") {
        _room?.showAddress(ip);
        setState(() {
          _directSsid = ssid;
          _directPass = pass;
          _direct = ssid.isEmpty
              ? "Rede de $name criada. Esperando a senha do Wi-Fi Direct..."
              : "Rede de $name pronta. Mostre este QR. O outro aceita uma vez só.";
        });
        if (ssid.isNotEmpty && pass.isNotEmpty) return;
      } else {
        setState(() => _direct = status["message"]?.toString() ?? "Criando a rede de $name...");
      }
    }
  }

  String _qrLink(IncomingRoom room) {
    if (_link == "direta") {
      if (_directSsid.isEmpty || room.ip == null || !room.ip!.startsWith("192.168.49.")) return "";
    }
    if (room.ip == null || room.ip!.isEmpty) return "";
    return Uri(
      scheme: "sincro",
      host: room.ip,
      port: room.port,
      queryParameters: {
        "c": room.code,
        if (_link == "direta" && _directSsid.isNotEmpty) "s": _directSsid,
        if (_link == "direta" && _directPass.isNotEmpty) "k": _directPass,
        if (_link == "direta" && _name.text.trim().isNotEmpty) "n": _name.text.trim(),
      },
    ).toString();
  }

  Future<void> _enterDirect(String ssid, String pass, String label) async {
    setState(() => _direct = "Aceite a rede de $label uma vez no aviso do Android. Se não aparecer, use o aparelho da lista.");
    await DeviceBridge.p2pJoinNet(ssid, pass);
    for (var i = 0; i < 16; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final status = await DeviceBridge.p2pStatus();
      final message = status["message"]?.toString() ?? "";
      if (!mounted) return;
      if (message.startsWith("Conectado")) {
        setState(() => _direct = "Ligado direto em $label. Agora digite o código de 3 letras.");
        return;
      }
      setState(() => _direct = message.isEmpty ? "Entrando na rede de $label..." : message);
    }
    if (mounted) {
      setState(() => _direct = "A rede direta não abriu. Toque no aparelho da lista (Wi-Fi de casa) e pareie.");
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
    final uri = Uri.parse(raw.trim());
    setState(() {
      _peer = peer;
      _manual.text = "${peer.address}:${peer.port}";
    });
    final ssid = uri.queryParameters["s"];
    final pass = uri.queryParameters["k"];
    if (_link == "direta" && ssid != null && pass != null && ssid.isNotEmpty && pass.isNotEmpty) {
      await _enterDirect(ssid, pass, uri.queryParameters["n"] ?? "o outro aparelho");
    }
    final code = uri.queryParameters["c"];
    if (code != null && code.isNotEmpty) {
      await _submitCode(code);
    }
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
      var target = peer;
      ({String token, String name})? paired;
      try {
        paired = await Sender.pair(target, code);
      } catch (error) {
        if (target.address.startsWith("192.168.49.")) {
          final lan = _peers.cast<FoundPeer?>().firstWhere(
            (item) => item != null && !item.address.startsWith("192.168.49.") && item.port == target.port,
            orElse: () => null,
          );
          if (lan != null && mounted) {
            setState(() => _status = "Rede direta não respondeu. Tentando pelo Wi-Fi de casa...");
            target = lan;
            paired = await Sender.pair(target, code);
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      if (paired == null) throw StateError("não pareou");
      if (!mounted) return;
      _peer = target;
      _peerLabel = paired.name;
      _token = paired.token;
      _resume = await ResumeStore.loadSession();
      unawaited(_pullCatalog());
      await _loadLibrary(paired.token);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        final text = error.toString();
        final hint = peer.address.startsWith("192.168.49.")
            ? " A rede direta não abriu. Toque no aparelho da lista (o do Wi-Fi de casa) e pareie de novo."
            : "";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Não pareou: $text$hint")));
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
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) => _hearPeer());
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
    for (final kind in ["images", "videos", "audio"]) {
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
    await _loadOtherFiles(token);
  }

  Future<void> _loadOtherFiles(String token) async {
    if (_loadingOthers || _token != token) return;
    _loadingOthers = true;
    final allowed = await DeviceBridge.hasAllFilesAccess();
    if (!mounted || _token != token) {
      _loadingOthers = false;
      return;
    }
    if (!allowed) {
      setState(() {
        _needAllFiles = true;
        _loadingLibrary = false;
        _loadingOthers = false;
        _status = "${_libraryStatus()} Para zip, PDF, Word e planilhas, permita o acesso a todos os arquivos.";
      });
      return;
    }
    setState(() {
      _needAllFiles = false;
      _status = "Lendo zip, PDF, Word, planilhas e áudio...";
    });
    for (final kind in ["files"]) {
      var offset = 0;
      while (mounted && _token == token && !_stop) {
        final page = await loadGalleryChunk(kind, offset);
        if (!mounted || _token != token) break;
        setState(() {
          final seen = _files.map((file) => file.path).toSet();
          for (final file in page.files) {
            if (!seen.add(file.path.isEmpty ? file.name : file.path)) continue;
            _files.add(file);
            if (_followAll) _selected.add(file.path);
          }
        });
        if (page.done || page.next <= offset) break;
        offset = page.next;
      }
    }
    if (!mounted || _token != token) {
      _loadingOthers = false;
      return;
    }
    final extras = await scanDocuments(await DeviceBridge.volumes());
    if (!mounted || _token != token) {
      _loadingOthers = false;
      return;
    }
    final known = _files.map((file) => file.path).toSet();
    setState(() {
      for (final file in extras) {
        if (!known.add(file.path)) continue;
        _files.add(file);
        if (_followAll) _selected.add(file.path);
      }
      _loadingLibrary = false;
      _loadingOthers = false;
      _needAllFiles = false;
      if (!_busy) _status = _libraryStatus();
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
    have.addAll(_remoteKeys);
    final chosen = picked.where((file) => !have.contains("${file.name}|${file.bytes}")).toList();
    if (chosen.isEmpty) {
      if (mounted) {
        setState(() => _status = "Esses arquivos já estão completos no outro aparelho. Nada novo para enviar.");
      }
      return;
    }
    final doneKeys = {...have};
    if (picked.length > chosen.length && mounted) {
      setState(() => _status = "Vou pular ${picked.length - chosen.length} arquivo(s) que já estão no outro aparelho.");
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
    try {
      await ResumeStore.saveSession(LastTransfer(peer: _peerLabel, files: picked, done: doneKeys));
      var jobDone = 0;
      var sentFiles = 0;
      for (var part = 0; part < batches.length; part++) {
        if (_stop) throw StateError("interrompido");
        final batch = batches[part];
        final offers = [
          for (var i = 0; i < batch.length; i++)
            Offer(id: "$i", name: batch[i].name, bytes: batch[i].bytes, category: batch[i].category),
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
      if (_leaving || _left) return;
      final text = error.toString();
      final remoteClosed = text.contains("Connection refused") ||
          text.contains("Connection reset") ||
          text.contains("Connection closed") ||
          text.contains("Broken pipe") ||
          text.contains("errno = 111") ||
          text.contains("errno = 104") ||
          text.contains("SocketException");
      if (remoteClosed) {
        _goHome = true;
      } else if (mounted) {
        setState(() => _status = _plainError(error));
      }
    } finally {
      await WakelockPlus.disable();
      await DeviceBridge.release();
      if (_goHome && mounted) {
        _goHome = false;
        _backToStart();
      } else if (mounted && !_left) {
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

  Future<void> _pullCatalog() async {
    final peer = _peer;
    final token = _token;
    if (peer == null || token == null) return;
    final keys = await Sender.catalog(peer, token);
    if (!mounted || keys.isEmpty) return;
    setState(() {
      _remoteKeys = keys;
      if (!_busy) {
        _status = "O outro aparelho já tem ${keys.length} arquivos no banco. O que for igual não será enviado.";
      }
    });
  }

  Future<void> _hearPeer() async {
    if (_hearing || _leaving || _left || _peer == null || _token == null) return;
    _hearing = true;
    try {
      final state = await Sender.pulse(_peer!, _token!, await _level());
      if (!mounted || _left) return;
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
      if (state["bye"] == true) await _agreeToClose();
    } catch (_) {
    } finally {
      _hearing = false;
    }
  }

  Future<void> _agreeToClose() async {
    if (_leaving || _left) return;
    _leaving = true;
    _stop = true;
    final peer = _peer;
    final token = _token;
    if (peer != null && token != null) {
      try {
        await Sender.bye(peer, token);
      } catch (_) {}
    }
    _backToStart();
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
    _leaving = true;
    final peer = _peer;
    final token = _token;
    if (room != null) room.askToClose();
    if (peer != null && token != null) {
      try {
        await Sender.bye(peer, token);
      } catch (_) {}
    }
    if (room != null && !room.ended) {
      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (!room.ended && DateTime.now().isBefore(deadline) && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    _backToStart();
  }

  void _backToStart() {
    if (!mounted || _left) return;
    _left = true;
    _stop = true;
    _poll?.cancel();
    final room = _room;
    _room = null;
    room?.cancel.cancelled = true;
    room?.close();
    WakelockPlus.disable();
    DeviceBridge.release();
    if (_link == "direta") DeviceBridge.p2pStop();
    setState(() {
      _role = null;
      _link = null;
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
                  const Text("Escolha uma forma de ligar os aparelhos. Só uma fica ativa por vez."),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => setState(() => _link = "casa"),
                    icon: const Icon(Icons.wifi),
                    label: const Text("Wi-Fi de casa"),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _link = "direta"),
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text("Rede direta"),
                  ),
                  if (_link != null) ...[
                    const SizedBox(height: 20),
                    Text(_link == "casa"
                        ? "Os dois no mesmo Wi-Fi. Quem recebe mostra o QR. Quem envia lê e já entra."
                        : "O celular cria a rede e mostra o QR. O tablet lê, aceita a rede uma vez e só recebe."),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _receive(direct: _link == "direta"),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text("Receber neste aparelho"),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _role = "send");
                        if (_link == "casa") _scanPeers();
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text("Enviar para o outro"),
                    ),
                  ],
                ],
              )
            : room != null
                ? _receiveBody(room)
                : _sendBody(),
      ),
    );
  }

  Widget _receiveBody(IncomingRoom room) {
    final link = _qrLink(room);
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
        if (link.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_link == "direta" ? "QR da rede direta" : "QR do Wi-Fi de casa", textAlign: TextAlign.center),
          Center(child: QrImageView(data: link, size: 160, backgroundColor: Colors.white)),
          Text("O outro lê este QR e já entra. Não precisa digitar código.", textAlign: TextAlign.center),
        ],
        const SizedBox(height: 12),
        Text("Modo ${modeLabel(widget.settings.mode)}. ${modeHint(widget.settings.mode)}"),
        Text(
          _sd == null
              ? "Não achei cartão SD neste aparelho. Os arquivos vão para a memória interna, em pastas Imagens, Vídeos e Arquivos."
              : "Primeiro o cartão SD (${formatBytes(_sd!.freeBytes)} livres). A memória interna só recebe o que não couber no cartão.",
        ),
        if (_direct.isNotEmpty) Text(_direct),
        if (_link == "direta") ...[
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: "Nome deste aparelho na rede direta"),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _ownDirect,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text("Criar rede direta"),
          ),
        ],
        if (room.indexLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(room.indexLabel),
        ],
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
          Text(_link == "direta"
              ? "No aparelho que recebe, crie a rede direta e mostre o QR. Aqui só leia esse QR e aceite uma vez."
              : "Os dois no mesmo Wi-Fi. Aponte a câmera para o QR ou toque no aparelho da lista."),
          const SizedBox(height: 12),
          if (_direct.isNotEmpty) Text(_direct),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _openCamera, child: const Text("Abrir câmera e ler o QR")),
          if (_link == "casa") ...[
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
          ],
          if (_peer != null && _token == null) ...[
            const SizedBox(height: 16),
            Text("Lendo o QR já conecta. Se preferir, digite o código de 3 letras."),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: "Código (opcional)"),
            ),
            FilledButton(
              onPressed: _busy || _code.text.trim().length < 3 ? null : () => _submitCode(_code.text.trim().toUpperCase()),
              child: Text(_busy ? "Conectando..." : "Conectar"),
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
          if (_needAllFiles && !_busy)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.icon(
                onPressed: () => DeviceBridge.requestAllFilesAccess(),
                icon: const Icon(Icons.folder_zip_outlined),
                label: const Text("Permitir zip, PDF, Word e planilhas"),
              ),
            ),
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
