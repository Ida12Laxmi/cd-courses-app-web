import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'create_quiz_screen.dart';
import 'quiz_questions_screen.dart';
import 'quiz_result_screen.dart';

class QuizListScreen extends StatefulWidget {
  final int teacherId;
  const QuizListScreen({super.key, required this.teacherId});

  @override
  State<QuizListScreen> createState() => _QuizListScreenState();
}

class _QuizListScreenState extends State<QuizListScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000';

  List<dynamic> _quizzes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchQuizzes();
  }

  Future<void> _fetchQuizzes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/accounts/quiz/teacher/${widget.teacherId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _quizzes = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load quizzes: ${response.body}';
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

   Future<void> _editQuiz(dynamic quiz) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateQuizScreen(teacherId: widget.teacherId, existingQuiz: quiz),
      ),
    );
    if (result == true) _fetchQuizzes();
  }

  Future<void> _confirmDeleteQuiz(dynamic quiz) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete quiz'),
        content: Text(
          'Are you sure you want to delete "${quiz['title'] ?? 'this quiz'}"? '
          'All its questions and student results will be deleted too. This cannot be undone.',
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
      await _deleteQuiz(quiz);
    }
  }

  Future<void> _deleteQuiz(dynamic quiz) async {
    final quizId = quiz['quid'];
    if (quizId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing quiz id, cannot delete')),
      );
      return;
    }

    final url = Uri.parse('$_baseUrl/accounts/quiz/delete/$quizId/');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Quiz deleted successfully')),
          );
        }
        _fetchQuizzes();
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
      appBar: AppBar(title: const Text('My Quizzes'),backgroundColor: const Color(0xFF013768),foregroundColor: Colors.white,),
      body: RefreshIndicator(
        onRefresh: _fetchQuizzes,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateQuizScreen(teacherId: widget.teacherId),
            ),
          );
          if (result == true) _fetchQuizzes();
        },
        child: const Icon(Icons.add),
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
            ElevatedButton(onPressed: _fetchQuizzes, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_quizzes.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No quizzes yet. Tap + to create one.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _quizzes.length,
      itemBuilder: (context, index) {
        final quiz = _quizzes[index];
        final questionCount = (quiz['questions'] as List?)?.length ?? 0;
        final String level = quiz['level']?.toString() ?? 'Basic';
        final String description = (quiz['description'] ?? '').toString();

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.quiz),
                title: Text(quiz['title'] ?? ''),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(description.isEmpty ? 'No description' : description),
                    Text('$questionCount question(s)'),
                    const SizedBox(height: 4),
                    _LevelChip(level: level),
                  ],
                ),
                isThreeLine: true,
              ),
              const Divider(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuizQuestionsScreen(
                            quizId: quiz['quid'],
                            quizTitle: quiz['title'],
                          ),
                        ),
                      );
                      if (result == true) _fetchQuizzes();
                    },
                    icon: const Icon(Icons.list_alt, size: 15),
                    label: const Text('Questions'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuizResultsScreen(
                            quizId: quiz['quid'],
                            quizTitle: quiz['title'] ?? '',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bar_chart, size: 15),
                    label: const Text('Results'),
                  ),
                  

                ],
              ),
              const Divider(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _editQuiz(quiz),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmDeleteQuiz(quiz),
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
      child: Text(level, style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
