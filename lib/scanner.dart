import "dart:io";

import "device_bridge.dart";

class LocalFile {
  LocalFile({required this.path, required this.name, required this.bytes, required this.category});

  final String path;
  final String name;
  final int bytes;
  final String category;
}

const _folders = ["DCIM", "Pictures", "Movies", "Download", "Documents", "WhatsApp/Media", "Telegram"];

String categoryFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith(".jpg") ||
      lower.endsWith(".jpeg") ||
      lower.endsWith(".png") ||
      lower.endsWith(".heic") ||
      lower.endsWith(".webp")) {
    return "Fotos";
  }
  if (lower.endsWith(".mp4") || lower.endsWith(".mov") || lower.endsWith(".mkv") || lower.endsWith(".3gp")) {
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
  for (final volume in volumes) {
    for (final folder in _folders) {
      final root = Directory("${volume.path}/$folder");
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (found.length >= 2500) return found;
          if (entity is! File) continue;
          final path = entity.path;
          if (path.contains("/.") || path.contains("/Android/")) continue;
          final category = categoryFor(path);
          if (category == "Outros") continue;
          final stat = await entity.stat();
          if (stat.size <= 0) continue;
          found.add(LocalFile(path: path, name: path.split("/").last, bytes: stat.size, category: category));
        }
      } catch (_) {}
    }
  }
  found.sort((a, b) => b.bytes.compareTo(a.bytes));
  return found;
}
