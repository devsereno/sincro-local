import "package:sqflite/sqflite.dart";
import "package:path/path.dart" as p;

class HistoryFile {
  HistoryFile({required this.name, required this.bytes, required this.dest, required this.sourcePath});

  final String name;
  final int bytes;
  final String dest;
  final String sourcePath;
}

class HistorySession {
  HistorySession({
    required this.id,
    required this.job,
    required this.mode,
    required this.peer,
    required this.at,
    required this.sourceDeleted,
    required this.files,
  });

  final int id;
  final String job;
  final String mode;
  final String peer;
  final int at;
  final bool sourceDeleted;
  final List<HistoryFile> files;
}

class HistoryStore {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, "sincro_local.db"),
      version: 1,
      onCreate: (db, version) async {
        await db.execute("""
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job TEXT NOT NULL,
            mode TEXT NOT NULL,
            peer TEXT NOT NULL,
            at INTEGER NOT NULL,
            source_deleted INTEGER NOT NULL
          )
        """);
        await db.execute("""
          CREATE TABLE files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            bytes INTEGER NOT NULL,
            dest TEXT NOT NULL,
            source_path TEXT NOT NULL
          )
        """);
      },
    );
    return _db!;
  }

  Future<int> add({
    required String job,
    required String mode,
    required String peer,
    required List<HistoryFile> files,
  }) async {
    final db = await _open();
    return db.transaction((txn) async {
      final id = await txn.insert("sessions", {
        "job": job,
        "mode": mode,
        "peer": peer,
        "at": DateTime.now().millisecondsSinceEpoch,
        "source_deleted": 0,
      });
      for (final file in files) {
        await txn.insert("files", {
          "session_id": id,
          "name": file.name,
          "bytes": file.bytes,
          "dest": file.dest,
          "source_path": file.sourcePath,
        });
      }
      return id;
    });
  }

  Future<List<HistorySession>> all() async {
    final db = await _open();
    final rows = await db.query("sessions", orderBy: "at DESC");
    final sessions = <HistorySession>[];
    for (final row in rows) {
      final files = await db.query("files", where: "session_id = ?", whereArgs: [row["id"]]);
      sessions.add(
        HistorySession(
          id: row["id"] as int,
          job: row["job"] as String,
          mode: row["mode"] as String,
          peer: row["peer"] as String,
          at: row["at"] as int,
          sourceDeleted: (row["source_deleted"] as int) == 1,
          files: [
            for (final file in files)
              HistoryFile(
                name: file["name"] as String,
                bytes: file["bytes"] as int,
                dest: file["dest"] as String,
                sourcePath: file["source_path"] as String,
              ),
          ],
        ),
      );
    }
    return sessions;
  }

  Future<void> markDeleted(int id) async {
    final db = await _open();
    await db.update("sessions", {"source_deleted": 1}, where: "id = ?", whereArgs: [id]);
  }
}
