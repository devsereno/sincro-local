import "package:flutter/services.dart";

class VolumeInfo {
  VolumeInfo({
    required this.label,
    required this.path,
    required this.freeBytes,
    required this.totalBytes,
    required this.removable,
    required this.fat32,
  });

  final String label;
  final String path;
  final int freeBytes;
  final int totalBytes;
  final bool removable;
  final bool fat32;

  factory VolumeInfo.fromMap(Map<dynamic, dynamic> map) {
    return VolumeInfo(
      label: map["label"] as String? ?? "Volume",
      path: map["path"] as String? ?? "",
      freeBytes: (map["freeBytes"] as num?)?.toInt() ?? 0,
      totalBytes: (map["totalBytes"] as num?)?.toInt() ?? 0,
      removable: map["removable"] == true,
      fat32: map["fat32"] == true,
    );
  }
}

class DeviceBridge {
  static const _channel = MethodChannel("br.sincrolocal.sincro_local/device");

  static Future<bool> hasAllFilesAccess() async {
    try {
      return await _channel.invokeMethod<bool>("hasAllFilesAccess") == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAllFilesAccess() async {
    try {
      await _channel.invokeMethod("requestAllFilesAccess");
    } catch (_) {}
  }

  static Future<String> deviceModel() async {
    try {
      return await _channel.invokeMethod<String>("deviceModel") ?? "Este aparelho";
    } catch (_) {
      return "Este aparelho";
    }
  }

  static Future<String?> wifiAddress() async {
    try {
      return await _channel.invokeMethod<String>("wifiAddress");
    } catch (_) {
      return null;
    }
  }

  static Future<List<VolumeInfo>> volumes() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>("volumes");
      if (raw == null) return [];
      return raw.map((item) => VolumeInfo.fromMap(item as Map<dynamic, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> mediaAccess() async {
    try {
      return await _channel.invokeMethod<String>("mediaAccess") ?? "none";
    } catch (_) {
      return "none";
    }
  }

  static Future<bool>? _asking;

  static Future<bool> requestMediaAccess() {
    final current = _asking;
    if (current != null) return current;
    final run = _channel.invokeMethod<bool>("requestMediaAccess").then((value) => value == true).catchError((_) => false).whenComplete(() {
      _asking = null;
    });
    _asking = run;
    return run;
  }

  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod("openSettings");
    } catch (_) {}
  }

  static Future<Map<dynamic, dynamic>> galleryPage({
    required String kind,
    required int offset,
    int limit = 250,
  }) async {
    final raw = await _channel.invokeMethod<dynamic>("gallery", {
      "kind": kind,
      "offset": offset,
      "limit": limit,
    });
    if (raw is Map) return Map<dynamic, dynamic>.from(raw);
    return {"files": <dynamic>[], "next": offset, "done": true};
  }

  static Future<String> stageMedia(String path, String uri) async {
    final staged = await _channel.invokeMethod<String>("stageMedia", {"path": path, "uri": uri});
    if (staged == null || staged.isEmpty) throw StateError("não consegui abrir o arquivo");
    return staged;
  }

  static Future<void> multicast(bool on) async {
    try {
      await _channel.invokeMethod("multicast", {"on": on});
    } catch (_) {}
  }

  static Future<void> hold() async {
    try {
      await _channel.invokeMethod("hold");
    } catch (_) {}
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod("release");
    } catch (_) {}
  }

  static Future<bool> p2pOwn() async {
    try {
      return await _channel.invokeMethod<bool>("p2pOwn") == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> p2pName(String name) async {
    try {
      return await _channel.invokeMethod<bool>("p2pName", {"name": name}) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> p2pJoinNet(String ssid, String pass) async {
    try {
      return await _channel.invokeMethod<bool>("p2pJoinNet", {"ssid": ssid, "pass": pass}) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> p2pStop() async {
    try {
      await _channel.invokeMethod("p2pStop");
    } catch (_) {}
  }
    try {
      final raw = await _channel.invokeMethod<dynamic>("p2pStatus");
      if (raw is Map) return raw.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {}
    return {};
  }
}
