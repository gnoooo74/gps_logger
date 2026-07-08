class LocationRecord {
  final int? id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? region2; // 시/군/구 (예: 강남구)
  final String? region3; // 읍/면/동 (예: 역삼동)

  LocationRecord({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.region2,
    this.region3,
  });

  /// 목록에 보여줄 간단 주소. 예: "강남구 역삼동"
  String get simpleAddress {
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
    };
  }

  factory LocationRecord.fromMap(Map<String, dynamic> map) {
    return LocationRecord(
      id: map['id'] as int?,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      timestamp: DateTime.parse(map['timestamp'] as String),
      region2: map['region2'] as String?,
      region3: map['region3'] as String?,
    );
  }
}
