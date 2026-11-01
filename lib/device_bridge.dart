import "package:flutter/services.dart";

class VolumeInfo {
  VolumeInfo({required this.label, required this.path, required this.freeBytes, required this.totalBytes, required this.removable, required this.fat32});
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
  static const _channel = MethodChannel("br.sincrolocal.sincrolocal/device");
  static Future<bool> hasAllFilesAccess() async {
    try { return await _channel.invokeMethod<bool>("hasAllFilesAccess") == true; } catch (_) { return false; }
  }
  static Future<void> requestAllFilesAccess() async {
    try { await _channel.invokeMethod("requestAllFilesAccess"); } catch (_) {}
  }
  static Future<String> deviceModel() async {
    try { return await _channel.invokeMethod<String>("deviceModel") ?? "Este aparelho"; } catch (_) { return "Este aparelho"; }
  }
  static Future<String?> wifiAddress() async {
    try { return await _channel.invokeMethod<String>("wifiAddress"); } catch (_) { return null; }
  }
  static Future<List<VolumeInfo>> volumes() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>("volumes");
      if (raw == null) return [];
      return raw.map((item) => VolumeInfo.fromMap(item as Map<dynamic, dynamic>)).toList();
    } catch (_) { return []; }
  }
  static Future<void> hold() async { try { await _channel.invokeMethod("hold"); } catch (_) {} }
  static Future<void> release() async { try { await _channel.invokeMethod("release"); } catch (_) {} }
}
