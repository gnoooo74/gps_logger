import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/location_record.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, List<LocationRecord>> _grouped = {};

  // 시간 오름차순(과거 -> 현재)으로 정렬된 전체 기록.
  // 상세화면에서 "선택 지점 기준 이전 4개 / 다음 4개"를 계산할 때 씀.
  List<LocationRecord> _allRecordsAscending = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    // timestamp DESC(최신순)로 옴
    final records = await DatabaseHelper.instance.getAllRecords();

    final grouped = <String, List<LocationRecord>>{};
    for (final r in records) {
      final dateKey =
          '${r.timestamp.year.toString().padLeft(4, '0')}-${r.timestamp.month.toString().padLeft(2, '0')}-${r.timestamp.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(dateKey, () => []).add(r);
    }

    setState(() {
      _grouped = grouped;
      _allRecordsAscending = records.reversed.toList(); // 과거 -> 현재 순으로 뒤집음
      _loading = false;
    });
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    return DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(date);
  }

  // 날짜는 섹션 헤더에서 이미 보여주므로 항목에는 시:분:초만 표시
  String _formatTime(DateTime dt) {
    return DateFormat('HH:mm:ss').format(dt);
  }

  void _openDetail(LocationRecord record) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          record: record,
          allRecords: _allRecordsAscending,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 날짜 최신순 정렬
    final sortedKeys = _grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('위치 수집 내역'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecords,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : sortedKeys.isEmpty
              ? const Center(child: Text('아직 수집된 위치 기록이 없어요'))
              : RefreshIndicator(
                  onRefresh: _loadRecords,
                  child: ListView.builder(
                    itemCount: sortedKeys.length,
                    itemBuilder: (context, index) {
                      final dateKey = sortedKeys[index];
                      final records = _grouped[dateKey]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text(
                              _formatDateHeader(dateKey),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                          ),
                          ...records.map(
                            (record) => _LocationCard(
                              record: record,
                              timeLabel: _formatTime(record.timestamp),
                              onMapTap: () => _openDetail(record),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final LocationRecord record;
  final String timeLabel;
  final VoidCallback onMapTap;

  const _LocationCard({
    required this.record,
    required this.timeLabel,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: Colors.deepPurple.withOpacity(0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.deepPurple.withOpacity(0.1)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: record.hasCoordinates ? onMapTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                record.hasCoordinates
                    ? Icons.location_on_outlined
                    : Icons.location_off_outlined,
                color: record.hasCoordinates ? Colors.deepPurple : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeLabel, // 시:분:초
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.simpleAddress, // 동 이름 또는 실패 사유("위치 획득 실패" 등)
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: record.hasCoordinates ? null : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.hasCoordinates
                          ? '${record.latitude!.toStringAsFixed(6)}, ${record.longitude!.toStringAsFixed(6)}'
                          : '좌표 없음',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                // 좌표가 없으면 지도에 찍을 게 없으니 버튼을 비활성화
                onPressed: record.hasCoordinates ? onMapTap : null,
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('맵보기'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
