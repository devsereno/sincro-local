import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:flutter/foundation.dart";

import "device_bridge.dart";
import "planner.dart";
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
  Offer({required this.id, required this.name, required this.bytes});

  final String id;
  final String name;
  final int bytes;

  Map<String, Object> toJson() => {"id": id, "name": name, "bytes": bytes};

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(id: json["id"].toString(), name: json["name"] as String, bytes: (json["bytes"] as num).toInt());
  }
}

class IncomingRoom extends ChangeNotifier {
  IncomingRoom({required this.deviceName});

  final String deviceName;
  final String code = makeCode();
  HttpServer? _server;
  RawDatagramSocket? _beacon;
  Timer? _timer;
  String? token;
  bool paired = false;
  String status = "Aguardando o outro aparelho na mesma rede Wi-Fi";
  List<Offer> offers = [];
  List<Placement> plan = [];
  bool decided = false;
  int port = 0;
  String? ip;
  int receivedBytes = 0;
  int totalBytes = 0;
  String current = "";
  bool finished = false;
  final List<({String name, int bytes, String dest, String sourcePath})> saved = [];
  final CancelFlag cancel = CancelFlag();

  Future<void> start(List<Placement> Function(List<Offer> offers) buildPlan) async {
    _buildPlan = buildPlan;
    ip = await DeviceBridge.wifiAddress();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    port = _server!.port;
    _server!.listen(_onRequest, onError: (Object _) {});
    _beacon = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _beacon!.broadcastEnabled = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _announce());
    _announce();
    notifyListeners();
  }

  List<Placement> Function(List<Offer> offers) _buildPlan = (offers) => [];

  void _announce() {
    final text = "SINCRO1|$deviceName|$port";
    try {
      _beacon?.send(utf8.encode(text), InternetAddress("255.255.255.255"), beaconPort);
    } catch (_) {}
  }

  Future<void> accept(String internalPath, String? sdPath) async {
    decided = true;
    _internalPath = internalPath;
    _sdPath = sdPath;
    totalBytes = plan.where((item) => item.dest != null).fold(0, (sum, item) => sum + item.bytes);
    status = "Recebendo arquivos";
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
        await _json(request, 200, {"ok": true, "token": token});
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
        plan = _buildPlan(offers);
        decided = false;
        status = "O outro aparelho quer enviar ${offers.length} arquivo(s). Confira o destino.";
        notifyListeners();
        await _json(request, 200, {"ok": true});
        return;
      }
      if (request.method == "GET" && path == "/v1/decision") {
        await _json(request, 200, {
          "ready": decided,
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
        final dest = await uniqueFile(Directory("$root/SincroLocal"), item.name);
        final hash = await writeHashed(
          source: request,
          dest: dest,
          total: item.bytes,
          cancel: cancel,
          onProgress: (written) {
            receivedBytes = saved.fold<int>(0, (sum, file) => sum + file.bytes) + written;
            notifyListeners();
          },
        );
        saved.add((name: item.name, bytes: item.bytes, dest: item.dest!.name, sourcePath: dest.path));
        status = "Recebido ${item.name}";
        notifyListeners();
        await _json(request, 201, {"ok": true, "sha256": hash});
        return;
      }
      if (request.method == "POST" && path == "/v1/finish") {
        finished = true;
        status = "Transferência verificada";
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

  Future<void> close() async {
    _timer?.cancel();
    _beacon?.close();
    await _server?.close(force: true);
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

  static Future<String> pair(FoundPeer peer, String code) async {
    final body = await _post(peer, "/v1/pair", {"code": code}, null);
    if (body["ok"] != true) throw StateError("Código recusado");
    return body["token"] as String;
  }

  static Future<void> manifest(FoundPeer peer, String token, List<Offer> files) async {
    await _post(peer, "/v1/manifest", {"files": files.map((file) => file.toJson()).toList()}, token);
  }

  static Future<Map<String, dynamic>> decision(FoundPeer peer, String token) async {
    return _get(peer, "/v1/decision", token);
  }

  static Future<void> upload(
    FoundPeer peer,
    String token,
    Offer offer,
    File file,
    void Function(int sent) onProgress,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.putUrl(Uri.parse("http://${peer.address}:${peer.port}/v1/file/${offer.id}"));
      request.headers.set("authorization", "Bearer $token");
      var sent = 0;
      final stream = file.openRead().transform<List<int>>(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) {
            sent += data.length;
            onProgress(sent);
            sink.add(data);
          },
        ),
      );
      request.contentLength = await file.length();
      await request.addStream(stream);
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 300) throw StateError(raw);
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> finish(FoundPeer peer, String token) async {
    await _post(peer, "/v1/finish", {}, token);
  }

  static Future<Map<String, dynamic>> _post(
    FoundPeer peer,
    String path,
    Object body,
    String? token,
  ) async {
    final client = HttpClient();
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
    final client = HttpClient();
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
