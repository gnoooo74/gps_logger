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

  static const String _createTableSql = '''
    CREATE TABLE location_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      latitude REAL,
      longitude REAL,
      timestamp TEXT NOT NULL,
      region2 TEXT,
      region3 TEXT,
      status TEXT NOT NULL DEFAULT 'ok'
    )
  ''';

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'location_tracker.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute(_createTableSql);
        await db.execute('CREATE INDEX idx_timestamp ON location_records(timestamp)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v1: latitude/longitude NOT NULL, status 컬럼 없음
          // v2: 위치/주소 획득 실패도 기록할 수 있도록 latitude/longitude를 nullable로,
          //     status 컬럼을 추가 (SQLite는 컬럼 제약을 직접 못 바꿔서 테이블을 새로 만듦)
          await db.execute('ALTER TABLE location_records RENAME TO location_records_old');
          await db.execute(_createTableSql);
          await db.execute('''
            INSERT INTO location_records (id, latitude, longitude, timestamp, region2, region3, status)
            SELECT id, latitude, longitude, timestamp, region2, region3, 'ok'
            FROM location_records_old
          ''');
          await db.execute('DROP TABLE location_records_old');
          await db.execute('CREATE INDEX idx_timestamp ON location_records(timestamp)');
        }
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
