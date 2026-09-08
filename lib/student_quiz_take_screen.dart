import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";

class StudentQuizTakeScreen extends StatefulWidget {
  final int quizId;
  final String quizTitle;
  final int studentId;
  const StudentQuizTakeScreen({
    super.key,
    required this.quizId,
    required this.quizTitle,
    required this.studentId,
  });

  @override
  State<StudentQuizTakeScreen> createState() => _StudentQuizTakeScreenState();
}

class _StudentQuizTakeScreenState extends State<StudentQuizTakeScreen> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  Map<String, dynamic>? _quiz;
  bool _isLoading = true;
  String? _error;
  bool _submitting = false;

  // question qsid -> selected option letter ('A'/'B'/'C'/'D')
  final Map<int, String> _selected = {};

  // set after a successful submit, to show score instead of the form
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _fetchQuiz();
  }

  Future<void> _fetchQuiz() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/accounts/quiz/${widget.quizId}/take/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _quiz = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load quiz: ${response.body}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect to server';
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    final questions = (_quiz?['questions'] as List?) ?? [];
    if (_selected.length < questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer every question before submitting.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final answers = questions.map((q) {
      return {
        'question_id': q['qsid'],
        'selected_option': _selected[q['qsid']],
      };
    }).toList();

    final url = Uri.parse('$_baseUrl/accounts/quiz/${widget.quizId}/submit/');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'student_id': widget.studentId,
          'answers': answers,
        }),
      );

      if (response.statusCode == 201) {
        setState(() {
          _result = jsonDecode(response.body);
          _submitting = false;
        });
      } else {
        setState(() => _submitting = false);
        if (mounted) {
          final body = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(body['error'] ?? 'Submission failed')),
          );
        }
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _result != null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.quizTitle),
          backgroundColor: const Color(0xFF013768),
          foregroundColor: Colors.white,
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchQuiz, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_result != null) {
      final score = _result!['score'];
      final total = _result!['total_questions'];
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
              const SizedBox(height: 20),
              const Text('Quiz Submitted!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                '$score / $total',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    }

    final questions = (_quiz?['questions'] as List?) ?? [];

    if (questions.isEmpty) {
      return const Center(child: Text('This quiz has no questions yet.'));
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: questions.length,
            itemBuilder: (context, index) {
              final q = questions[index];
              final qsid = q['qsid'];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${q['question_text'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _optionTile(qsid, 'A', q['option_a']),
                      _optionTile(qsid, 'B', q['option_b']),
                      _optionTile(qsid, 'C', q['option_c']),
                      _optionTile(qsid, 'D', q['option_d']),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Quiz'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(int qsid, String key, dynamic text) {
    return RadioListTile<String>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('$key. ${text ?? ''}'),
      value: key,
      groupValue: _selected[qsid],
      onChanged: (value) {
        setState(() => _selected[qsid] = value!);
      },
    );
  }
}