import "dart:io";

import "device_bridge.dart";

class LocalFile {
  LocalFile({
    required this.path,
    required this.name,
    required this.bytes,
    required this.category,
    this.uri,
  });

  final String path;
  final String name;
  final int bytes;
  final String category;
  final String? uri;

  factory LocalFile.fromMap(Map<dynamic, dynamic> map) {
    return LocalFile(
      path: map["path"] as String? ?? "",
      name: map["name"] as String? ?? "arquivo",
      bytes: (map["bytes"] as num?)?.toInt() ?? 0,
      category: map["category"] as String? ?? "Outros",
      uri: map["uri"] as String?,
    );
  }
}

const _folders = ["DCIM", "Pictures", "Movies", "Download", "Documents", "WhatsApp/Media", "Telegram"];

String categoryFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith(".jpg") ||
      lower.endsWith(".jpeg") ||
      lower.endsWith(".png") ||
      lower.endsWith(".heic") ||
      lower.endsWith(".webp") ||
      lower.endsWith(".gif") ||
      lower.endsWith(".bmp") ||
      lower.endsWith(".dng")) {
    return "Fotos";
  }
  if (lower.endsWith(".mp4") ||
      lower.endsWith(".mov") ||
      lower.endsWith(".mkv") ||
      lower.endsWith(".3gp") ||
      lower.endsWith(".webm")) {
    return "Vídeos";
  }
  if (lower.endsWith(".pdf") ||
      lower.endsWith(".doc") ||
      lower.endsWith(".docx") ||
      lower.endsWith(".txt") ||
      lower.endsWith(".xls") ||
      lower.endsWith(".xlsx")) {
    return "Documentos";
  }
  if (lower.contains("/download/")) return "Downloads";
  return "Outros";
}

Future<List<LocalFile>> scanFiles(List<VolumeInfo> volumes) async {
  final found = <LocalFile>[];
  final seen = <String>{};
  try {
    final raw = await DeviceBridge.gallery();
    for (final item in raw) {
      final file = LocalFile.fromMap(item);
      if (file.bytes <= 0) continue;
      final key = file.path.isNotEmpty ? file.path : (file.uri ?? file.name);
      if (!seen.add(key)) continue;
      found.add(file);
    }
  } catch (_) {}
  for (final volume in volumes) {
    for (final folder in _folders) {
      final root = Directory("${volume.path}/$folder");
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (found.length >= 15000) return found;
          if (entity is! File) continue;
          final path = entity.path;
          if (path.contains("/.") || path.contains("/Android/")) continue;
          if (!seen.add(path)) continue;
          final category = categoryFor(path);
          if (category == "Fotos" || category == "Vídeos" || category == "Outros") continue;
          final stat = await entity.stat();
          if (stat.size <= 0) continue;
          found.add(LocalFile(path: path, name: path.split("/").last, bytes: stat.size, category: category));
        }
      } catch (_) {}
    }
  }
  return found;
}

Future<File> readableFile(LocalFile file) async {
  if (file.path.startsWith("/")) {
    final direct = File(file.path);
    try {
      if (await direct.exists()) {
        final handle = await direct.open();
        await handle.close();
        return direct;
      }
    } catch (_) {}
  }
  final staged = await DeviceBridge.stageMedia(file.path, file.uri ?? "");
  return File(staged);
}
