import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import "config/api_config.dart";


class TeacherSubmissionSearchScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  final String contentType; // 'assignment' | 'project'
  const TeacherSubmissionSearchScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.contentType,
  });

  @override
  State<TeacherSubmissionSearchScreen> createState() => _TeacherSubmissionSearchScreenState();
}

class _TeacherSubmissionSearchScreenState extends State<TeacherSubmissionSearchScreen> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<dynamic> _given = [];
  List<dynamic> _submissions = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _error;

  bool get _isAssignment => widget.contentType == 'assignment';
  String get _idKey => _isAssignment ? 'asid' : 'psid';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
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

    final uri = Uri.parse(
      '$_baseUrl/accounts/students/${widget.studentId}/${widget.contentType}/search/',
    ).replace(queryParameters: {'q': trimmed});

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _given = data['given'] ?? [];
          _submissions = data['submissions'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Search failed (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Search failed: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openFile(dynamic item) async {
    final file = item['file'];
    if (file == null || file.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file attached')),
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
    final id = submission[_idKey];
    if (id == null) return;

    final endpoint = _isAssignment ? 'assignments' : 'projects';
    final url = Uri.parse('$_baseUrl/accounts/$endpoint/feedback/$id/');
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
        setState(() {
          submission['teacher_feedback'] = feedback;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save feedback: ${response.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    }
  }

  // "Math • Basic" — only includes the parts that actually exist on the item.
  String _metaLine(dynamic item) {
    final subject = (item['subject'] ?? '').toString().trim();
    final level = (item['level'] ?? '').toString().trim();
    return [subject, level].where((e) => e.isNotEmpty).join(' • ');
  }

  bool _hasMetaAndDescription(dynamic item) {
    final description = (item['description'] ?? '').toString().trim();
    return _metaLine(item).isNotEmpty && description.isNotEmpty;
  }

  Widget _buildSubtitle(dynamic item) {
    final meta = _metaLine(item);
    final description = (item['description'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meta.isNotEmpty)
          Text(
            meta,
            style: const TextStyle(
              color: Color(0xFF0B8081),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        if (description.isNotEmpty) Text(description),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search ${widget.studentName}\'s ${_isAssignment ? 'assignments' : 'projects'}…',
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
          Text('Given', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._given.map((g) => Card(
                child: ListTile(
                  leading: const Icon(Icons.assignment_outlined),
                  title: Text(g['title'] ?? ''),
                  subtitle: _buildSubtitle(g),
                  isThreeLine: _hasMetaAndDescription(g),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openFile(g),
                ),
              )),
          const SizedBox(height: 16),
        ],
        if (_submissions.isNotEmpty) ...[
          Text('${widget.studentName}\'s submissions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._submissions.map((s) {
            final feedback = s['teacher_feedback']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: Icon(_isAssignment ? Icons.insert_drive_file : Icons.folder_special),
                    title: Text(s['title'] ?? ''),
                    subtitle: _buildSubtitle(s),
                    isThreeLine: _hasMetaAndDescription(s),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openFile(s),
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
                        onPressed: () => _openFeedbackDialog(s),
                        icon: const Icon(Icons.edit_note, size: 18),
                        label: Text(feedback.isEmpty ? 'Add Feedback' : 'Edit Feedback'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}