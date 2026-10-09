import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'student_list_screen.dart';
import "config/api_config.dart";
import 'app_logo.dart';

class AttendanceScreen extends StatefulWidget {
  final int teacherId;
  final DateTime? initialDate;
  const AttendanceScreen({super.key, required this.teacherId, this.initialDate});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static const String _baseUrl = ApiConfig.baseUrl;

  late DateTime _selectedDate;
  List<dynamic> _students = [];
  // sid -> status ('present' | 'absent' | 'late')
  final Map<int, String> _statusMap = {};

  // Subject filter: key = lowercase/trimmed subject ('' = no subject), value = label shown on chip
  Map<String, String> _subjects = {};
  String? _selectedSubject; // null until the teacher picks one

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

  String _subjectKey(dynamic student) =>
      (student['subject'] ?? '').toString().trim().toLowerCase();

  // Students of the currently selected subject only.
  List<dynamic> get _visibleStudents {
    if (_selectedSubject == null) return [];
    return _students.where((s) => _subjectKey(s) == _selectedSubject).toList();
  }

  int _countFor(String key) => _students.where((s) => _subjectKey(s) == key).length;

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

        final found = <String, String>{};
        for (var s in data) {
          _statusMap[s['sid']] = s['status'] ?? 'present'; // default to present if unmarked
          final raw = (s['subject'] ?? '').toString().trim();
          found.putIfAbsent(raw.toLowerCase(), () => raw.isEmpty ? 'No subject' : raw);
        }

        // sort subjects alphabetically by label
        final keys = found.keys.toList()
          ..sort((a, b) => found[a]!.toLowerCase().compareTo(found[b]!.toLowerCase()));
        final sorted = {for (final k in keys) k: found[k]!};

        // keep the previous choice if it still exists; auto-pick when there is only one subject
        String? selected = _selectedSubject;
        if (selected != null && !sorted.containsKey(selected)) selected = null;
        if (selected == null && sorted.length == 1) selected = sorted.keys.first;

        setState(() {
          _students = data;
          _subjects = sorted;
          _selectedSubject = selected;
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
      firstDate: DateTime(2026),
      lastDate: DateTime.now().add(const Duration(days: 0)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _fetchAttendance();
    }
  }

  Future<void> _saveAttendance() async {
    if (_selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a subject first')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Only save the students of the selected subject.
    final visibleIds = _visibleStudents.map((s) => s['sid'] as int).toSet();
    final records = _statusMap.entries
        .where((e) => visibleIds.contains(e.key))
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
    final bool showSave = !_isLoading &&
        _error == null &&
        _selectedSubject != null &&
        _visibleStudents.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Text('Attendance', style: TextStyle(color: Colors.white)),
          ],
        ),
        automaticallyImplyLeading: true,
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
          if (!_isLoading && _error == null && _students.isNotEmpty) _buildSubjectSelector(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: showSave
          ? SafeArea(
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
            )
          : null,
    );
  }

  Widget _buildSubjectSelector() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select subject',
            style: TextStyle(color: Color(0xFF013768), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _subjects.entries.map((e) {
                final isSelected = _selectedSubject == e.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${e.value} (${_countFor(e.key)})'),
                    selected: isSelected,
                    selectedColor: const Color(0xFF013768),
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF013768),
                    ),
                    onSelected: (_) => setState(() => _selectedSubject = e.key),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
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

    if (_selectedSubject == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Select a subject above to take attendance.',
            style: TextStyle(color: Color(0xFF013768)),
          ),
        ),
      );
    }

    final visible = _visibleStudents;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final student = visible[index];
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