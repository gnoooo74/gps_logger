import 'dart:io';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/location_record.dart';

/// 위치 수집 기록을 "다운로드/gps_logs/YYYY-MM-DD.csv" 파일로
/// 하루에 한 파일씩 남기는 서비스.
///
/// - location_service.dart 에서 위치를 수집해 DB에 저장할 때
///   이 서비스의 appendLog()도 같이 호출해주면 됩니다.
/// - 기존 SQLite 저장 로직은 그대로 유지되고, 이 서비스는
///   "파일로도 로그를 남긴다"는 요구사항만 추가로 처리합니다.
/// - 위치/주소 획득 실패도 예외를 던지지 않고 그대로 한 줄로 기록합니다.
class GpsLogFileService {
  static const String _folderName = 'gps_logs';

  /// "모든 파일 관리" 권한이 이미 허용되어 있는지 확인만 합니다 (요청하지 않음).
  ///
  /// 이 권한은 앱 내 팝업이 아니라 설정 앱의 별도 화면으로 이동해서 켜야 하는
  /// 방식이라, 화면(Activity)이 없는 백그라운드 서비스 안에서 request()를
  /// 호출하면 제대로 뜨지 않습니다. 그래서 백그라운드에서는 상태만 확인하고,
  /// 실제 요청은 앱을 열었을 때 UI 쪽(main.dart)에서 [requestPermissionFromUi]로 합니다.
  static Future<bool> hasPermission() async {
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }

  /// 앱 UI(화면이 있는 상태)에서 한 번 호출해서 실제로 권한을 요청합니다.
  /// main.dart에서 앱 시작 시 호출해주세요.
  static Future<bool> requestPermissionFromUi() async {
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
  ///
  /// latitude/longitude/region2/region3는 획득 실패 시 null일 수 있으며,
  /// 그 경우 status를 통해 실패 사유가 CSV에 그대로 남습니다.
  /// 이 메서드 자체는 어떤 이유로도 예외를 밖으로 던지지 않습니다
  /// (권한 문제, 디스크 오류 등은 조용히 무시하고 다음 주기에 재시도).
  static Future<void> appendLog({
    required DateTime timestamp,
    double? latitude,
    double? longitude,
    String? region2, // 예: 강남구
    String? region3, // 예: 역삼동
    LocationStatus status = LocationStatus.ok,
  }) async {
    try {
      final granted = await hasPermission();
      if (!granted) {
        // 권한이 없으면 파일 로그는 건너뛰고 조용히 리턴
        // (SQLite 저장은 location_service.dart 쪽에서 계속 진행됨)
        // 권한 요청 자체는 main.dart에서 앱을 열 때 이미 시도했어야 함.
        return;
      }

      final dir = await _logDir();
      final dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
      final file = File('${dir.path}/$dateStr.csv');

      final isNewFile = !await file.exists();

      final sink = file.openWrite(mode: FileMode.append);
      if (isNewFile) {
        sink.writeln('time,latitude,longitude,region2,region3,status');
      }

      final timeStr = DateFormat('HH:mm:ss').format(timestamp);
      final latStr = latitude?.toString() ?? '';
      final lngStr = longitude?.toString() ?? '';
      final statusStr = switch (status) {
        LocationStatus.ok => 'OK',
        LocationStatus.gpsFailed => 'GPS_획득실패',
        LocationStatus.addressFailed => '주소_획득실패',
      };

      sink.writeln(
        '$timeStr,$latStr,$lngStr,${region2 ?? ''},${region3 ?? ''},$statusStr',
      );

      await sink.flush();
      await sink.close();
    } catch (e) {
      // 파일 쓰기 실패(디스크 꽉 참, 권한 취소 등)도 앱을 죽이지 않고 조용히 무시.
      // 다음 주기에 다시 시도된다.
    }
  }
}
