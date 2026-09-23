import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'quiz_questions_screen.dart';
import "config/api_config.dart";
import 'app_logo.dart';

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
  final TextEditingController descriptionController = TextEditingController();
  String _selectedLevel = 'Basic';
  bool _isLoading = false;

  bool get _isEditing => widget.existingQuiz != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      titleController.text = widget.existingQuiz['title']?.toString() ?? '';
      descriptionController.text = widget.existingQuiz['description']?.toString() ?? '';

      final existingLevel = widget.existingQuiz['level']?.toString();
      if (existingLevel != null && _levels.contains(existingLevel)) {
        _selectedLevel = existingLevel;
      }
    }
  }

  dynamic get _existingId => widget.existingQuiz?['quid'];

  Future<void> _submit() async {
    if (titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quiz title is required')),
      );
      return;
    }

    if (_isEditing && _existingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing quiz id, cannot update')),
      );
      return;
    }

    setState(() => _isLoading = true);

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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No quiz id returned. Response: ${response.body}')),
            );
          }
          setState(() => _isLoading = false);
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
            // Replace this screen with the questions screen so the back
            // button returns straight to the quiz list, with questions added.
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => QuizQuestionsScreen(
                  quizId: quizId,
                  quizTitle: titleController.text.trim(),
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_isEditing ? 'Update' : 'Create'} failed: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      
       // title: Text(_isEditing ? 'Edit Quiz' : 'Create Quiz'),
       title: Row(
  children: [
    const AppLogo(radius: 18),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        _isEditing ? 'Edit Quiz' : 'Create Quiz',
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Quiz Title', border: OutlineInputBorder()),
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
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
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
