import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";
import 'app_logo.dart';

class AddQuestionForm extends StatefulWidget {
  final int quizId;
  // Pass an existing question to edit it instead of creating a new one.
  final dynamic existingQuestion;

  const AddQuestionForm({super.key, required this.quizId, this.existingQuestion});

  @override
  State<AddQuestionForm> createState() => _AddQuestionFormState();
}

class _AddQuestionFormState extends State<AddQuestionForm> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  final TextEditingController questionController = TextEditingController();
  final TextEditingController optionAController = TextEditingController();
  final TextEditingController optionBController = TextEditingController();
  final TextEditingController optionCController = TextEditingController();
  final TextEditingController optionDController = TextEditingController();

  String _correctOption = 'A';
  bool _isLoading = false;

  bool get _isEditing => widget.existingQuestion != null;

  // Adjust this if your Question primary key field is named something
  // other than 'qsid'.
  dynamic get _existingId => widget.existingQuestion?['qsid'];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final q = widget.existingQuestion;
      questionController.text = q['question_text']?.toString() ?? '';
      optionAController.text = q['option_a']?.toString() ?? '';
      optionBController.text = q['option_b']?.toString() ?? '';
      optionCController.text = q['option_c']?.toString() ?? '';
      optionDController.text = q['option_d']?.toString() ?? '';
      _correctOption = q['correct_option']?.toString() ?? 'A';
    }
  }

  Future<void> _addQuestion({required bool addAnother}) async {
    if (questionController.text.trim().isEmpty ||
        optionAController.text.trim().isEmpty ||
        optionBController.text.trim().isEmpty ||
        optionCController.text.trim().isEmpty ||
        optionDController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the question and all four options')),
      );
      return;
    }

    if (_isEditing && _existingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing question id, cannot update')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final uri = _isEditing
        ? Uri.parse('$_baseUrl/accounts/quiz/question/update/$_existingId/')
        : Uri.parse('$_baseUrl/accounts/quiz/${widget.quizId}/add-question/');

    final body = jsonEncode({
      'question_text': questionController.text.trim(),
      'option_a': optionAController.text.trim(),
      'option_b': optionBController.text.trim(),
      'option_c': optionCController.text.trim(),
      'option_d': optionDController.text.trim(),
      'correct_option': _correctOption,
    });

    try {
      final response = _isEditing
          ? await http.patch(uri, headers: {'Content-Type': 'application/json; charset=UTF-8'}, body: body)
          : await http.post(uri, headers: {'Content-Type': 'application/json; charset=UTF-8'}, body: body);

      final success = _isEditing ? response.statusCode == 200 : response.statusCode == 201;

      if (success) {
        if (_isEditing) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Question updated successfully!')),
            );
            Navigator.pop(context, true);
          }
        } else if (addAnother) {
          questionController.clear();
          optionAController.clear();
          optionBController.clear();
          optionCController.clear();
          optionDController.clear();
          setState(() => _correctOption = 'A');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Question added! Add the next one.')),
            );
          }
        } else {
          if (mounted) Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to ${_isEditing ? 'update' : 'add'} question: ${response.body}')),
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

  Widget _optionField(String label, TextEditingController controller, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Radio<String>(
            value: key,
            groupValue: _correctOption,
            onChanged: (v) => setState(() => _correctOption = v!),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(labelText: 'Option $label', border: const OutlineInputBorder()),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        
        title: Row(
  children: [
    const AppLogo(radius: 18),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        _isEditing ? 'Edit Question' : 'Add Question',
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            TextField(
              controller: questionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Question', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            const Text(
              'Options (select the radio button for the correct one)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _optionField('A', optionAController, 'A'),
            _optionField('B', optionBController, 'B'),
            _optionField('C', optionCController, 'C'),
            _optionField('D', optionDController, 'D'),
            const SizedBox(height: 20),
            if (_isEditing)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _addQuestion(addAnother: false),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Update Question'),
                ),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _addQuestion(addAnother: true),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save & Add Another'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => _addQuestion(addAnother: false),
                  child: const Text('Save & Finish'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
