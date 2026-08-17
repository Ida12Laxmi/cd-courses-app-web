import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'teacher_submission_search_screen.dart';

class StudentAssignmentsScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const StudentAssignmentsScreen({super.key, required this.studentId, required this.studentName});

  @override
  State<StudentAssignmentsScreen> createState() => _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000';

  List<dynamic> _submissions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSubmissions();
  }

  Future<void> _fetchSubmissions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/accounts/students/${widget.studentId}/assignments/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _submissions = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load assignments: ${response.body}';
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

  Future<void> _openFile(dynamic submission) async {
    final file = submission['file'];
    if (file == null || file.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file attached to this submission')),
      );
      return;
    }
    final fileStr = file.toString();
    final urlToOpen = fileStr.startsWith('http') ? fileStr : '$_baseUrl$fileStr';
    final uri = Uri.parse(urlToOpen);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $urlToOpen')),
      );
    }
  }

  Future<void> _openFeedbackDialog(dynamic submission) async {
    final controller = TextEditingController(text: submission['teacher_feedback']?.toString() ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Feedback'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Write feedback for this submission...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _saveFeedback(submission, result);
    }
  }

  Future<void> _saveFeedback(dynamic submission, String feedback) async {
    final id = submission['asid'];
    if (id == null) return;

    final url = Uri.parse('$_baseUrl/accounts/assignments/feedback/$id/');
    try {
      final response = await http.patch(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'teacher_feedback': feedback}),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Feedback saved')),
          );
        }
        _fetchSubmissions();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save feedback: ${response.body}')),
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.studentName} — Assignments'),backgroundColor: const Color(0xFF013768),foregroundColor: Colors.white,
      actions: [
        IconButton(icon: const Icon(Icons.search),
        tooltip: 'Search',
        onPressed:  () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TeacherSubmissionSearchScreen(
            studentId: widget.studentId,
            studentName: widget.studentName,
            contentType: 'assignment',
          ),
        ),
      ),
)
      ],
      ),
      body: RefreshIndicator(onRefresh: _fetchSubmissions, child: _buildBody()),
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
            ElevatedButton(onPressed: _fetchSubmissions, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_submissions.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No assignments submitted yet.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _submissions.length,
      itemBuilder: (context, index) {
        final submission = _submissions[index];
        final feedback = submission['teacher_feedback']?.toString() ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text(submission['title'] ?? ''),
                subtitle: Text(submission['description'] ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openFile(submission),
              ),
              if (feedback.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Feedback: $feedback',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                  ),
                ),
              const Divider(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _openFeedbackDialog(submission),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(feedback.isEmpty ? 'Add Feedback' : 'Edit Feedback'),
                  ),
                /*  TextButton.icon(
                    onPressed: () => _confirmDelete(submission),
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),*/
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
