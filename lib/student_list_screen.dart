import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'student_register.dart';
import 'student_detail_screen.dart';
import 'chat_message.dart';

class StudentListScreen extends StatefulWidget {
  final int teacherId;
  final String? chatTopic;
  const StudentListScreen({super.key, required this.teacherId, this.chatTopic});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000';

  List<dynamic> _students = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/accounts/students/teacher/${widget.teacherId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _students = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load students: ${response.body}';
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

  Future<void> _editStudent(dynamic student) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddStudentForm(teacherId: widget.teacherId, existingStudent: student),
      ),
    );
    if (result == true) _fetchStudents();
  }

  Future<void> _confirmDelete(dynamic student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete student'),
        content: Text(
          'Are you sure you want to remove "${student['username'] ?? 'this student'}"? '
          'Their assignment and project submissions will be deleted too.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) _deleteStudent(student);
  }

  Future<void> _deleteStudent(dynamic student) async {
    final id = student['sid'];
    if (id == null) return;

    final url = Uri.parse('$_baseUrl/accounts/students/delete/$id/');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Student removed')),
          );
        }
        _fetchStudents();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    }
  }

  Color _levelColor(String? level) {
    switch (level) {
      case 'Intermediate':
        return Colors.orange;
      case 'Advance':
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Students')),
      body: RefreshIndicator(onRefresh: _fetchStudents, child: _buildBody()),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddStudentForm(teacherId: widget.teacherId)),
          );
          if (result == true) _fetchStudents();
        },
        child: const Icon(Icons.add),
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
            ElevatedButton(onPressed: _fetchStudents, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_students.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No students yet. Tap + to add one.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _students.length,
      itemBuilder: (context, index) {
        final student = _students[index];
        final level = student['level']?.toString() ?? 'Basic';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(student['username'] ?? ''),
                subtitle: Text(
                  [student['email'], student['phone']]
                      .where((e) => e != null && e.toString().isNotEmpty)
                      .join(' • '),
                ),
                trailing: Chip(
                  label: Text(level, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: _levelColor(level),
                  padding: EdgeInsets.zero,
                ),
               onTap: () {
  if (widget.chatTopic != null) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          topicTitle: widget.chatTopic!,
          currentUserType: 'teacher',
          teacherId: widget.teacherId,
          studentId: student['sid'],
        ),
      ),
    );
  } else {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentDetailScreen(
          studentId: student['sid'],
          studentName: student['username'] ?? '',
          teacherId: widget.teacherId,
        ),
      ),
    );
  }
},
              ),
              const Divider(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _editStudent(student),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmDelete(student),
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
