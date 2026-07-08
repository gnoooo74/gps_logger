import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/home_screen.dart';
import 'services/location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 위치 권한 + (Android 13+) 알림 권한 요청
  await Geolocator.requestPermission();
  await Permission.notification.request();
  // 백그라운드에서도 계속 수집하려면 '항상 허용'이 필요합니다.
  await Permission.locationAlways.request();

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
