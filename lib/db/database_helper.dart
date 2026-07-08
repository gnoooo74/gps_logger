import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/location_record.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'location_tracker.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE location_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            timestamp TEXT NOT NULL,
            region2 TEXT,
            region3 TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_timestamp ON location_records(timestamp)');
      },
    );
  }

  Future<int> insertRecord(LocationRecord record) async {
    final db = await database;
    return db.insert('location_records', record.toMap()..remove('id'));
  }

  Future<List<LocationRecord>> getAllRecords() async {
    final db = await database;
    final rows = await db.query('location_records', orderBy: 'timestamp DESC');
    return rows.map((e) => LocationRecord.fromMap(e)).toList();
  }

  Future<int> deleteRecord(int id) async {
    final db = await database;
    return db.delete('location_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearAll() async {
    final db = await database;
    return db.delete('location_records');
  }

  /// 날짜(yyyy-MM-dd) 별로 그룹핑해서 반환
  Future<Map<String, List<LocationRecord>>> getRecordsGroupedByDate() async {
    final records = await getAllRecords();
    final Map<String, List<LocationRecord>> grouped = {};
    for (final r in records) {
      final dateKey =
          '${r.timestamp.year.toString().padLeft(4, '0')}-${r.timestamp.month.toString().padLeft(2, '0')}-${r.timestamp.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(dateKey, () => []).add(r);
    }
    return grouped;
  }
}
