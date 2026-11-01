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

  Map<String, Object?> toJson() => {
        "path": path,
        "name": name,
        "bytes": bytes,
        "category": category,
        if (uri != null) "uri": uri,
      };

  factory LocalFile.fromJson(Map<String, dynamic> json) {
    return LocalFile.fromMap(json);
  }

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

String shelfFor(String category) {
  if (category == "Fotos") return "Imagens";
  if (category == "Vídeos") return "Vídeos";
  return "Arquivos";
}

const _folders = ["Download", "Documents", "WhatsApp/Media", "Telegram"];

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
      lower.endsWith(".xlsx") ||
      lower.endsWith(".ppt") ||
      lower.endsWith(".pptx") ||
      lower.endsWith(".rtf")) {
    return "Documentos";
  }
  if (lower.endsWith(".apk") || lower.endsWith(".apks") || lower.endsWith(".xapk")) {
    return "Aplicativos";
  }
  if (lower.endsWith(".zip") ||
      lower.endsWith(".rar") ||
      lower.endsWith(".7z") ||
      lower.endsWith(".tar") ||
      lower.endsWith(".gz")) {
    return "Arquivos";
  }
  if (lower.endsWith(".mp3") ||
      lower.endsWith(".m4a") ||
      lower.endsWith(".aac") ||
      lower.endsWith(".wav") ||
      lower.endsWith(".ogg") ||
      lower.endsWith(".flac")) {
    return "Áudio";
  }
  if (lower.contains("/download/")) return "Downloads";
  return "Outros";
}

class GalleryChunk {
  GalleryChunk({required this.files, required this.next, required this.done});

  final List<LocalFile> files;
  final int next;
  final bool done;
}

Future<GalleryChunk> loadGalleryChunk(String kind, int offset, {int limit = 250}) async {
  final page = await DeviceBridge.galleryPage(kind: kind, offset: offset, limit: limit);
  final raw = page["files"];
  final files = <LocalFile>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      final file = LocalFile.fromMap(item);
      if (file.bytes <= 0) continue;
      files.add(file);
    }
  }
  return GalleryChunk(
    files: files,
    next: (page["next"] as num?)?.toInt() ?? offset,
    done: page["done"] == true,
  );
}

Future<List<LocalFile>> scanFiles(List<VolumeInfo> volumes) async {
  final found = <LocalFile>[];
  final seen = <String>{};
  try {
    for (final kind in ["images", "videos"]) {
      var offset = 0;
      while (found.length < 40000) {
        final page = await loadGalleryChunk(kind, offset, limit: 400);
        for (final file in page.files) {
          final key = file.path.isNotEmpty ? file.path : (file.uri ?? file.name);
          if (seen.add(key)) found.add(file);
        }
        if (page.done || page.next <= offset) break;
        offset = page.next;
      }
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
          if (category == "Fotos" || category == "Vídeos") continue;
          final stat = await entity.stat();
          if (stat.size <= 0) continue;
          found.add(LocalFile(path: path, name: path.split("/").last, bytes: stat.size, category: category));
        }
      } catch (_) {}
    }
  }
  return found;
}

Future<List<LocalFile>> scanDocuments(List<VolumeInfo> volumes) async {
  final found = <LocalFile>[];
  final seen = <String>{};
  for (final volume in volumes) {
    final root = Directory(volume.path);
    if (!await root.exists()) continue;
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (found.length >= 20000) return found;
        if (entity is! File) continue;
        final path = entity.path;
        if (_skipPath(path) || !seen.add(path)) continue;
        final category = categoryFor(path);
        if (category == "Fotos" || category == "Vídeos") continue;
        final stat = await entity.stat();
        if (stat.size <= 0) continue;
        found.add(LocalFile(path: path, name: path.split("/").last, bytes: stat.size, category: category));
        if (found.length % 200 == 0) await Future<void>.delayed(Duration.zero);
      }
    } catch (_) {}
  }
  return found;
}

Future<int> indexStorage(List<VolumeInfo> volumes, void Function(String path, String name, int bytes) onFile) async {
  final seen = <String>{};
  var count = 0;
  for (final volume in volumes) {
    final root = Directory(volume.path);
    if (!await root.exists()) continue;
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (count >= 80000) return count;
        if (entity is! File) continue;
        final path = entity.path;
        if (_skipPath(path) || !seen.add(path)) continue;
        final size = await entity.length().catchError((_) => 0);
        if (size <= 0) continue;
        count++;
        onFile(path, path.split("/").last, size);
        if (count % 250 == 0) await Future<void>.delayed(Duration.zero);
      }
    } catch (_) {}
  }
  return count;
}

bool _skipPath(String path) {
  return path.contains("/.") || path.contains("/Android/data") || path.contains("/Android/obb");
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
