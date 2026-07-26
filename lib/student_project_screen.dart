import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class StudentProjectsScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const StudentProjectsScreen({super.key, required this.studentId, required this.studentName});

  @override
  State<StudentProjectsScreen> createState() => _StudentProjectsScreenState();
}

class _StudentProjectsScreenState extends State<StudentProjectsScreen> {
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

    final url = Uri.parse('$_baseUrl/accounts/students/${widget.studentId}/projects/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _submissions = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load projects: ${response.body}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.studentName} — Projects')),
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
          Center(child: Text('No projects submitted yet.')),
        ],
      );
    }

    // View-only — no edit/delete actions here by design.
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _submissions.length,
      itemBuilder: (context, index) {
        final submission = _submissions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const Icon(Icons.folder_special),
            title: Text(submission['title'] ?? ''),
            subtitle: Text(submission['description'] ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openFile(submission),
          ),
        );
      },
    );
  }
}
