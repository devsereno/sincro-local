import "package:path/path.dart" as p;
import "package:sqflite/sqflite.dart";

class CatalogStore {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, "sincro_catalog.db"),
      version: 1,
      onCreate: (db, version) async {
        await db.execute("""
          CREATE TABLE files (
            name TEXT NOT NULL,
            bytes INTEGER NOT NULL,
            category TEXT NOT NULL,
            path TEXT NOT NULL,
            PRIMARY KEY (name, bytes)
          )
        """);
      },
    );
    return _db!;
  }

  Future<Set<String>> loadKeys() async {
    final db = await _open();
    final rows = await db.query("files", columns: ["name", "bytes"]);
    return {
      for (final row in rows) "${row["name"]}|${row["bytes"]}",
    };
  }

  Future<void> saveAll(List<({String name, int bytes, String category, String path})> files) async {
    if (files.isEmpty) return;
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete("files");
      final batch = txn.batch();
      for (final file in files) {
        batch.insert("files", {
          "name": file.name,
          "bytes": file.bytes,
          "category": file.category,
          "path": file.path,
        });
      }
      await batch.commit(noResult: true);
    });
  }
}
