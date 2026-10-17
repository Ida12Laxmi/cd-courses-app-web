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

  void _refreshHistory() {
    setState(() {
      _history = _isAssignment
          ? ApiService.fetchAssignmentSubmissions(widget.studentId)
          : ApiService.fetchProjectSubmissions(widget.studentId);
    });
  }

  // ---- Submit / edit popup ----

  /// Opens the submit form as a popup. Pass [submission] to edit an existing one.
  Future<void> _openSubmitForm({dynamic submission}) async {
    final isEditing = submission != null;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // tapping outside won't close it by accident
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: _SubmissionFormDialog(
            studentId: widget.studentId,
            contentType: widget.contentType,
            existingSubmission: submission,
          ),
        ),
      ),
    );

    if (saved == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEditing ? 'Submission updated.' : 'Submitted successfully.')),
        );
      }
      _refreshHistory();
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSubmitForm(),
        icon: const Icon(Icons.upload_file),
        label: Text('Submit ${_isAssignment ? 'Assignment' : 'Project'}'),
      ),
      body: ListView(
        // Extra bottom padding so the floating button never covers the last card.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
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
          Text('Past submissions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<List<dynamic>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) return const Text('No submissions yet. Tap the button below to submit.');
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
                              onPressed: () => _openSubmitForm(submission: s),
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

/// Popup form used for both submitting new work and editing an existing
/// submission. Pops with `true` after a successful save.
class _SubmissionFormDialog extends StatefulWidget {
  final int studentId;
  final String contentType; // 'assignment' | 'project'
  final dynamic existingSubmission; // pass a submission map to edit

  const _SubmissionFormDialog({
    required this.studentId,
    required this.contentType,
    this.existingSubmission,
  });

  @override
  State<_SubmissionFormDialog> createState() => _SubmissionFormDialogState();
}

class _SubmissionFormDialogState extends State<_SubmissionFormDialog> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  PlatformFile? _pickedFile; // works on web (bytes) and mobile (path)
  bool _submitting = false;
  String? _errorMessage;

  bool get _isAssignment => widget.contentType == 'assignment';
  bool get _isEditing => widget.existingSubmission != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleController.text = widget.existingSubmission['title']?.toString() ?? '';
      _noteController.text = widget.existingSubmission['description']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
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
    final title = _titleController.text.trim();
    final note = _noteController.text.trim();

    if (title.isEmpty) {
      setState(() => _errorMessage = 'Please add a title.');
      return;
    }
    // A file is required for a new submission; optional when editing.
    if (!_isEditing && _pickedFile == null) {
      setState(() => _errorMessage = 'Please pick a file.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      if (_isEditing) {
        if (_isAssignment) {
          await ApiService.updateOwnAssignment(
            asid: widget.existingSubmission['asid'],
            studentId: widget.studentId,
            title: title,
            description: note,
            file: _pickedFile,
          );
        } else {
          await ApiService.updateOwnProject(
            psid: widget.existingSubmission['psid'],
            studentId: widget.studentId,
            title: title,
            description: note,
            file: _pickedFile,
          );
        }
      } else {
        if (_isAssignment) {
          await ApiService.submitAssignment(
            studentId: widget.studentId,
            title: title,
            file: _pickedFile!,
            description: note,
          );
        } else {
          await ApiService.submitProject(
            studentId: widget.studentId,
            title: title,
            file: _pickedFile!,
            description: note,
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '${_isEditing ? 'Update' : 'Submission'} failed: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String typeLabel = _isAssignment ? 'Assignment' : 'Project';

    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const AppLogo(radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit submission' : 'Submit $typeLabel',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF013768),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF013768)),
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 10),

            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _isEditing ? 'Note' : 'Note (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_isEditing ? 'Replace file' : 'Pick file'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _pickedFile?.name ?? (_isEditing ? 'Keep current file' : 'No file selected'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'Save' : 'Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}