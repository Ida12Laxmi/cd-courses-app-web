import 'dart:async';
import 'package:flutter/material.dart';
import 'services/api_service.dart';

class StudentSubmissionSearchScreen extends StatefulWidget {
  final int studentId;
  final String contentType; // 'assignment' | 'project'
  final String title; // e.g. 'Assignments' | 'Project'
  const StudentSubmissionSearchScreen({
    super.key,
    required this.studentId,
    required this.contentType,
    required this.title,
  });

  @override
  State<StudentSubmissionSearchScreen> createState() => _StudentSubmissionSearchScreenState();
}

class _StudentSubmissionSearchScreenState extends State<StudentSubmissionSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<dynamic> _given = [];
  List<dynamic> _submissions = [];
  bool _isLoading = false;
  String? _error;
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(value));
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _given = [];
        _submissions = [];
        _hasSearched = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
    });

    try {
      final data = await ApiService.searchAssignmentorProject(
        widget.studentId, widget.contentType, trimmed,
      );
      setState(() {
        _given = data['given'] ?? [];
        _submissions = data['submissions'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Search failed: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search ${widget.title.toLowerCase()}…',
            hintStyle: const TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_hasSearched) {
      return const Center(child: Text('Start typing to search.'));
    }
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_given.isEmpty && _submissions.isEmpty) {
      return const Center(child: Text('No matches found.'));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_given.isNotEmpty) ...[
          Text('Given by your teacher', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._given.map((item) => Card(
                child: ListTile(
                  title: Text(item['title'] ?? ''),
                  subtitle: Text(item['description'] ?? ''),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(item['title'] ?? ''),
                      content: Text(item['description'] ?? 'No details.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                      ],
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 20),
        ],
        if (_submissions.isNotEmpty) ...[
          Text('Past submissions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._submissions.map((s) {
            final feedback = s['teacher_feedback'];
            return ListTile(
              title: Text(s['title'] ?? ''),
              subtitle: Text(
                feedback != null && feedback.toString().isNotEmpty
                    ? 'Feedback: $feedback'
                    : 'Awaiting review',
              ),
            );
          }),
        ],
      ],
    );
  }
}