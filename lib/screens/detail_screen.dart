import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/location_record.dart';
import '../services/kakao_api.dart';

/// 카카오맵 JavaScript SDK 앱 키
/// https://developers.kakao.com 에서 [내 애플리케이션] > [앱 키] > JavaScript 키를 발급받아 넣어주세요.
/// 또한 [플랫폼] > [Web]에 사용할 도메인을 등록해야 지도가 로드됩니다.
const String kakaoJsKey = 'YOUR_KAKAO_JS_KEY_HERE';

/// 지도에 찍을 지점 하나를 표현. 선택 지점인지, 몇 번 라벨인지를 함께 들고 있음.
class _MapPoint {
  final double lat;
  final double lng;
  final String label; // '1'..'8'. 선택 지점이면 사용 안 함(별도 표시)
  final bool isSelected;
  final DateTime timestamp;

  _MapPoint({
    required this.lat,
    required this.lng,
    required this.label,
    required this.isSelected,
    required this.timestamp,
  });
}

class DetailScreen extends StatefulWidget {
  final LocationRecord record;

  /// 시간 오름차순(과거 -> 현재)으로 정렬된 전체 기록.
  /// 선택 지점(record) 기준 이전 4개 / 다음 4개를 지도에 같이 표시하는 데 사용.
  /// 비어있으면 선택 지점 하나만 표시함.
  final List<LocationRecord> allRecords;

  const DetailScreen({
    super.key,
    required this.record,
    this.allRecords = const [],
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  KakaoAddressResult? _detailAddress;
  bool _loadingAddress = true;
  late final WebViewController _webController;
  late final List<_MapPoint> _mapPoints;

  @override
  void initState() {
    super.initState();
    _mapPoints = _buildMapPoints();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(_buildMapHtml(_mapPoints));
    _loadDetailAddress();
  }

  /// 선택 지점을 기준으로 시간순으로 이전 최대 4개, 다음 최대 4개를 뽑아
  /// 지도에 찍을 점 목록을 만든다. 라벨은 이전 -> 선택 -> 다음 순으로
  /// 1번부터 끊김 없이 매기며, 선택 지점도 번호를 가진다.
  /// 예) 이전 4 + 선택 + 다음 4 -> 1,2,3,4,5(선택),6,7,8,9
  ///     이전 1 + 선택 + 다음 3 -> 1,2(선택),3,4,5
  /// (앞/뒤가 4개보다 적으면 있는 만큼만 채운다.)
  List<_MapPoint> _buildMapPoints() {
    final all = widget.allRecords;
    final selected = widget.record;

    if (all.isEmpty) {
      return [
        _MapPoint(
          lat: selected.latitude,
          lng: selected.longitude,
          label: '1',
          isSelected: true,
          timestamp: selected.timestamp,
        ),
      ];
    }

    final selectedIndex = all.indexWhere((r) => r.id == selected.id);
    if (selectedIndex == -1) {
      // 목록에서 못 찾으면 안전하게 선택 지점만 표시
      return [
        _MapPoint(
          lat: selected.latitude,
          lng: selected.longitude,
          label: '1',
          isSelected: true,
          timestamp: selected.timestamp,
        ),
      ];
    }

    final prevStart = (selectedIndex - 4).clamp(0, all.length);
    final previous = all.sublist(prevStart, selectedIndex); // 시간순, 최대 4개

    final nextEnd = (selectedIndex + 1 + 4).clamp(0, all.length);
    final next = all.sublist(selectedIndex + 1, nextEnd); // 시간순, 최대 4개

    final points = <_MapPoint>[];

    for (var i = 0; i < previous.length; i++) {
      points.add(_MapPoint(
        lat: previous[i].latitude,
        lng: previous[i].longitude,
        label: '${i + 1}',
        isSelected: false,
        timestamp: previous[i].timestamp,
      ));
    }

    // 선택 지점도 이전 것들 뒤를 이어받는 번호를 가짐 (예: 이전이 4개면 선택은 5번)
    points.add(_MapPoint(
      lat: selected.latitude,
      lng: selected.longitude,
      label: '${previous.length + 1}',
      isSelected: true,
      timestamp: selected.timestamp,
    ));

    for (var i = 0; i < next.length; i++) {
      points.add(_MapPoint(
        lat: next[i].latitude,
        lng: next[i].longitude,
        label: '${previous.length + 2 + i}',
        isSelected: false,
        timestamp: next[i].timestamp,
      ));
    }

    return points;
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

  String _buildMapHtml(List<_MapPoint> points) {
    final center = points.firstWhere(
      (p) => p.isSelected,
      orElse: () => points.first,
    );

    final pointsJs = points.map((p) {
      final labelText = p.isSelected ? '${p.label}(선택)' : p.label;
      return "{lat: ${p.lat}, lng: ${p.lng}, label: '$labelText', selected: ${p.isSelected}}";
    }).join(',');

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <style>
    html, body, #map { width: 100%; height: 100%; margin: 0; padding: 0; }
    .pin {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 26px;
      height: 26px;
      border-radius: 50%;
      color: #fff;
      font-weight: bold;
      font-size: 12px;
      font-family: sans-serif;
      box-shadow: 0 1px 4px rgba(0,0,0,0.4);
      border: 2px solid #fff;
      white-space: nowrap;
    }
    .pin.normal { background: #7C4DFF; }
    .pin.selected {
      background: #E53935;
      width: auto;
      min-width: 34px;
      height: 30px;
      padding: 0 8px;
      font-size: 12px;
      border-radius: 15px;
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=$kakaoJsKey"></script>
  <script>
    var points = [$pointsJs];

    var container = document.getElementById('map');
    var map = new kakao.maps.Map(container, {
      center: new kakao.maps.LatLng(${center.lat}, ${center.lng}),
      level: 6
    });

    var bounds = new kakao.maps.LatLngBounds();

    points.forEach(function (p) {
      var pos = new kakao.maps.LatLng(p.lat, p.lng);
      bounds.extend(pos);

      var el = document.createElement('div');
      el.className = 'pin ' + (p.selected ? 'selected' : 'normal');
      el.innerText = p.label;

      var overlay = new kakao.maps.CustomOverlay({
        position: pos,
        content: el,
        yAnchor: 0.5,
        xAnchor: 0.5,
        zIndex: p.selected ? 10 : 1
      });
      overlay.setMap(map);
    });

    if (points.length > 1) {
      map.setBounds(bounds);
    }
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
          DateFormat('yyyy.MM.dd HH:mm:ss').format(record.timestamp),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 320,
            child: WebViewWidget(controller: _webController),
          ),
          if (_mapPoints.length > 1) _MapLegend(points: _mapPoints),
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

/// 지도 아래에 "번호 - 시:분:초"를 짧게 보여주는 범례.
/// 숫자만 봐서는 어느 시점인지 알기 어려워서 참고용으로 추가.
class _MapLegend extends StatelessWidget {
  final List<_MapPoint> points;
  const _MapLegend({required this.points});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm:ss');
    return Container(
      width: double.infinity,
      color: Colors.deepPurple.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: points.map((p) {
          final label = p.isSelected ? '${p.label}(선택)' : p.label;
          return Text(
            '$label · ${timeFormat.format(p.timestamp)}',
            style: TextStyle(
              fontSize: 11,
              color: p.isSelected ? Colors.red[700] : Colors.grey[700],
              fontWeight: p.isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          );
        }).toList(),
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
