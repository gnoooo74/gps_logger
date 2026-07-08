import 'dart:io';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

/// 위치 수집 기록을 "다운로드/gps_logs/YYYY-MM-DD.csv" 파일로
/// 하루에 한 파일씩 남기는 서비스.
///
/// - location_service.dart 에서 위치를 수집해 DB에 저장할 때
///   이 서비스의 appendLog()도 같이 호출해주면 됩니다.
/// - 기존 SQLite 저장 로직은 그대로 유지되고, 이 서비스는
///   "파일로도 로그를 남긴다"는 요구사항만 추가로 처리합니다.
class GpsLogFileService {
  static const String _folderName = 'gps_logs';

  /// Android 10+ (scoped storage) 에서도 공용 다운로드 폴더에
  /// 직접 쓸 수 있도록 "모든 파일 관리" 권한을 요청합니다.
  /// (Play 스토어 배포용이 아닌 개인/사이드로드 APK이므로 사용 가능)
  static Future<bool> ensurePermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    final result = await Permission.manageExternalStorage.request();
    return result.isGranted;
  }

  /// /storage/emulated/0/Download/gps_logs 디렉토리를 반환 (없으면 생성)
  static Future<Directory> _logDir() async {
    final dir = Directory('/storage/emulated/0/Download/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 오늘 날짜(YYYY-MM-DD.csv) 파일에 한 줄을 추가합니다.
  /// 파일이 없으면 헤더를 먼저 쓰고 시작합니다.
  static Future<void> appendLog({
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    String? region2, // 예: 강남구
    String? region3, // 예: 역삼동
  }) async {
    final granted = await ensurePermission();
    if (!granted) {
      // 권한이 없으면 파일 로그는 건너뛰고 조용히 리턴
      // (SQLite 저장은 location_service.dart 쪽에서 계속 진행됨)
      return;
    }

    final dir = await _logDir();
    final dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
    final file = File('${dir.path}/$dateStr.csv');

    final isNewFile = !await file.exists();

    final sink = file.openWrite(mode: FileMode.append);
    if (isNewFile) {
      sink.writeln('time,latitude,longitude,region2,region3');
    }

    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    sink.writeln(
      '$timeStr,$latitude,$longitude,${region2 ?? ''},${region3 ?? ''}',
    );

    await sink.flush();
    await sink.close();
  }
}
