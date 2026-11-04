import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";
import "dart:typed_data";

import "package:battery_plus/battery_plus.dart";
import "package:flutter/foundation.dart";

import "device_bridge.dart";
import "planner.dart";
import "scanner.dart";
import "tcp_pipe.dart";
import "transfer.dart";

const beaconPort = 45821;

String makeCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  final random = Random.secure();
  return List.generate(3, (_) => alphabet[random.nextInt(alphabet.length)]).join();
}

List<String> decoysFor(String code) {
  final options = {code};
  while (options.length < 3) {
    options.add(makeCode());
  }
  final list = options.toList()..shuffle(Random());
  return list;
}

class FoundPeer {
  FoundPeer({required this.name, required this.address, required this.port});

  final String name;
  final String address;
  final int port;

  String get key => "$address:$port";
}

class Offer {
  Offer({required this.id, required this.name, required this.bytes, this.category = "Arquivos"});

  final String id;
  final String name;
  final int bytes;
  final String category;

  Map<String, Object> toJson() => {"id": id, "name": name, "bytes": bytes, "category": category};

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(
      id: json["id"].toString(),
      name: json["name"] as String,
      bytes: (json["bytes"] as num).toInt(),
      category: json["category"] as String? ?? "Arquivos",
    );
  }
}

class IncomingRoom extends ChangeNotifier {
  IncomingRoom({required this.deviceName});

  final String deviceName;
  final String code = makeCode();
  HttpServer? _server;
  ServerSocket? _tcp;
  RawDatagramSocket? _beacon;
  Timer? _timer;
  String? token;
  bool paired = false;
  String status = "Aguardando o outro aparelho na mesma rede Wi-Fi";
  List<Offer> offers = [];
  List<Placement> plan = [];
  bool decided = false;
  int port = 0;
  int tcpPort = 0;
  String? ip;
  int receivedBytes = 0;
  int totalBytes = 0;
  String current = "";
  bool finished = false;
  bool pauseHere = false;
  bool pauseThere = false;
  bool keepGoing = false;
  bool ended = false;
  bool wantClose = false;
  int? peerBattery;
  int jobBytes = 0;
  int jobDone = 0;
  int part = 1;
  int parts = 1;
  bool get paused => pauseHere || pauseThere;
  final knownKeys = <String>{};
  int indexed = 0;
  String indexLabel = "";
  final List<({String name, int bytes, String dest, String sourcePath})> saved = [];

  void noteIndexed(int count, String label) {
    indexed = count;
    indexLabel = label;
    notifyListeners();
  }
  final CancelFlag cancel = CancelFlag();

