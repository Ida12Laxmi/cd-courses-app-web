import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'attendance_screen.dart';
import "config/api_config.dart";

class StudentAttendanceHistoryScreen extends StatefulWidget {
  final int teacherId;
  final int studentId;
  final String studentName;
  const StudentAttendanceHistoryScreen({
    super.key,
    required this.teacherId,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentAttendanceHistoryScreen> createState() => _StudentAttendanceHistoryScreenState();
}

class _StudentAttendanceHistoryScreenState extends State<StudentAttendanceHistoryScreen> {
  static const String _baseUrl = ApiConfig.baseUrl;

  List<dynamic> _records = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/attendance/student/${widget.studentId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _records = jsonDecode(response.body);
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

  Color _statusColor(String status) {
    switch (status) {
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'absent':
        return Icons.cancel;
      case 'late':
        return Icons.watch_later;
      default:
        return Icons.check_circle;
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
    if (result == true) _fetchHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        title: Text('${widget.studentName} — History', style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(onRefresh: _fetchHistory, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!.length > 300 ? '${_error!.substring(0, 300)}...' : _error!,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchHistory, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_records.isEmpty) {
      return const Center(child: Text('No attendance recorded for this student yet.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final record = _records[index];
        final status = record['status'] ?? 'present';
        final remarks = record['remarks']?.toString() ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Icon(_statusIcon(status), color: _statusColor(status)),
            title: Text(record['date'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: remarks.isNotEmpty ? Text(remarks) : null,
            trailing: Chip(
              label: Text(
                status[0].toUpperCase() + status.substring(1),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              backgroundColor: _statusColor(status),
              padding: EdgeInsets.zero,
            ),
            onTap: () => _openDate(record['date']),
          ),
        );
      },
    );
  }
}
