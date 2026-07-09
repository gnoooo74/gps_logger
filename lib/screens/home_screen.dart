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

  // 마지막으로 "맵보기"를 눌러서 봤던 기록의 id. 목록에 돌아왔을 때
  // 이 기록을 눈에 띄게 표시해서 어떤 걸 봤었는지 바로 알 수 있게 함.
  int? _lastViewedId;

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

  final Map<int, GlobalKey> _itemKeys = {};

  Future<void> _openDetail(LocationRecord record) async {
    final neighborWindow =
        await DatabaseHelper.instance.getNeighborWindow(record);
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          record: record,
          allRecords: neighborWindow,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _lastViewedId = record.id);

    // 지도를 보고 돌아왔을 때, 방금 봤던 항목이 화면 안에 들어오도록 스크롤.
    // (프레임이 그려진 다음에 위치를 알 수 있어서 한 프레임 뒤에 실행)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[record.id];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
      }
    });
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
                      final key = _itemKeys.putIfAbsent(
                        record.id!,
                        () => GlobalKey(),
                      );
                      return _LocationCard(
                        key: key,
                        record: record,
                        timeLabel: _formatTime(record.timestamp),
                        onMapTap: () => _openDetail(record),
                        isLastViewed: record.id == _lastViewedId,
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
  final bool isLastViewed;

  const _LocationCard({
    super.key,
    required this.record,
    required this.timeLabel,
    required this.onMapTap,
    this.isLastViewed = false,
  });

  @override
  Widget build(BuildContext context) {
    final highlightColor = Colors.amber[700]!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: isLastViewed
          ? highlightColor.withOpacity(0.12)
          : Colors.deepPurple.withOpacity(0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isLastViewed
              ? highlightColor
              : Colors.deepPurple.withOpacity(0.1),
          width: isLastViewed ? 1.5 : 1,
        ),
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
                color: isLastViewed
                    ? highlightColor
                    : (record.hasCoordinates ? Colors.deepPurple : Colors.grey),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          timeLabel, // 시:분:초
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        if (isLastViewed) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: highlightColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '방금 본 위치',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
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
