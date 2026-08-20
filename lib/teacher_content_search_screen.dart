import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class TeacherContentSearchScreen extends StatefulWidget {
  final int teacherId;
  // When set, search is scoped to just this content type (e.g. 'syllabus').
  // When null, searches across all content types.
  final String? contentType;
  final String? scopeLabel;
  const TeacherContentSearchScreen({
    super.key,
    required this.teacherId,
    this.contentType,
    this.scopeLabel,
  });

  @override
  State<TeacherContentSearchScreen> createState() => _TeacherContentSearchScreenState();
}

class _TeacherContentSearchScreenState extends State<TeacherContentSearchScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000/accounts';

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<dynamic> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _error;

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

    final uri = Uri.parse('$_baseUrl/teacher/${widget.teacherId}/search/').replace(
      queryParameters: {
        'q': trimmed,
        if (widget.contentType != null) 'type': widget.contentType,
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        setState(() {
          _results = jsonDecode(response.body);
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
            hintText: widget.scopeLabel != null
                ? 'Search ${widget.scopeLabel}…'
                : 'Search syllabus, notes, videos…',
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
          subtitle: Text(
            item['level'] != null ? '${_labelFor(type)} · Level: ${item['level']}' : _labelFor(type),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Wire this to whatever detail/viewer flow your teacher-side
            // content list already uses (e.g. same viewer ContentListScreen opens on tap).
          },
        );
      },
    );
  }
}