  Future<void> start(List<Placement> Function(List<Offer> offers) buildPlan, {required String internalPath, String? sdPath, bool announce = true}) async {
    _buildPlan = buildPlan;
    _internalPath = internalPath;
    _sdPath = sdPath;
    ip = await DeviceBridge.wifiAddress();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    port = _server!.port;
    _server!.listen(_onRequest, onError: (Object _) {});
    try {
      _tcp = await ServerSocket.bind(InternetAddress.anyIPv4, directTcpPort);
    } catch (_) {
      _tcp = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    }
    tcpPort = _tcp!.port;
    _tcp!.listen((socket) => unawaited(_serveChunks(socket)), onError: (Object _) {});
    if (announce) {
      _beacon = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _beacon!.broadcastEnabled = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _announce());
      _announce();
    }
    notifyListeners();
  }

  void stopAnnounce() {
    _timer?.cancel();
    _timer = null;
    _beacon?.close();
    _beacon = null;
  }

  List<Placement> Function(List<Offer> offers) _buildPlan = (offers) => [];

  void showAddress(String value) {
    ip = value;
    notifyListeners();
  }

  void _announce() {
    final text = "SINCRO1|$deviceName|$port";
    try {
      _beacon?.send(utf8.encode(text), InternetAddress("255.255.255.255"), beaconPort);
    } catch (_) {}
  }

  Future<void> accept(String internalPath, String? sdPath) async {
    keepGoing = true;
    _internalPath = internalPath;
    _sdPath = sdPath;
    _armReceipt();
    notifyListeners();
  }

  void _armReceipt() {
    decided = true;
    finished = false;
    receivedBytes = 0;
    current = "";
    saved.clear();
    totalBytes = plan.where((item) => item.dest != null).fold(0, (sum, item) => sum + item.bytes);
    status = parts > 1 ? "Recebendo parte $part de $parts" : "Recebendo arquivos";
  }

  void askToClose() {
    wantClose = true;
    status = "Encerrando a conexão...";
    notifyListeners();
  }

  void setLocalPause(bool value) {
    pauseHere = value;
    cancel.paused = paused;
    if (decided && !finished) status = paused ? "Transferência pausada" : "Recebendo arquivos";
    notifyListeners();
  }

  void _applyRemotePause(bool value) {
    pauseThere = value;
    cancel.paused = paused;
    if (decided && !finished) status = paused ? "Transferência pausada" : "Recebendo arquivos";
    notifyListeners();
  }

  String? _internalPath;
  String? _sdPath;

  Future<void> _onRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == "POST" && path == "/v1/pair") {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        if (body["code"] != code) {
          await _json(request, 401, {"ok": false});
          return;
        }
        token = makeCode() + makeCode();
        paired = true;
        status = "Pareado. Esperando a lista de arquivos.";
        notifyListeners();
        await _json(request, 200, {"ok": true, "token": token, "name": deviceName});
        return;
      }
      if (!_authorized(request)) {
        await _json(request, 401, {"ok": false});
        return;
      }
      if (request.method == "POST" && path == "/v1/manifest") {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        offers = [
          for (final item in body["files"] as List<dynamic>) Offer.fromJson(item as Map<String, dynamic>),
        ];
        peerBattery = (body["battery"] as num?)?.toInt();
        part = (body["part"] as num?)?.toInt() ?? 1;
        parts = (body["parts"] as num?)?.toInt() ?? 1;
        jobBytes = (body["jobBytes"] as num?)?.toInt() ?? offers.fold(0, (sum, file) => sum + file.bytes);
        jobDone = (body["jobDone"] as num?)?.toInt() ?? 0;
        plan = _buildPlan(offers);
        if (keepGoing && _internalPath != null) {
          _armReceipt();
        } else {
          decided = false;
          finished = false;
          receivedBytes = 0;
          status = "O outro aparelho quer enviar ${offers.length} arquivo(s). Confira o destino.";
        }
        notifyListeners();
        await _json(request, 200, {"ok": true});
        return;
      }
      if (request.method == "POST" && path == "/v1/pulse") {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final remote = (body["battery"] as num?)?.toInt();
        if (remote != null && remote >= 0) peerBattery = remote;
        final level = await _batteryLevel();
        notifyListeners();
        await _json(request, 200, {
          "here": pauseHere,
          "there": pauseThere,
          "battery": level,
          "received": jobDone + receivedBytes,
          "total": jobBytes,
          "bye": wantClose,
        });
        return;
      }
      if (request.method == "GET" && path == "/v1/catalog") {
        final items = <Map<String, Object>>[];
        final seen = <String>{};
        for (final key in knownKeys) {
          if (!seen.add(key)) continue;
          final bar = key.lastIndexOf("|");
          if (bar <= 0) continue;
          final bytes = int.tryParse(key.substring(bar + 1));
          if (bytes == null) continue;
          items.add({"name": key.substring(0, bar), "bytes": bytes});
        }
        await _json(request, 200, {"count": items.length, "items": items});
        return;
      }
      if (request.method == "POST" && path == "/v1/present") {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final have = <String>[];
        for (final item in body["items"] as List<dynamic>? ?? []) {
          if (item is! Map) continue;
          final name = item["name"]?.toString() ?? "";
          final bytes = (item["bytes"] as num?)?.toInt() ?? 0;
          if (name.isEmpty || bytes <= 0) continue;
          if (await _hasComplete(name, bytes)) have.add("$name|$bytes");
        }
        await _json(request, 200, {"have": have});
        return;
      }
      if (request.method == "POST" && path == "/v1/bye") {
        await _json(request, 200, {"ok": true});
        await Future<void>.delayed(const Duration(milliseconds: 200));
        ended = true;
        wantClose = false;
        keepGoing = false;
        cancel.cancelled = true;
        status = "Conexão encerrada.";
        notifyListeners();
        return;
      }
      if (request.method == "GET" && path == "/v1/pause") {
        await _json(request, 200, {"here": pauseHere, "there": pauseThere});
        return;
      }
      if (request.method == "POST" && path == "/v1/pause") {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        _applyRemotePause(body["paused"] == true);
        await _json(request, 200, {"ok": true, "here": pauseHere, "there": pauseThere});
        return;
      }
      if (request.method == "GET" && path == "/v1/decision") {
        await _json(request, 200, {
          "ready": decided,
          "battery": await _batteryLevel(),
          "placements": [
            for (final item in plan) {"id": idFor(item), "dest": item.dest?.name, "reason": item.reason},
          ],
        });
        return;
      }
      if (request.method == "PUT" && path.startsWith("/v1/file/")) {
        final id = path.split("/").last;
        final index = offers.indexWhere((offer) => offer.id == id);
        if (index < 0 || index >= plan.length || !decided) {
          await _json(request, 409, {"ok": false});
          return;
        }
        final item = plan[index];
        if (item.dest == null) {
          await _json(request, 409, {"ok": false});
          return;
        }
        final root = item.dest == Dest.sd ? _sdPath : _internalPath;
        if (root == null) {
          await _json(request, 409, {"ok": false, "error": "destino indisponível"});
          return;
        }
        current = item.name;
        final prepared = await preparePut(id);
        if (prepared == null) {
          await _json(request, 409, {"ok": false, "error": "destino indisponível"});
          return;
        }
        if (prepared.already) {
          noteDone(prepared.name, prepared.bytes, prepared.destName, prepared.file.path);
          await _json(request, 201, {"ok": true, "sha256": "existente"});
          return;
        }
        final dest = prepared.file;
        final hash = await writeHashed(
          source: request,
          dest: dest,
          total: prepared.bytes,
          cancel: cancel,
          onProgress: noteChunk,
        );
        noteDone(prepared.name, prepared.bytes, prepared.destName, dest.path);
        await _json(request, 201, {"ok": true, "sha256": hash});
        return;
      }
      if (request.method == "POST" && path == "/v1/finish") {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        if (body["more"] != true) parts = part;
        finished = true;
        status = part < parts ? "Parte $part concluída. Esperando a próxima." : "Transferência verificada";
        notifyListeners();
        await _json(request, 200, {"ok": true});
        return;
      }
      await _json(request, 404, {"ok": false});
    } catch (error) {
      try {
        await _json(request, 500, {"ok": false, "error": error.toString()});
      } catch (_) {}
    }
  }

  String idFor(Placement item) {
    final index = plan.indexOf(item);
    if (index < 0 || index >= offers.length) return item.name;
    return offers[index].id;
  }

  bool _authorized(HttpRequest request) {
    if (token == null) return false;
    return request.headers.value("authorization") == "Bearer $token";
  }

  Future<bool> _hasComplete(String name, int bytes) async {
    final clean = safeName(name);
    if (knownKeys.contains("$clean|$bytes") || knownKeys.contains("$name|$bytes")) return true;
    for (final root in [_internalPath, _sdPath]) {
      if (root == null || root.isEmpty) continue;
      final file = File("$root/SincroLocal/$clean");
      if (await file.exists() && await file.length() == bytes) return true;
    }
    return false;
  }

  Future<({File file, bool already, int bytes, String name, String destName})?> preparePut(String id) async {
    final index = offers.indexWhere((offer) => offer.id == id);
    if (index < 0 || index >= plan.length || !decided) return null;
    final item = plan[index];
    if (item.dest == null) return null;
    final root = item.dest == Dest.sd ? _sdPath : _internalPath;
    if (root == null) return null;
    current = item.name;
    final category = index < offers.length ? offers[index].category : "Arquivos";
    final target = await incomingTarget(Directory("$root/SincroLocal/${shelfFor(category)}"), item.name, item.bytes);
    return (file: target.file, already: target.alreadyThere, bytes: item.bytes, name: item.name, destName: item.dest!.name);
  }

  void noteChunk(int written) {
    receivedBytes = saved.fold<int>(0, (sum, file) => sum + file.bytes) + written;
    notifyListeners();
  }

  void noteDone(String name, int bytes, String destName, String path) {
    saved.add((name: name, bytes: bytes, dest: destName, sourcePath: path));
    status = "Recebido $name";
    receivedBytes = saved.fold<int>(0, (sum, file) => sum + file.bytes);
    notifyListeners();
  }

  Future<void> _serveChunks(Socket socket) async {
    final reader = ChunkReader(socket);
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      if (await reader.line() != "SINCROFILE") return;
      while (!cancel.cancelled) {
        final header = await reader.line();
        if (header == "BYE" || header.isEmpty) break;
        final meta = jsonDecode(header);
        if (meta is! Map || meta["token"] != token) {
          socket.write("NO\n");
          await socket.flush();
          break;
        }
        final prepared = await preparePut(meta["id"].toString());
        if (prepared == null) {
          socket.write("NO\n");
          await socket.flush();
          continue;
        }
        if (prepared.already) {
          noteDone(prepared.name, prepared.bytes, prepared.destName, prepared.file.path);
          socket.write("SKIP\n");
          await socket.flush();
          continue;
        }
        socket.write("GO\n");
        await socket.flush();
        final out = prepared.file.openWrite();
        var got = 0;
        try {
          while (got < prepared.bytes) {
            while (cancel.paused && !cancel.cancelled) {
              await Future.delayed(const Duration(milliseconds: 200));
            }
            if (cancel.cancelled) break;
            final rest = prepared.bytes - got;
            final size = rest > chunkBytes ? chunkBytes : rest;
            final block = await reader.take(size);
            out.add(block);
            got += block.length;
            noteChunk(got);
            socket.write("ACK\n");
            await socket.flush();
          }
          await out.flush();
          await out.close();
          if (got != prepared.bytes) {
            if (await prepared.file.exists()) await prepared.file.delete();
            socket.write("ERR\n");
            await socket.flush();
            continue;
          }
          noteDone(prepared.name, prepared.bytes, prepared.destName, prepared.file.path);
          socket.write("OK\n");
          await socket.flush();
        } catch (error) {
          try {
            await out.close();
          } catch (_) {}
          if (await prepared.file.exists()) await prepared.file.delete();
          rethrow;
        }
      }
    } catch (_) {
    } finally {
      await reader.close();
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    _timer?.cancel();
    _beacon?.close();
    await _server?.close(force: true);
    await _tcp?.close();
  }
}

