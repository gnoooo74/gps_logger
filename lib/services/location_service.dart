import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';

import '../db/database_helper.dart';
import '../models/location_record.dart';
import 'kakao_api.dart';

/// 수집 주기 (분). 필요에 맞게 조절하세요.
const int collectIntervalMinutes = 15;

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
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  // 최초 1회 즉시 수집 후, 주기적으로 반복
  await _collectAndSaveLocation();

  Timer.periodic(const Duration(minutes: collectIntervalMinutes), (timer) async {
    await _collectAndSaveLocation();
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

Future<void> _collectAndSaveLocation() async {
  try {
    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

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
  } catch (e) {
    // 수집 실패는 조용히 무시 (다음 주기에 재시도)
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
