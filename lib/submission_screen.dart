import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'services/api_service.dart';

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
  String? _pickedFilePath;
  String? _pickedFileName;
  bool _submitting = false;
  late Future<List<dynamic>> _questions;
  late Future<List<dynamic>> _history;

  @override
  void initState() {
    super.initState();
    _questions = ApiService.fetchContent(widget.studentId, widget.contentType);
    _history = widget.contentType == 'assignment'
        ? ApiService.fetchAssignmentSubmissions(widget.studentId)
        : ApiService.fetchProjectSubmissions(widget.studentId);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pickedFilePath = result.files.single.path;
        _pickedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty || _pickedFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title and pick a file first.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      if (widget.contentType == 'assignment') {
        await ApiService.submitAssignment(
          studentId: widget.studentId,
          title: _titleController.text.trim(),
          filePath: _pickedFilePath!,
          description: _noteController.text.trim(),
        );
      } else {
        await ApiService.submitProject(
          studentId: widget.studentId,
          title: _titleController.text.trim(),
          filePath: _pickedFilePath!,
          description: _noteController.text.trim(),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted successfully.')));
        _titleController.clear();
        _noteController.clear();
        setState(() {
          _pickedFilePath = null;
          _pickedFileName = null;
          _history = widget.contentType == 'assignment'
              ? ApiService.fetchAssignmentSubmissions(widget.studentId)
              : ApiService.fetchProjectSubmissions(widget.studentId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submission failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                children: items.map((q) => Card(
                  child: ListTile(
                    title: Text(q['title'] ?? ''),
                    subtitle: Text(q['description'] ?? ''),
                  ),
                )).toList(),
              );
            },
          ),
          const Divider(height: 32),
          Text('Submit your work', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _noteController, maxLines: 3, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.attach_file), label: const Text('Pick file')),
              const SizedBox(width: 12),
              Expanded(child: Text(_pickedFileName ?? 'No file selected', overflow: TextOverflow.ellipsis)),
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
                children: items.map((s) => ListTile(
                  title: Text(s['title'] ?? ''),
                  subtitle: Text(s['teacher_feedback'] != null && s['teacher_feedback'] != ''
                      ? 'Feedback: ${s['teacher_feedback']}' : 'Awaiting review'),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}