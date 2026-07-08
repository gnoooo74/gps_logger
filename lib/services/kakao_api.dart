import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// 카카오 REST API 키
/// https://developers.kakao.com 에서 앱 생성 후 [내 애플리케이션] > [앱 키] > REST API 키를 발급받아 넣어주세요.
const String kakaoRestApiKey = 'YOUR_KAKAO_REST_API_KEY_HERE';

/// 네트워크가 느리거나 응답이 없을 때 무한정 기다리지 않도록 하는 제한 시간.
/// 이 시간을 넘기면 실패로 처리하고 null을 반환한다 (예외를 던지지 않음).
const Duration _kakaoRequestTimeout = Duration(seconds: 10);

class KakaoAddressResult {
  final String? region2; // 시/군/구
  final String? region3; // 읍/면/동
  final String? roadAddress; // 도로명 상세주소
  final String? jibunAddress; // 지번 상세주소

  KakaoAddressResult({
    this.region2,
    this.region3,
    this.roadAddress,
    this.jibunAddress,
  });
}

class KakaoApi {
  /// 좌표 -> 행정구역 정보 (간단 주소용, 동 단위까지)
  /// https://developers.kakao.com/docs/latest/ko/local/dev-guide#coord-to-district
  ///
  /// 네트워크 오류, 타임아웃, 응답 파싱 실패 등 어떤 이유로든 실패하면
  /// 예외를 던지지 않고 null을 반환한다. 호출부(location_service.dart)는
  /// null을 "주소 획득 실패"로 기록하면 된다.
  static Future<KakaoAddressResult?> coordToRegion(
      double lat, double lng) async {
    try {
      final url = Uri.parse(
          'https://dapi.kakao.com/v2/local/geo/coord2regioncode.json?x=$lng&y=$lat');
      final res = await http.get(url, headers: {
        'Authorization': 'KakaoAK $kakaoRestApiKey',
      }).timeout(_kakaoRequestTimeout);

      if (res.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final documents = data['documents'] as List?;
      if (documents == null || documents.isEmpty) return null;

      // region_type이 'H'(행정동)인 항목을 우선 사용
      final doc = documents.firstWhere(
        (d) => d['region_type'] == 'H',
        orElse: () => documents.first,
      );

      return KakaoAddressResult(
        region2: doc['region_2depth_name'] as String?,
        region3: doc['region_3depth_name'] as String?,
      );
    } catch (e) {
      // 네트워크 끊김, 타임아웃, JSON 형식 이상 등 무엇이든 여기서 흡수하고
      // 실패로만 처리한다 (앱을 죽이지 않음).
      return null;
    }
  }

  /// 좌표 -> 상세 주소 (도로명 + 지번, 상세보기 화면용)
  /// https://developers.kakao.com/docs/latest/ko/local/dev-guide#coord-to-address
  /// 위와 동일하게, 실패 시 예외 없이 null을 반환한다.
  static Future<KakaoAddressResult?> coordToDetailAddress(
      double lat, double lng) async {
    try {
      final url = Uri.parse(
          'https://dapi.kakao.com/v2/local/geo/coord2address.json?x=$lng&y=$lat');
      final res = await http.get(url, headers: {
        'Authorization': 'KakaoAK $kakaoRestApiKey',
      }).timeout(_kakaoRequestTimeout);

      if (res.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final documents = data['documents'] as List?;
      if (documents == null || documents.isEmpty) return null;

      final doc = documents.first;
      final road = doc['road_address'];
      final jibun = doc['address'];

      return KakaoAddressResult(
        roadAddress: road != null ? road['address_name'] as String? : null,
        jibunAddress: jibun != null ? jibun['address_name'] as String? : null,
      );
    } catch (e) {
      return null;
    }
  }
}
