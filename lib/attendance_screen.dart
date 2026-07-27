import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'student_list_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final int teacherId;
  final DateTime? initialDate;
  const AttendanceScreen({super.key, required this.teacherId, this.initialDate});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000/accounts';

  late DateTime _selectedDate;
  List<dynamic> _students = [];
  // sid -> status ('present' | 'absent' | 'late')
  final Map<int, String> _statusMap = {};

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _fetchAttendance();
  }

  String get _dateStr =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  Future<void> _fetchAttendance() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/attendance/${widget.teacherId}/?date=$_dateStr');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        _statusMap.clear();
        for (var s in data) {
          _statusMap[s['sid']] = s['status'] ?? 'present'; // default to present if unmarked
        }
        setState(() {
          _students = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load attendance: ${response.body}';
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _fetchAttendance();
    }
  }

  Future<void> _saveAttendance() async {
    setState(() => _isSaving = true);

    final records = _statusMap.entries
        .map((e) => {'student': e.key, 'status': e.value})
        .toList();

    final url = Uri.parse('$_baseUrl/attendance/save/');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'teacher': widget.teacherId,
          'date': _dateStr,
          'records': records,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attendance saved!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF212529),
        title: const Text('Attendance', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.insert_chart_outlined, color: Colors.white),
            tooltip: 'Student Report',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentListScreen(teacherId: widget.teacherId, attendanceReportMode: true),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            tooltip: 'View History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentListScreen(teacherId: widget.teacherId, attendanceHistoryMode: true),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: _pickDate,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFF212529),
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(
              child: TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.edit_calendar, color: Colors.white, size: 18),
                label: Text(
                  _dateStr,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _isLoading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveAttendance,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF212529)),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Save Attendance', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ),
            ),
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
            ElevatedButton(onPressed: _fetchAttendance, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_students.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No students added yet. Add students first from Manage Students.'),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _students.length,
      itemBuilder: (context, index) {
        final student = _students[index];
        final sid = student['sid'] as int;
        final currentStatus = _statusMap[sid] ?? 'present';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    student['username'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                ToggleButtons(
                  borderRadius: BorderRadius.circular(8),
                  isSelected: [
                    currentStatus == 'present',
                    currentStatus == 'late',
                    currentStatus == 'absent',
                  ],
                  onPressed: (i) {
                    setState(() {
                      _statusMap[sid] = ['present', 'late', 'absent'][i];
                    });
                  },
                  selectedColor: Colors.white,
                  fillColor: _statusColor(currentStatus),
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('P')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('L')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('A')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
