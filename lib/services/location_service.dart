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

/// GPS 위치 요청 자체가 오래 걸릴 때(신호 불량, 실내 등) 무한정 기다리지 않도록
/// 하는 제한 시간. 이 시간을 넘기면 "위치 획득 실패"로 기록하고 다음 주기로 넘어감.
const Duration gpsTimeout = Duration(seconds: 20);

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // 앱을 다시 열 때마다 main()이 재실행되면서 이 함수가 다시 불릴 수 있는데,
  // 이미 서비스가 돌고 있는 상태에서 configure()/startService()를 또 호출하면
  // 이미 떠 있는 포그라운드 알림과 충돌해서 CannotPostForegroundServiceNotificationException
  // ("Bad notification for startForeground")로 죽는 케이스가 있었음.
  // 이미 실행 중이면 그대로 두고 아무것도 하지 않는다.
  final alreadyRunning = await service.isRunning();
  if (alreadyRunning) {
    return;
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'location_tracker_channel',
      initialNotificationTitle: '위치 수집 중',
      initialNotificationContent: '앱이 백그라운드에서 위치를 기록하고 있습니다',
      foregroundServiceNotificationId: 888,
      // Android 14(API 34)+ 에서는 이 타입 선언이 없으면
      // MissingForegroundServiceTypeException으로 서비스 시작 자체가 크래시함.
      // AndroidManifest.xml의 <service> 태그에 선언한 foregroundServiceType="location"과 짝을 맞춰야 함.
      foregroundServiceTypes: [AndroidForegroundType.location],
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
/// - GPS/주소 획득이 실패해도 앱은 절대 죽지 않고, "실패"라는 상태로 정상 기록한다.
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
    final result = await _collectAndSaveLocation();

    final reliableFast = result.status == LocationStatus.ok &&
        _isReliableFastReading(
          speedMps: result.speedMps,
          accuracyMeters: result.accuracyMeters,
          speedAccuracyMps: result.speedAccuracyMps,
        );
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
bool _isReliableFastReading({
  required double speedMps,
  required double accuracyMeters,
  required double speedAccuracyMps,
}) {
  final isFastEnough = speedMps >= rapidSpeedThresholdMps;
  final hasGoodAccuracy = accuracyMeters <= maxAcceptableAccuracyMeters;
  final speedAccuracyOk =
      speedAccuracyMps <= 0 || speedAccuracyMps <= maxAcceptableSpeedAccuracyMps;

  return isFastEnough && hasGoodAccuracy && speedAccuracyOk;
}

/// 한 번의 수집 결과. 다음 로그 간격(평소/급격)을 판단하는 데 필요한 값만 담는다.
class _CollectResult {
  final LocationStatus status;
  final double speedMps;
  final double accuracyMeters;
  final double speedAccuracyMps;

  _CollectResult({
    required this.status,
    this.speedMps = 0,
    this.accuracyMeters = 0,
    this.speedAccuracyMps = 0,
  });
}

/// 위치를 한 번 수집해서 DB + 파일 로그에 저장합니다.
///
/// 중요: 이 함수는 절대 예외를 밖으로 던지지 않습니다.
/// GPS를 못 얻으면 "위치 획득 실패", 주소만 못 얻으면 "주소 획득 실패"로
/// 정상적으로 한 줄을 기록하고 넘어갑니다. (요청사항: 실패 = 에러가 아니라 기록되어야 함)
Future<_CollectResult> _collectAndSaveLocation() async {
  final now = DateTime.now();

  double? lat;
  double? lng;
  double speedMps = 0;
  double accuracyMeters = 0;
  double speedAccuracyMps = 0;
  LocationStatus status = LocationStatus.ok;

  // 1단계: GPS 위치 획득 (실패하면 gpsFailed로 기록하고 아래 단계는 건너뜀)
  try {
    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) {
      status = LocationStatus.gpsFailed;
    } else {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(gpsTimeout);

      lat = position.latitude;
      lng = position.longitude;
      speedMps = position.speed;
      accuracyMeters = position.accuracy;
      speedAccuracyMps = position.speedAccuracy;
    }
  } catch (e) {
    // 권한 취소, GPS 신호 없음, timeout 등 - 무엇이든 "위치 획득 실패"로 처리
    status = LocationStatus.gpsFailed;
  }

  String? region2;
  String? region3;

  // 2단계: 주소 변환 (GPS가 성공했을 때만 시도)
  if (status == LocationStatus.ok && lat != null && lng != null) {
    // KakaoApi는 내부에서 이미 타임아웃/예외를 흡수해서 null만 반환한다.
    final region = await KakaoApi.coordToRegion(lat, lng);
    if (region == null) {
      status = LocationStatus.addressFailed;
    } else {
      region2 = region.region2;
      region3 = region.region3;
    }
  }

  final record = LocationRecord(
    latitude: lat,
    longitude: lng,
    timestamp: now,
    region2: region2,
    region3: region3,
    status: status,
  );

  // 3단계: 저장 (DB, 파일 로그) - 이 저장 자체가 실패해도 앱은 계속 진행되어야 함
  try {
    await DatabaseHelper.instance.insertRecord(record);
  } catch (e) {
    // DB 저장 실패(드묾)도 앱을 죽이지 않고 무시, 다음 주기에 계속 진행
  }

  await GpsLogFileService.appendLog(
    timestamp: record.timestamp,
    latitude: record.latitude,
    longitude: record.longitude,
    region2: record.region2,
    region3: record.region3,
    status: record.status,
  );

  return _CollectResult(
    status: status,
    speedMps: speedMps,
    accuracyMeters: accuracyMeters,
    speedAccuracyMps: speedAccuracyMps,
  );
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
