import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'attendance_screen.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final int teacherId;
  const AttendanceHistoryScreen({super.key, required this.teacherId});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000/accounts';

  List<dynamic> _dates = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDates();
  }

  Future<void> _fetchDates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/attendance/dates/${widget.teacherId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _dates = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load history: ${response.body}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect to server';
        _isLoading = false;
      });
    }
  }

  Future<void> _openDate(String dateStr) async {
    final parsed = DateTime.parse(dateStr);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceScreen(teacherId: widget.teacherId, initialDate: parsed),
      ),
    );
    if (result == true) _fetchDates(); // refresh counts if something changed
  }

  Widget _countChip(String label, int count, Color color) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(
        '$label $count',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF212529),
        title: const Text('Attendance History', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(onRefresh: _fetchDates, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchDates, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_dates.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No attendance has been recorded yet.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _dates.length,
      itemBuilder: (context, index) {
        final entry = _dates[index];
        final dateStr = entry['date'] as String;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const Icon(Icons.event_available),
            title: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _countChip('P', entry['present'] ?? 0, Colors.green),
                  _countChip('L', entry['late'] ?? 0, Colors.orange),
                  _countChip('A', entry['absent'] ?? 0, Colors.red),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDate(dateStr),
          ),
        );
      },
    );
  }
}
