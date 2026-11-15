import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'models.dart';

class LocalStore {
  LocalStore(this.directory) {
    Directory(directory).createSync(recursive: true);
    db = sqlite3.open('$directory${Platform.pathSeparator}lysia.sqlite');
    db.execute('PRAGMA journal_mode=WAL');
    db.execute(
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY, song TEXT NOT NULL, identity TEXT NOT NULL, first_heard INTEGER NOT NULL, last_heard INTEGER NOT NULL, count INTEGER NOT NULL DEFAULT 1)',
    );
  }
  static String get defaultDirectory =>
      File(Platform.resolvedExecutable).parent.path;
  static LocalStore openPortable() {
    final location = defaultDirectory;
    final exists = File(
      '$location${Platform.pathSeparator}lysia.sqlite',
    ).existsSync();
    final store = LocalStore(location);
    if (!exists) {
      final legacy =
          '${Platform.environment['LOCALAPPDATA']}${Platform.pathSeparator}Tingjian${Platform.pathSeparator}tingjian.sqlite';
      if (File(legacy).existsSync()) store.importLegacy(legacy);
    }
    return store;
  }

  void importLegacy(String path) {
    final old = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final settings = old.select('SELECT key,value FROM settings');
      final records = old.select(
        'SELECT song,identity,first_heard,last_heard,count FROM history',
      );
      db.execute('BEGIN');
      try {
        for (final row in settings) {
          db.execute('INSERT OR IGNORE INTO settings(key,value) VALUES(?,?)', [
            row['key'],
            row['value'],
          ]);
        }
        for (final row in records) {
          db.execute(
            'INSERT INTO history(song,identity,first_heard,last_heard,count) VALUES(?,?,?,?,?)',
            [
              row['song'],
              row['identity'],
              row['first_heard'],
              row['last_heard'],
              row['count'],
            ],
          );
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      old.dispose();
    }
  }

  final String directory;
  late final Database db;
  String setting(String key, String fallback) {
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  void saveSetting(String key, String value) => db.execute(
    'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
    [key, value],
  );
  void remember(Song song, DateTime now) {
    final rows = db.select(
      'SELECT id,identity,last_heard FROM history ORDER BY last_heard DESC,id DESC LIMIT 1',
    );
    if (rows.isNotEmpty &&
        rows.first['identity'] == song.identity &&
        now.millisecondsSinceEpoch - (rows.first['last_heard'] as int) <
            180000) {
      db.execute('UPDATE history SET last_heard=?,count=count+1 WHERE id=?', [
        now.millisecondsSinceEpoch,
        rows.first['id'],
      ]);
    } else {
      db.execute(
        'INSERT INTO history(song,identity,first_heard,last_heard) VALUES(?,?,?,?)',
        [
          jsonEncode(song.toJson()),
          song.identity,
          now.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
        ],
      );
    }
    db.execute(
      'DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY last_heard DESC,id DESC LIMIT 500)',
    );
  }

  List<HeardSong> history() => db
      .select(
        'SELECT * FROM history ORDER BY last_heard DESC,id DESC LIMIT 500',
      )
      .map(
        (row) => HeardSong(
          id: row['id'] as int,
          song: Song.fromJson(
            jsonDecode(row['song'] as String) as Map<String, dynamic>,
          ),
          firstHeard: DateTime.fromMillisecondsSinceEpoch(
            row['first_heard'] as int,
          ),
          lastHeard: DateTime.fromMillisecondsSinceEpoch(
            row['last_heard'] as int,
          ),
          count: row['count'] as int,
        ),
      )
      .toList();
  void clearHistory() => db.execute('DELETE FROM history');
  void close() => db.dispose();
}
