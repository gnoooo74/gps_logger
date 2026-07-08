import 'dart:convert';
import 'package:http/http.dart' as http;

/// 카카오 REST API 키
/// https://developers.kakao.com 에서 앱 생성 후 [내 애플리케이션] > [앱 키] > REST API 키를 발급받아 넣어주세요.
const String kakaoRestApiKey = 'YOUR_KAKAO_REST_API_KEY_HERE';

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
  static Future<KakaoAddressResult?> coordToRegion(
      double lat, double lng) async {
    final url = Uri.parse(
        'https://dapi.kakao.com/v2/local/geo/coord2regioncode.json?x=$lng&y=$lat');
    final res = await http.get(url, headers: {
      'Authorization': 'KakaoAK $kakaoRestApiKey',
    });

    if (res.statusCode != 200) return null;

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final documents = data['documents'] as List;
    if (documents.isEmpty) return null;

    // region_type이 'H'(행정동)인 항목을 우선 사용
    final doc = documents.firstWhere(
      (d) => d['region_type'] == 'H',
      orElse: () => documents.first,
    );

    return KakaoAddressResult(
      region2: doc['region_2depth_name'] as String?,
      region3: doc['region_3depth_name'] as String?,
    );
  }

  /// 좌표 -> 상세 주소 (도로명 + 지번, 상세보기 화면용)
  /// https://developers.kakao.com/docs/latest/ko/local/dev-guide#coord-to-address
  static Future<KakaoAddressResult?> coordToDetailAddress(
      double lat, double lng) async {
    final url = Uri.parse(
        'https://dapi.kakao.com/v2/local/geo/coord2address.json?x=$lng&y=$lat');
    final res = await http.get(url, headers: {
      'Authorization': 'KakaoAK $kakaoRestApiKey',
    });

    if (res.statusCode != 200) return null;

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final documents = data['documents'] as List;
    if (documents.isEmpty) return null;

    final doc = documents.first;
    final road = doc['road_address'];
    final jibun = doc['address'];

    return KakaoAddressResult(
      roadAddress: road != null ? road['address_name'] as String? : null,
      jibunAddress: jibun != null ? jibun['address_name'] as String? : null,
    );
  }
}
