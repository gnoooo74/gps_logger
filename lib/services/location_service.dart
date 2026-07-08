import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';

import '../db/database_helper.dart';
import '../models/location_record.dart';
import 'gps_log_file_service.dart';
import 'kakao_api.dart';

/// 평소 로그 간격(초). 값이 바뀌든 안 바뀌든 이 주기로 무조건 기록합니다.
const int baseIntervalSeconds = 30;

/// "급격한 이동"이 확정됐을 때 로그 간격(초).
const int fastIntervalSeconds = 10;

/// "급격한 이동"으로 판단하는 속도 임계값 (km/h) → m/s로 환산해서 사용
const double rapidSpeedThresholdKmh = 15;
const double rapidSpeedThresholdMps = rapidSpeedThresholdKmh * 1000 / 3600;

/// [GPS 스파이크 필터 1] 위치 정확도(오차 반경, m)가 이보다 나쁘면
/// 그 순간의 speed 값은 신뢰하지 않습니다. (신호 불량 구간에서 튀는 값 배제)
const double maxAcceptableAccuracyMeters = 30;

/// [GPS 스파이크 필터 2] 속도 추정치 자체의 오차(m/s)가 이보다 크면 신뢰하지 않습니다.
/// 일부 기기/OS는 이 값을 0으로 주기도 하는데("값 없음"의 의미), 그 경우는 건너뜁니다.
const double maxAcceptableSpeedAccuracyMps = 2.5;

/// [GPS 스파이크 필터 3] 급격 모드로 "진입"하려면 신뢰 가능한 고속 판정이
/// 이 횟수만큼 연속으로 나와야 합니다. 단발성 스파이크는 진입을 못 시킵니다.
/// (급격 모드에서 "이탈"은 즉시 이뤄집니다 — 정책상 그렇게 정했습니다)
const int requiredConsecutiveFastReadings = 2;

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'location_tracker_channel',
      initialNotificationTitle: '위치 수집 중',
      initialNotificationContent: '앱이 백그라운드에서 위치를 기록하고 있습니다',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );

  await service.startService();
}

/// 백그라운드 isolate 진입점
///
/// 정책:
/// - 평소에는 baseIntervalSeconds(30초)마다 무조건 기록
/// - 신뢰 가능한 고속 판정(정확도+속도오차 필터 통과 && 15km/h 이상)이
///   requiredConsecutiveFastReadings(2)번 연속 나오면 급격 모드로 진입,
///   이후 fastIntervalSeconds(10초) 간격으로 기록
/// - 급격 모드 중 신뢰 가능한 고속 판정이 한 번이라도 끊기면 즉시 평소 간격으로 복귀
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  bool stopped = false;
  service.on('stopService').listen((event) {
    stopped = true;
    service.stopSelf();
  });

  int consecutiveFastReadings = 0;

  while (!stopped) {
    final position = await _collectAndSaveLocation();

    final reliableFast = position != null && _isReliableFastReading(position);
    consecutiveFastReadings = reliableFast ? consecutiveFastReadings + 1 : 0;

    final isRapidMove = consecutiveFastReadings >= requiredConsecutiveFastReadings;

    final waitSeconds = isRapidMove ? fastIntervalSeconds : baseIntervalSeconds;
    await Future.delayed(Duration(seconds: waitSeconds));
  }
}

/// 이 위치 판독을 "신뢰 가능한 고속 판정"으로 볼 수 있는지 검사합니다.
/// - 속도가 임계값 이상이어야 하고
/// - 위치 정확도가 충분히 좋아야 하고 (GPS 오차로 인한 스파이크 배제)
/// - 속도 추정치 자체의 오차도 충분히 작아야 함 (0이면 "값 없음"으로 보고 건너뜀)
bool _isReliableFastReading(Position position) {
  final isFastEnough = position.speed >= rapidSpeedThresholdMps;
  final hasGoodAccuracy = position.accuracy <= maxAcceptableAccuracyMeters;
  final speedAccuracyOk = position.speedAccuracy <= 0 ||
      position.speedAccuracy <= maxAcceptableSpeedAccuracyMps;

  return isFastEnough && hasGoodAccuracy && speedAccuracyOk;
}

/// 위치를 한 번 수집해서 DB에 저장하고, 다음 간격 판단에 쓸 Position을 반환합니다.
/// 실패하면 null을 반환하고, 이 경우 호출부에서는 평소 간격으로 다음 시도를 합니다.
Future<Position?> _collectAndSaveLocation() async {
  try {
    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return null;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // 카카오 API로 간단주소(구/동)만 미리 조회해서 함께 저장
    final region = await KakaoApi.coordToRegion(
      position.latitude,
      position.longitude,
    );

    final record = LocationRecord(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now(),
      region2: region?.region2,
      region3: region?.region3,
    );

    await DatabaseHelper.instance.insertRecord(record);

    // 다운로드/gps_logs/날짜.csv 파일에도 같은 기록을 남김 (구/동 주소 포함)
    await GpsLogFileService.appendLog(
      timestamp: record.timestamp,
      latitude: record.latitude,
      longitude: record.longitude,
      region2: record.region2,
      region3: record.region3,
    );

    return position;
  } catch (e) {
    // 수집 실패는 조용히 무시 (다음 주기에 재시도)
    return null;
  }
}

Future<bool> _ensureLocationPermission() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return false;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return false;
  }
  if (permission == LocationPermission.deniedForever) return false;

  return true;
}
