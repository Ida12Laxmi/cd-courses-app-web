import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'services/api_service.dart';

class StudentAttendanceReportScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const StudentAttendanceReportScreen({super.key, required this.studentId, required this.studentName});

  @override
  State<StudentAttendanceReportScreen> createState() => _StudentAttendanceReportScreenState();
}

class _StudentAttendanceReportScreenState extends State<StudentAttendanceReportScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchAttendanceHistory(widget.studentId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B3D66),
        title: Text('${widget.studentName} — Report'),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load: ${snapshot.error}'));
          }
          final records = snapshot.data ?? [];
          final total = records.length;
          final present = records.where((r) => r['status'] == 'present').length;
          final late = records.where((r) => r['status'] == 'late').length;
          final absent = records.where((r) => r['status'] == 'absent').length;

          double pct(int count) => total > 0 ? (count / total * 100) : 0.0;
          final presentPct = pct(present);
          final latePct = pct(late);
          final absentPct = pct(absent);

          if (total == 0) {
            return const Center(child: Text('No attendance records yet.'));
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text("${widget.studentName}'s Attendance",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Total days recorded: $total',
                        style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 220,
                      child: PieChart(
                        PieChartData(
                          centerSpaceRadius: 60,
                          sectionsSpace: 2,
                          sections: [
                            if (present > 0)
                              PieChartSectionData(
                                value: present.toDouble(),
                                color: const Color(0xFF4CAF50),
                                title: '${presentPct.toStringAsFixed(0)}%',
                                radius: 60,
                                titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            if (late > 0)
                              PieChartSectionData(
                                value: late.toDouble(),
                                color: const Color(0xFFFF9800),
                                title: '${latePct.toStringAsFixed(0)}%',
                                radius: 60,
                                titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            if (absent > 0)
                              PieChartSectionData(
                                value: absent.toDouble(),
                                color: const Color(0xFFF44336),
                                title: '${absentPct.toStringAsFixed(0)}%',
                                radius: 60,
                                titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _Legend(color: const Color(0xFF4CAF50), label: 'Present', count: present),
                        _Legend(color: const Color(0xFFFF9800), label: 'Late', count: late),
                        _Legend(color: const Color(0xFFF44336), label: 'Absent', count: absent),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _Legend({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(width: 12, height: 12, color: color),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        const SizedBox(height: 4),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}