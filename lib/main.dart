import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/home_screen.dart';
import 'services/gps_log_file_service.dart';
import 'services/location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 홈 화면에서 'yyyy년 M월 d일 (E)' 같은 ko_KR 포맷을 쓰기 때문에
  // 미리 초기화해두지 않으면 첫 렌더링에서 LocaleDataException이 발생합니다.
  await initializeDateFormatting('ko_KR', null);

  // 위치 권한 + (Android 13+) 알림 권한 요청
  await Geolocator.requestPermission();
  await Permission.notification.request();
  // 백그라운드에서도 계속 수집하려면 '항상 허용'이 필요합니다.
  await Permission.locationAlways.request();

  // 다운로드/gps_logs 파일 로그를 쓰려면 "모든 파일 관리" 권한이 필요합니다.
  // 이 권한은 설정 앱의 별도 화면으로 넘어가야 해서, 화면이 있는 지금(UI)
  // 시점에 요청해야 합니다. 백그라운드 서비스 안에서는 상태만 확인합니다.
  await GpsLogFileService.requestPermissionFromUi();

  await initializeBackgroundService();

  runApp(const LocationTrackerApp());
}

class LocationTrackerApp extends StatelessWidget {
  const LocationTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '위치 수집기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
