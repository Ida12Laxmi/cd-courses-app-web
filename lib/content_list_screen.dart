import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'content_upload_form.dart';
import 'package:url_launcher/url_launcher.dart';
import "config/api_config.dart";
import 'app_logo.dart';

class ContentListScreen extends StatefulWidget {
  final int teacherId;
  final int studentId;
  final String studentName;
  final String contentType;
  final String title;
  final String? userRole; // 'teacher' or 'student'

  const ContentListScreen({
    super.key,
    required this.teacherId,
    required this.studentId,
    required this.studentName,
    required this.contentType,
    required this.title,
    this.userRole = 'student',
  });

  @override
  State<ContentListScreen> createState() => _ContentListScreenState();
}

class _ContentListScreenState extends State<ContentListScreen> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  List<dynamic> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchContent();
  }

  Future<void> _fetchContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final url = Uri.parse(
      '$_baseUrl/accounts/content/${widget.teacherId}/${widget.contentType}/',
    );
    try {
      final response = await http.get(url);
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          _items = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load:${response.body}';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fetch failed: $e');
      setState(() {
        _error = 'Could not connect to server';
        _isLoading = false;
      });
    }
  }

  Future<void> _openItem(dynamic item) async {
    String? urlToOpen;

    final videoLink = item['video_link'];
    final file = item['file'];

    if (videoLink != null && videoLink.toString().isNotEmpty) {
      urlToOpen = videoLink.toString();
    } else if (file != null && file.toString().isNotEmpty) {
      final fileStr = file.toString();
      urlToOpen = fileStr.startsWith('http') ? fileStr : '$_baseUrl$fileStr';
    }

    if (urlToOpen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file or link available')),
      );
      return;
    }

    final uri = Uri.parse(urlToOpen);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $urlToOpen')),
        );
      }
    }
  }

  Future<void> _editItem(dynamic item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContentUploadForm(
          teacherId: widget.teacherId,
          contentType: widget.contentType,
          title: widget.title,
          existingItem: item,
        ),
      ),
    );

    if (result == true || result == null) {
      _fetchContent();
    }
  }

  Future<void> _confirmDelete(dynamic item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item'),
        content: Text(
          'Are you sure you want to delete "${item['title'] ?? 'this item'}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteItem(item);
    }
  }

  Future<void> _deleteItem(dynamic item) async {
    final id = item['id'] ?? item['cid'];
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing item id, cannot delete')),
      );
      return;
    }

    final url = Uri.parse('$_baseUrl/accounts/content/delete/$id/');

    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deleted successfully')),
          );
        }
        _fetchContent();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
          ],
        ),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchContent,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContentUploadForm(
                teacherId: widget.teacherId,
                contentType: widget.contentType,
                title: widget.title,
              ),
            ),
          );
          if (result == true || result == null) {
            _fetchContent();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xFF013768))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchContent, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(
            child: Text(
              'Nothing uploaded yet. Tap + to add.',
              style: TextStyle(color: Color(0xFF013768)),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final bool isVideoLink =
            item['video_link'] != null && item['video_link'].toString().isNotEmpty;
        final String level = item['level']?.toString() ?? 'Basic';
        final String description = item['description']?.toString() ?? '';
        final String subject = item['subject']?.toString() ?? '';

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                textColor: const Color(0xFF0B8081),
                leading: Icon(
                  isVideoLink ? Icons.link : Icons.insert_drive_file,
                  color: const Color(0xFF0B8081),
                ),
                title: Text(
                  item['title'] ?? '',
                  style: const TextStyle(
                    color: Color(0xFF013768),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subject.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          subject,
                          style: const TextStyle(
                            color: Color(0xFF0B8081),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: const TextStyle(color: Color(0xFF013768)),
                      ),
                    const SizedBox(height: 4),
                    _LevelChip(level: level),
                  ],
                ),
                isThreeLine: description.isNotEmpty || subject.isNotEmpty,
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF0B8081),
                ),
                onTap: () => _openItem(item),
              ),
              const Divider(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _editItem(item),
                    icon: const Icon(Icons.edit, size: 18, color: Colors.black),
                    label: const Text('Update', style: TextStyle(color: Colors.black)),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmDelete(item),
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

class _LevelChip extends StatelessWidget {
  final String level;
  const _LevelChip({required this.level});

  Color get _color {
    switch (level) {
      case 'Advance':
        return const Color(0xFF7B1FA2);
      case 'Intermediate':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color, width: 1),
      ),
      child: Text(
        level,
        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}