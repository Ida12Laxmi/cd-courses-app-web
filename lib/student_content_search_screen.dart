import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/api_service.dart';
import 'secure_content_viewer_screen.dart';

class StudentContentSearchScreen extends StatefulWidget {
  final int studentId;
  // When set, search is scoped to just this content type (e.g. 'syllabus').
  // When null, searches across all 7 content types.
  final String? contentType;
  final String? scopeLabel; // e.g. 'Syllabus', shown in the hint/title
  const StudentContentSearchScreen({
    super.key,
    required this.studentId,
    this.contentType,
    this.scopeLabel,
  });

  @override
  State<StudentContentSearchScreen> createState() => _StudentContentSearchScreenState();
}

class _StudentContentSearchScreenState extends State<StudentContentSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<dynamic> _results = [];
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
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
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
      final results = await ApiService.searchContent(widget.studentId, trimmed);
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Search failed: $e';
        _isLoading = false;
      });
    }
  }

  String _labelFor(String type) {
    switch (type) {
      case 'time table':
        return 'Time Table';
      case 'video':
        return 'Video';
      default:
        return type.isEmpty ? '' : '${type[0].toUpperCase()}${type.substring(1)}';
    }
  }

  Future<void> _openItem(dynamic item) async {
    final contentType = item['content_type']?.toString() ?? '';
    final hasFile = item['file'] != null;
    final videoLink = item['video_link']?.toString();
    final isVideo = contentType == 'video';
    final isYoutube = isVideo && videoLink != null &&
        (videoLink.contains('youtube.com') || videoLink.contains('youtu.be'));

    if (isYoutube) {
      final uri = Uri.parse(videoLink);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the video link.')),
        );
      }
      return;
    }

    if (hasFile || (isVideo && videoLink != null && videoLink.isNotEmpty)) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => SecureContentViewerScreen(
          contentId: item['cid'],
          title: item['title'] ?? '',
          contentType: contentType,
          videoLink: hasFile ? null : videoLink,
        ),
      ));
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item['title'] ?? ''),
        content: Text(item['description'] ?? 'No details.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
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
          decoration: const InputDecoration(
            hintText: 'Search syllabus, notes, videos…',
            hintStyle: TextStyle(color: Colors.white70),
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
      return const Center(child: Text('Start typing to search your content.'));
    }
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_results.isEmpty) return const Center(child: Text('No matches found.'));

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = _results[i];
        final type = item['content_type']?.toString() ?? '';
        return ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(item['title'] ?? ''),
          subtitle: Text(_labelFor(type)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openItem(item),
        );
      },
    );
  }
}