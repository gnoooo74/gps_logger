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

  /// 기록이 하나라도 있는 날짜 목록(yyyy-MM-dd)을 최신순으로 반환.
  /// 전체 레코드를 안 불러오고 날짜만 가볍게 조회함 (날짜 선택 화면용).
  Future<List<String>> getAvailableDates() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT substr(timestamp, 1, 10) as date
      FROM location_records
      ORDER BY date DESC
    ''');
    return rows.map((r) => r['date'] as String).toList();
  }

  /// 특정 날짜(yyyy-MM-dd)의 기록만 조회 (최신순).
  /// 홈 화면이 그 날짜의 기록만 불러오도록 해서, 기록이 아무리 쌓여도
  /// 한 번에 다 불러오지 않게 하기 위함.
  Future<List<LocationRecord>> getRecordsForDate(String dateKey) async {
    final db = await database;
    final rows = await db.query(
      'location_records',
      where: 'timestamp LIKE ?',
      whereArgs: ['$dateKey%'],
      orderBy: 'timestamp DESC',
    );
    return rows.map((e) => LocationRecord.fromMap(e)).toList();
  }

  /// 상세화면(지도)에서 "선택 지점 기준 이전 N개 / 다음 N개"를 보여주기 위한
  /// 이웃 기록만 가볍게 조회. 날짜 경계를 넘어서도(예: 자정 근처) 정확하게
  /// 이전/다음을 찾을 수 있도록 전체 테이블에서 직접 조회한다.
  /// (좌표가 없는 GPS 실패 기록은 지도에 찍을 수 없으므로 애초에 제외)
  Future<List<LocationRecord>> getNeighborWindow(
    LocationRecord selected, {
    int before = 4,
    int after = 4,
  }) async {
    final db = await database;
    final ts = selected.timestamp.toIso8601String();

    final prevRows = await db.query(
      'location_records',
      where: 'timestamp < ? AND latitude IS NOT NULL AND longitude IS NOT NULL',
      whereArgs: [ts],
      orderBy: 'timestamp DESC',
      limit: before,
    );
    final nextRows = await db.query(
      'location_records',
      where: 'timestamp > ? AND latitude IS NOT NULL AND longitude IS NOT NULL',
      whereArgs: [ts],
      orderBy: 'timestamp ASC',
      limit: after,
    );

    // prevRows는 최신순으로 왔으니 뒤집어서 과거->현재 순으로 맞춘다.
    final previous =
        prevRows.map((e) => LocationRecord.fromMap(e)).toList().reversed.toList();
    final next = nextRows.map((e) => LocationRecord.fromMap(e)).toList();

    return [...previous, selected, ...next];
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
