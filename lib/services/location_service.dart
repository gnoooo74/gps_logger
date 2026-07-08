import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';

import '../db/database_helper.dart';
import '../models/location_record.dart';
import 'kakao_api.dart';

/// 평소 로그 간격(초). 값이 바뀌든 안 바뀌든 이 주기로 무조건 기록합니다.
const int baseIntervalSeconds = 60;

/// "급격한 이동"이 감지됐을 때 로그 간격(초).
const int fastIntervalSeconds = 10;

/// "급격한 이동"으로 판단하는 속도 임계값 (km/h).
const double rapidSpeedThresholdKmh = 15;

/// 위 값을 m/s로 환산 (Geolocator의 Position.speed 단위가 m/s이기 때문)
const double rapidSpeedThresholdMps = rapidSpeedThresholdKmh * 1000 / 3600;

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
/// - 평소에는 baseIntervalSeconds(1분)마다 무조건 기록
/// - 직전 수집에서 속도가 rapidSpeedThresholdMps(15km/h) 이상이었다면
///   fastIntervalSeconds(10초) 뒤에 바로 다음 수집을 진행 (급격 모드)
/// - 급격 모드 중 속도가 임계값 아래로 내려가면 다음 턴부터 즉시 1분 간격으로 복귀
///   (임계값 근처에서 속도가 왔다갔다 하면 간격도 같이 왔다갔다 할 수 있음 —
///    필요하면 나중에 "N분 연속 임계값 아래일 때만 복귀" 같은 유지시간을 추가할 수 있습니다)
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

  while (!stopped) {
    final position = await _collectAndSaveLocation();

    final speedMps = position?.speed ?? 0;
    final isRapidMove = speedMps >= rapidSpeedThresholdMps;

    final waitSeconds = isRapidMove ? fastIntervalSeconds : baseIntervalSeconds;
    await Future.delayed(Duration(seconds: waitSeconds));
  }
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
