import 'dart:async';
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'secure_content_viewer_screen.dart';

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

  // Opens the file inside the app via SecureContentViewerScreen instead of
  // handing it off to an external app (browser, PDF/photo viewer, etc). This
  // is what enables screenshot/recording protection and keeps the file from
  // ever leaving the app's own viewer — applies the same way to files the
  // teacher gave and files the student submitted, since both come through
  // this one function.
  void _openFile(dynamic item) {
    final rawUrl = item['file'] ?? item['file_url'];
    if (rawUrl == null || rawUrl.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file attached.')),
      );
      return;
    }

    final path = rawUrl.toString();
    final fullUrl = path.startsWith('http') ? path : '${ApiService.mediaOrigin}$path';

    // SecureContentViewerScreen.forAttachment picks how to render the file
    // (PDF/video/image/unsupported) based on the file's extension, so pull
    // a filename out of the URL for it to inspect. Falls back to the item's
    // title if the URL has no path segments for some reason.
    final uri = Uri.tryParse(fullUrl);
    final fileName = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : (item['title']?.toString() ?? 'file');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SecureContentViewerScreen.forAttachment(
          url: fullUrl,
          fileName: fileName,
          title: item['title']?.toString(),
        ),
      ),
    );
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
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openFile(item),
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
               trailing: const Icon(Icons.chevron_right),
               onTap: () => _openFile(s),
            );
          }),
        ],
      ],
    );
  }
}