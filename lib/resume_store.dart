import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:sqflite/sqflite.dart";

import "scanner.dart";

class LastTransfer {
  LastTransfer({required this.peer, required this.files, required this.done});

  final String peer;
  final List<LocalFile> files;
  final Set<String> done;

  int get remaining => files.where((file) => !done.contains("${file.name}|${file.bytes}")).length;
}

class ResumeStore {
  static Future<File> _file(String name) async {
    final dir = await getDatabasesPath();
    return File(p.join(dir, name));
  }

  static Future<void> saveLibrary(List<LocalFile> files) async {
    final file = await _file("library.json");
    await file.writeAsString(jsonEncode([for (final item in files) item.toJson()]));
  }

  static Future<List<LocalFile>> loadLibrary() async {
    try {
      final file = await _file("library.json");
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map) LocalFile.fromJson(item.cast<String, dynamic>()),
      ].where((item) => item.bytes > 0 && item.path.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSession(LastTransfer session) async {
    final file = await _file("last_transfer.json");
    await file.writeAsString(jsonEncode({
      "peer": session.peer,
      "done": session.done.toList(),
      "files": [for (final item in session.files) item.toJson()],
    }));
  }

  static Future<LastTransfer?> loadSession() async {
    try {
      final file = await _file("last_transfer.json");
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final files = [
        for (final item in (raw["files"] as List<dynamic>? ?? []))
          if (item is Map) LocalFile.fromJson(item.cast<String, dynamic>()),
      ];
      if (files.isEmpty) return null;
      return LastTransfer(
        peer: raw["peer"] as String? ?? "",
        files: files,
        done: {for (final item in (raw["done"] as List<dynamic>? ?? [])) item.toString()},
      );
    } catch (_) {
      return null;
    }
  }
}
