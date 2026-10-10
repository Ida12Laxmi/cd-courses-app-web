import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'services/api_service.dart';
import 'student_submission_search_screen.dart';
//import 'package:url_launcher/url_launcher.dart';
import 'secure_content_viewer_screen.dart';
import 'app_logo.dart';

class SubmissionScreen extends StatefulWidget {
  final int studentId;
  final String contentType; // 'assignment' | 'project'
  final String title;
  const SubmissionScreen({super.key, required this.studentId, required this.contentType, required this.title});

  @override
  State<SubmissionScreen> createState() => _SubmissionScreenState();
}

class _SubmissionScreenState extends State<SubmissionScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  PlatformFile? _pickedFile; // works on web (bytes) and mobile (path)
  bool _submitting = false;
  late Future<List<dynamic>> _questions;
  late Future<List<dynamic>> _history;

  bool get _isAssignment => widget.contentType == 'assignment';

  @override
  void initState() {
    super.initState();
    _questions = ApiService.fetchContent(widget.studentId, widget.contentType);
    _history = _isAssignment
        ? ApiService.fetchAssignmentSubmissions(widget.studentId)
        : ApiService.fetchProjectSubmissions(widget.studentId);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _refreshHistory() {
    setState(() {
      _history = _isAssignment
          ? ApiService.fetchAssignmentSubmissions(widget.studentId)
          : ApiService.fetchProjectSubmissions(widget.studentId);
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb, // bytes are required on web
    );
    if (result != null) {
      setState(() => _pickedFile = result.files.single);
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty || _pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title and pick a file first.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_isAssignment) {
        await ApiService.submitAssignment(
          studentId: widget.studentId,
          title: _titleController.text.trim(),
          file: _pickedFile!,
          description: _noteController.text.trim(),
        );
      } else {
        await ApiService.submitProject(
          studentId: widget.studentId,
          title: _titleController.text.trim(),
          file: _pickedFile!,
          description: _noteController.text.trim(),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted successfully.')));
        _titleController.clear();
        _noteController.clear();
        setState(() => _pickedFile = null);
        _refreshHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submission failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---- Edit own submission ----

  Future<void> _openEditDialog(dynamic submission) async {
    final editTitleController = TextEditingController(text: submission['title'] ?? '');
    final editNoteController = TextEditingController(text: submission['description'] ?? '');
    PlatformFile? newFile;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit submission'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: editTitleController,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: editNoteController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf'],
                          withData: kIsWeb,
                        );
                        if (result != null) {
                          setDialogState(() => newFile = result.files.single);
                        }
                      },
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Replace file'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        newFile?.name ?? 'Keep current file',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    if (editTitleController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title cannot be empty.')));
      }
      return;
    }

    try {
      if (_isAssignment) {
        await ApiService.updateOwnAssignment(
          asid: submission['asid'],
          studentId: widget.studentId,
          title: editTitleController.text.trim(),
          description: editNoteController.text.trim(),
          file: newFile,
        );
      } else {
        await ApiService.updateOwnProject(
          psid: submission['psid'],
          studentId: widget.studentId,
          title: editTitleController.text.trim(),
          description: editNoteController.text.trim(),
          file: newFile,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submission updated.')));
      }
      _refreshHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  // ---- Delete own submission ----

  Future<void> _confirmDelete(dynamic submission) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete submission'),
        content: const Text('Are you sure you want to delete this submission?'),
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
    if (confirmed != true) return;

    try {
      if (_isAssignment) {
        await ApiService.deleteOwnAssignment(submission['asid'], widget.studentId);
      } else {
        await ApiService.deleteOwnProject(submission['psid'], widget.studentId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submission deleted.')));
      }
      _refreshHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _openFile(dynamic submission) async {
    final rawUrl = submission['file'] ?? submission['file_url'];
    if (rawUrl == null || rawUrl.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file attached to this submission.')),
      );
      return;
    }

    final path = rawUrl.toString();
    final fullUrl = path.startsWith('http') ? path : '${ApiService.mediaOrigin}$path';
    final fileName = path.split('/').last;
    final title = (submission['title'] ?? fileName).toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SecureContentViewerScreen.forAttachment(
          url: fullUrl,
          fileName: fileName,
          title: title,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            Text(widget.title),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentSubmissionSearchScreen(
                  studentId: widget.studentId,
                  contentType: widget.contentType,
                  title: widget.title,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Given by your teacher', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<List<dynamic>>(
            future: _questions,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) return const Text('Nothing posted yet.');
              return Column(
                children: items
                    .map((q) => Card(
                          child: ListTile(
                            title: Text(q['title'] ?? ''),
                            subtitle: Text(q['description'] ?? ''),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openFile(q),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const Divider(height: 32),
          Text('Submit your work', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file),
                label: const Text('Pick file'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _pickedFile?.name ?? 'No file selected',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit'),
            ),
          ),
          const Divider(height: 32),
          Text('Past submissions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<List<dynamic>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) return const Text('No submissions yet.');
              return Column(
                children: items.map((s) {
                  final feedback = s['teacher_feedback']?.toString() ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: Text(s['title'] ?? ''),
                          subtitle: Text(feedback.isNotEmpty ? 'Feedback: $feedback' : 'Awaiting review'),
                          onTap: () => _openFile(s),
                        ),
                        const Divider(height: 1),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => _openEditDialog(s),
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit'),
                            ),
                            TextButton.icon(
                              onPressed: () => _confirmDelete(s),
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              label: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}