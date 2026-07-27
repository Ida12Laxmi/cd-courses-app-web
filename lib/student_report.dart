import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

class StudentAttendanceReportScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const StudentAttendanceReportScreen({super.key, required this.studentId, required this.studentName});

  @override
  State<StudentAttendanceReportScreen> createState() => _StudentAttendanceReportScreenState();
}

class _StudentAttendanceReportScreenState extends State<StudentAttendanceReportScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000/accounts';

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
          _error = 'Failed to load report: ${response.body}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF212529),
        title: Text('${widget.studentName} — Report', style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildBody(),
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

    final total = _records.length;
    final present = _records.where((r) => r['status'] == 'present').length;
    final late = _records.where((r) => r['status'] == 'late').length;
    final absent = _records.where((r) => r['status'] == 'absent').length;

    final pPresent = total > 0 ? (present / total * 100) : 0.0;
    final pLate = total > 0 ? (late / total * 100) : 0.0;
    final pAbsent = total > 0 ? (absent / total * 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  '${widget.studentName}\'s Attendance',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Total days recorded: $total', style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: [
                        if (present > 0)
                          PieChartSectionData(
                            color: Colors.green,
                            value: pPresent,
                            title: '${pPresent.toStringAsFixed(1)}%',
                            radius: 50,
                            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        if (late > 0)
                          PieChartSectionData(
                            color: Colors.orange,
                            value: pLate,
                            title: '${pLate.toStringAsFixed(1)}%',
                            radius: 50,
                            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        if (absent > 0)
                          PieChartSectionData(
                            color: Colors.red,
                            value: pAbsent,
                            title: '${pAbsent.toStringAsFixed(1)}%',
                            radius: 50,
                            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatChip(color: Colors.green, label: 'Present', count: present),
                    _StatChip(color: Colors.orange, label: 'Late', count: late),
                    _StatChip(color: Colors.red, label: 'Absent', count: absent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _StatChip({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(width: 12, height: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 4),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
