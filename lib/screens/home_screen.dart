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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final grouped = await DatabaseHelper.instance.getRecordsGroupedByDate();
    setState(() {
      _grouped = grouped;
      _loading = false;
    });
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    return DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(date);
  }

  String _formatTime(DateTime dt) {
    return DateFormat('HH:mm').format(dt);
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
                          ...records.map((record) => ListTile(
                                leading: const Icon(Icons.location_on_outlined),
                                title: Text(record.simpleAddress),
                                subtitle: Text(_formatTime(record.timestamp)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DetailScreen(record: record),
                                    ),
                                  );
                                },
                              )),
                          const Divider(height: 1),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}