Future<int> _batteryLevel() async {
  try {
    return await Battery().batteryLevel;
  } catch (_) {
    return -1;
  }
}

Future<void> _json(HttpRequest request, int code, Object body) async {
  request.response.statusCode = code;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

class Sender {
  static Future<List<FoundPeer>> listen({Duration duration = const Duration(seconds: 4)}) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, beaconPort, reuseAddress: true);
    final found = <String, FoundPeer>{};
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null) return;
      final text = utf8.decode(packet.data, allowMalformed: true);
      final parts = text.split("|");
      if (parts.length != 3 || parts[0] != "SINCRO1") return;
      final port = int.tryParse(parts[2]);
      if (port == null) return;
      final peer = FoundPeer(name: parts[1], address: packet.address.address, port: port);
      found[peer.key] = peer;
    });
    await Future.delayed(duration);
    await sub.cancel();
    socket.close();
    return found.values.toList();
  }

  static Future<({String token, String name})> pair(FoundPeer peer, String code) async {
    final body = await _post(peer, "/v1/pair", {"code": code}, null, timeout: const Duration(seconds: 8));
    if (body["ok"] != true) throw StateError("Código recusado");
    return (token: body["token"] as String, name: body["name"] as String? ?? peer.name);
  }

  static Future<void> manifest(
    FoundPeer peer,
    String token,
    List<Offer> files, {
    required int battery,
    required int part,
    required int parts,
    required int jobBytes,
    required int jobDone,
  }) async {
    await _post(peer, "/v1/manifest", {
      "files": files.map((file) => file.toJson()).toList(),
      "battery": battery,
      "part": part,
      "parts": parts,
      "jobBytes": jobBytes,
      "jobDone": jobDone,
    }, token);
  }

  static Future<Map<String, dynamic>> decision(FoundPeer peer, String token) async {
    return _get(peer, "/v1/decision", token);
  }

  static Future<Set<String>> catalog(FoundPeer peer, String token) async {
    try {
      final body = await _get(peer, "/v1/catalog", token);
      return {
        for (final item in body["items"] as List<dynamic>? ?? [])
          if (item is Map) "${item["name"]}|${item["bytes"]}",
      };
    } catch (_) {
      return {};
    }
  }

  static Future<Set<String>> present(FoundPeer peer, String token, List<LocalFile> files) async {
    try {
      final body = await _post(peer, "/v1/present", {
        "items": [
          for (final file in files) {"name": file.name, "bytes": file.bytes},
        ],
      }, token);
      return {for (final item in body["have"] as List<dynamic>? ?? []) item.toString()};
    } catch (_) {
      return {};
    }
  }

  static Future<void> bye(FoundPeer peer, String token) async {
    await _post(peer, "/v1/bye", {}, token);
  }

  static Future<void> _uploadChunks(
    FoundPeer peer,
    String token,
    Offer offer,
    File file,
    void Function(int sent) onProgress,
    Future<void> Function() gate,
  ) async {
    final socket = await Socket.connect(peer.address, directTcpPort, timeout: const Duration(seconds: 3));
    final reader = ChunkReader(socket);
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      final length = await file.length();
      socket.write("SINCROFILE\n");
      socket.write("${jsonEncode({"token": token, "id": offer.id, "name": offer.name, "bytes": length})}\n");
      await socket.flush();
      final answer = await reader.line().timeout(const Duration(seconds: 8));
      if (answer == "SKIP") {
        onProgress(length);
        return;
      }
      if (answer != "GO") throw StateError("direto recusou");
      final pending = BytesBuilder(copy: false);
      var held = 0;
      var sent = 0;
      Future<void> push() async {
        if (held == 0) return;
        socket.add(pending.takeBytes());
        held = 0;
        await socket.flush();
        final ack = await reader.line().timeout(const Duration(seconds: 30));
        if (ack != "ACK") throw StateError("bloco sem confirmação");
      }

      await for (final data in file.openRead()) {
        await gate();
        pending.add(data);
        held += data.length;
        sent += data.length;
        onProgress(sent);
        if (held >= chunkBytes) await push();
      }
      await push();
      final end = await reader.line().timeout(const Duration(seconds: 30));
      if (end != "OK") throw StateError("o outro não confirmou o arquivo");
    } finally {
      await reader.close();
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  static Future<void> upload(
    FoundPeer peer,
    String token,
    Offer offer,
    File file,
    void Function(int sent) onProgress,
    Future<void> Function() gate,
  ) async {
    try {
      await _uploadChunks(peer, token, offer, file, onProgress, gate);
      return;
    } on SocketException {
      // A porta direta não abriu. Segue pelo HTTP.
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.putUrl(Uri.parse("http://${peer.address}:${peer.port}/v1/file/${offer.id}"));
      request.headers.set("authorization", "Bearer $token");
      var sent = 0;
      final stream = file.openRead().asyncMap((data) async {
        await gate();
        sent += data.length;
        onProgress(sent);
        return data;
      });
      request.contentLength = await file.length();
      await request.addStream(stream);
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 300) throw StateError(raw);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> pulse(FoundPeer peer, String token, int battery) {
    return _post(peer, "/v1/pulse", {"battery": battery}, token);
  }

  static Future<Map<String, dynamic>> pauseState(FoundPeer peer, String token) {
    return _get(peer, "/v1/pause", token);
  }

  static Future<void> setPause(FoundPeer peer, String token, bool paused) async {
    await _post(peer, "/v1/pause", {"paused": paused}, token);
  }

  static Future<void> finish(FoundPeer peer, String token, {bool more = false}) async {
    await _post(peer, "/v1/finish", {"more": more}, token);
  }

  static Future<Map<String, dynamic>> _post(
    FoundPeer peer,
    String path,
    Object body,
    String? token, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(Uri.parse("http://${peer.address}:${peer.port}$path"));
      if (token != null) request.headers.set("authorization", "Bearer $token");
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (response.statusCode >= 300) throw StateError(json["error"]?.toString() ?? "Falha na rede");
      return json;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _get(FoundPeer peer, String path, String token) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.getUrl(Uri.parse("http://${peer.address}:${peer.port}$path"));
      request.headers.set("authorization", "Bearer $token");
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}
