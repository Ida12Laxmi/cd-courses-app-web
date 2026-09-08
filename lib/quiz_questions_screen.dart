import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'add_question_form.dart';
import "config/api_config.dart";

class QuizQuestionsScreen extends StatefulWidget {
  final int quizId;
  final String? quizTitle;
  const QuizQuestionsScreen({super.key, required this.quizId, this.quizTitle});

  @override
  State<QuizQuestionsScreen> createState() => _QuizQuestionsScreenState();
}

class _QuizQuestionsScreenState extends State<QuizQuestionsScreen> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  Map<String, dynamic>? _quiz;
  bool _isLoading = true;
  String? _error;
  bool _questionsChanged = false;

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

    final url = Uri.parse('$_baseUrl/accounts/quiz/${widget.quizId}/');
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

  Future<void> _editQuestion(dynamic question) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddQuestionForm(quizId: widget.quizId, existingQuestion: question),
      ),
    );
    if (result == true) {
      _questionsChanged = true;
      _fetchQuiz();
    }
  }

  Future<void> _confirmDeleteQuestion(dynamic question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete question'),
        content: const Text('Are you sure you want to delete this question? This cannot be undone.'),
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
      await _deleteQuestion(question);
    }
  }

  Future<void> _deleteQuestion(dynamic question) async {
    final questionId = question['qsid']; // adjust if your Question pk field is named differently
    if (questionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing question id, cannot delete')),
      );
      return;
    }

    final url = Uri.parse('$_baseUrl/accounts/quiz/question/delete/$questionId/');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Question deleted successfully')),
          );
        }
        _questionsChanged = true;
        _fetchQuiz();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _questionsChanged);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.quizTitle ?? _quiz?['title'] ?? 'Quiz Questions'),
          backgroundColor: const Color(0xFF013768),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _questionsChanged),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: RefreshIndicator(onRefresh: _fetchQuiz, child: _buildBody()),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final added = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddQuestionForm(quizId: widget.quizId)),
            );
            if (added == true) {
              _questionsChanged = true;
              _fetchQuiz();
            }
          },
          child: const Icon(Icons.add),
        ),
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

    final questions = (_quiz?['questions'] as List?) ?? [];

    if (questions.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No questions yet. Tap + to add one.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final q = questions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}. ${q['question_text'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _optionRow('A', q['option_a'], q['correct_option']),
                    _optionRow('B', q['option_b'], q['correct_option']),
                    _optionRow('C', q['option_c'], q['correct_option']),
                    _optionRow('D', q['option_d'], q['correct_option']),
                  ],
                ),
              ),
              const Divider(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _editQuestion(q),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmDeleteQuestion(q),
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

  Widget _optionRow(String key, dynamic text, dynamic correct) {
    final isCorrect = key == correct;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: isCorrect ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$key. ${text ?? ''}',
              style: TextStyle(
                color: isCorrect ? Colors.green : null,
                fontWeight: isCorrect ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
