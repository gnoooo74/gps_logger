/// 위치/주소 획득이 정상인지, 어느 단계에서 실패했는지를 나타냄.
/// 실패도 "에러"가 아니라 정상적으로 기록되는 상태 중 하나로 다룬다.
enum LocationStatus {
  ok, // 위치, 주소 모두 정상 획득
  gpsFailed, // GPS(위치) 자체를 못 얻음 -> latitude/longitude가 null
  addressFailed, // 위치는 얻었지만 카카오 API로 주소 변환 실패 -> region2/region3가 null
}

LocationStatus _statusFromString(String? s) {
  switch (s) {
    case 'gpsFailed':
      return LocationStatus.gpsFailed;
    case 'addressFailed':
      return LocationStatus.addressFailed;
    default:
      return LocationStatus.ok;
  }
}

class LocationRecord {
  final int? id;

  // GPS 획득에 실패하면 null (에러를 던지는 대신 null + status로 표현)
  final double? latitude;
  final double? longitude;

  final DateTime timestamp;

  // 주소 획득에 실패하면 null
  final String? region2; // 시/군/구 (예: 강남구)
  final String? region3; // 읍/면/동 (예: 역삼동)

  final LocationStatus status;

  LocationRecord({
    this.id,
    this.latitude,
    this.longitude,
    required this.timestamp,
    this.region2,
    this.region3,
    this.status = LocationStatus.ok,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// 목록에 보여줄 간단 주소. 실패 상태면 실패 사유를 그대로 보여준다.
  String get simpleAddress {
    if (status == LocationStatus.gpsFailed) return '위치 획득 실패';
    if (status == LocationStatus.addressFailed) return '주소 획득 실패';
    if (region2 == null && region3 == null) return '주소 확인 중';
    return [region2, region3].where((e) => e != null && e.isNotEmpty).join(' ');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'region2': region2,
      'region3': region3,
      'status': status.name,
    };
  }

  factory LocationRecord.fromMap(Map<String, dynamic> map) {
    return LocationRecord(
      id: map['id'] as int?,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      region2: map['region2'] as String?,
      region3: map['region3'] as String?,
      status: _statusFromString(map['status'] as String?),
    );
  }
}
