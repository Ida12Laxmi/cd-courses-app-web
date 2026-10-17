import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";
import 'app_logo.dart';

/// Shown inside a popup dialog (see QuizListScreen._openQuizForm).
///
/// Pops with:
///  - `true` after a successful edit
///  - `{'created': true, 'quid': ..., 'title': ...}` after a successful create
///  - `null` if the user just closes it
class CreateQuizScreen extends StatefulWidget {
  final int teacherId;
  // Pass an existing quiz to edit it instead of creating a new one.
  final dynamic existingQuiz;

  const CreateQuizScreen({super.key, required this.teacherId, this.existingQuiz});

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  // Keep in sync with Student.LEVEL_CHOICES on the backend.
  static const List<String> _levels = ['Basic', 'Intermediate', 'Advance'];

  final TextEditingController titleController = TextEditingController();
  final TextEditingController subjectController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  String _selectedLevel = 'Basic';
  bool _isLoading = false;
  String? _errorMessage; // shown inside the dialog

  bool get _isEditing => widget.existingQuiz != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      titleController.text = widget.existingQuiz['title']?.toString() ?? '';
      subjectController.text = widget.existingQuiz['subject']?.toString() ?? '';
      descriptionController.text = widget.existingQuiz['description']?.toString() ?? '';

      final existingLevel = widget.existingQuiz['level']?.toString();
      if (existingLevel != null && _levels.contains(existingLevel)) {
        _selectedLevel = existingLevel;
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    subjectController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  dynamic get _existingId => widget.existingQuiz?['quid'];

  Future<void> _submit() async {
    if (titleController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Quiz title is required');
      return;
    }

    if (_isEditing && _existingId == null) {
      setState(() => _errorMessage = 'Missing quiz id, cannot update');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uri = _isEditing
        ? Uri.parse('$_baseUrl/accounts/quiz/update/$_existingId/')
        : Uri.parse('$_baseUrl/accounts/quiz/create/');

    try {
      final response = _isEditing
          ? await http.patch(
              uri,
              headers: {'Content-Type': 'application/json; charset=UTF-8'},
              body: jsonEncode({
                'title': titleController.text.trim(),
                'subject': subjectController.text.trim(),
                'description': descriptionController.text.trim(),
                'level': _selectedLevel,
              }),
            )
          : await http.post(
              uri,
              headers: {'Content-Type': 'application/json; charset=UTF-8'},
              body: jsonEncode({
                'teacher': widget.teacherId,
                'title': titleController.text.trim(),
                'subject': subjectController.text.trim(),
                'description': descriptionController.text.trim(),
                'level': _selectedLevel,
              }),
            );

      final success = _isEditing ? response.statusCode == 200 : response.statusCode == 201;

      if (success) {
        final data = jsonDecode(response.body);
        final quizId = _isEditing ? _existingId : data['quid'];

        if (quizId == null) {
          if (mounted) {
            setState(() => _errorMessage = 'No quiz id returned. Response: ${response.body}');
          }
          return;
        }

        if (mounted) {
          if (_isEditing) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Quiz updated successfully!')),
            );
            Navigator.pop(context, true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Quiz created! Now add some questions.')),
            );
            // Close the popup and hand the new quiz back to the list screen,
            // which then opens the questions screen.
            Navigator.pop(context, {
              'created': true,
              'quid': quizId,
              'title': titleController.text.trim(),
            });
          }
        }
      } else {
        if (mounted) {
          setState(() => _errorMessage =
              '${_isEditing ? 'Update' : 'Create'} failed: ${response.body}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not connect to server');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    _isEditing ? 'Edit Quiz' : 'Create Quiz',
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
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 10),

            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Quiz Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              initialValue: _selectedLevel,
              decoration: const InputDecoration(labelText: 'Level', border: OutlineInputBorder()),
              items: _levels
                  .map((level) => DropdownMenuItem(value: level, child: Text(level)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedLevel = value);
              },
            ),
            const SizedBox(height: 15),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),

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
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isEditing ? 'Update Quiz' : 'Create & Add Questions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}