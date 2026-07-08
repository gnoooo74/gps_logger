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
  late String _selectedDateKey; // yyyy-MM-dd
  List<LocationRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedDateKey = _dateKeyOf(DateTime.now()); // 항상 오늘 날짜로 시작
    _loadRecordsForSelectedDate();
  }

  String _dateKeyOf(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadRecordsForSelectedDate() async {
    setState(() => _loading = true);
    final records =
        await DatabaseHelper.instance.getRecordsForDate(_selectedDateKey);
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    return DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(date);
  }

  // 날짜는 상단에서 이미 보여주므로 항목에는 시:분:초만 표시
  String _formatTime(DateTime dt) {
    return DateFormat('HH:mm:ss').format(dt);
  }

  Future<void> _openDatePicker() async {
    final dates = await DatabaseHelper.instance.getAvailableDates();
    if (!mounted) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '날짜 선택',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple[700],
                  ),
                ),
              ),
              if (dates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('기록이 있는 날짜가 없어요'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: dates.length,
                    itemBuilder: (context, index) {
                      final dateKey = dates[index];
                      final isSelected = dateKey == _selectedDateKey;
                      return ListTile(
                        title: Text(_formatDateHeader(dateKey)),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.deepPurple)
                            : null,
                        selected: isSelected,
                        onTap: () => Navigator.pop(context, dateKey),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (picked != null && picked != _selectedDateKey) {
      setState(() => _selectedDateKey = picked);
      await _loadRecordsForSelectedDate();
    }
  }

  Future<void> _openDetail(LocationRecord record) async {
    final neighborWindow =
        await DatabaseHelper.instance.getNeighborWindow(record);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          record: record,
          allRecords: neighborWindow,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _openDatePicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _formatDateHeader(_selectedDateKey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordsForSelectedDate,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Text(
                    _selectedDateKey == _dateKeyOf(DateTime.now())
                        ? '아직 오늘 기록이 없어요'
                        : '이 날짜에는 기록이 없어요',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRecordsForSelectedDate,
                  child: ListView.builder(
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      final record = _records[index];
                      return _LocationCard(
                        record: record,
                        timeLabel: _formatTime(record.timestamp),
                        onMapTap: () => _openDetail(record),
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
