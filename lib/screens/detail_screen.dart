import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/location_record.dart';
import '../services/kakao_api.dart';

/// 카카오맵 JavaScript SDK 앱 키
/// https://developers.kakao.com 에서 [내 애플리케이션] > [앱 키] > JavaScript 키를 발급받아 넣어주세요.
/// 또한 [플랫폼] > [Web]에 사용할 도메인을 등록해야 지도가 로드됩니다.
const String kakaoJsKey = 'YOUR_KAKAO_JS_KEY_HERE';

class DetailScreen extends StatefulWidget {
  final LocationRecord record;
  const DetailScreen({super.key, required this.record});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  KakaoAddressResult? _detailAddress;
  bool _loadingAddress = true;
  late final WebViewController _webController;

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(_buildMapHtml());
    _loadDetailAddress();
  }

  Future<void> _loadDetailAddress() async {
    final result = await KakaoApi.coordToDetailAddress(
      widget.record.latitude,
      widget.record.longitude,
    );
    setState(() {
      _detailAddress = result;
      _loadingAddress = false;
    });
  }

  String _buildMapHtml() {
    final lat = widget.record.latitude;
    final lng = widget.record.longitude;
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <style>html, body, #map { width: 100%; height: 100%; margin: 0; padding: 0; }</style>
</head>
<body>
  <div id="map"></div>
  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=$kakaoJsKey"></script>
  <script>
    var container = document.getElementById('map');
    var options = {
      center: new kakao.maps.LatLng($lat, $lng),
      level: 3
    };
    var map = new kakao.maps.Map(container, options);
    var marker = new kakao.maps.Marker({
      position: new kakao.maps.LatLng($lat, $lng)
    });
    marker.setMap(map);
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          DateFormat('yyyy.MM.dd HH:mm').format(record.timestamp),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 280,
            child: WebViewWidget(controller: _webController),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('상세 주소', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                if (_loadingAddress)
                  const CircularProgressIndicator()
                else ...[
                  if (_detailAddress?.roadAddress != null)
                    _AddressRow(label: '도로명', value: _detailAddress!.roadAddress!),
                  if (_detailAddress?.jibunAddress != null)
                    _AddressRow(label: '지번', value: _detailAddress!.jibunAddress!),
                  if (_detailAddress?.roadAddress == null && _detailAddress?.jibunAddress == null)
                    const Text('상세 주소를 가져오지 못했어요'),
                ],
                const SizedBox(height: 16),
                Text(
                  '좌표: ${record.latitude.toStringAsFixed(6)}, ${record.longitude.toStringAsFixed(6)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final String label;
  final String value;
  const _AddressRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
