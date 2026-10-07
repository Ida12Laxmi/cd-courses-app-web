import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'student_quiz_take_screen.dart';
import "config/api_config.dart";
import 'app_logo.dart';

class StudentQuizListScreen extends StatefulWidget {
  final int studentId;
  final int teacherId;
  final String studentLevel; // 'Basic' | 'Intermediate' | 'Advance'
  final String studentSubject; // student's registered subject
  final VoidCallback? onBack;
  const StudentQuizListScreen({
    super.key,
    required this.studentId,
    required this.teacherId,
    required this.studentLevel,
    this.studentSubject = '',
    this.onBack,
  });

  @override
  State<StudentQuizListScreen> createState() => _StudentQuizListScreenState();
}

class _StudentQuizListScreenState extends State<StudentQuizListScreen> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  List<dynamic> _quizzes = [];
  // quiz['quid'] -> this student's result map (score/total_questions), if attempted
  final Map<int, dynamic> _myResults = {};
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

    // The backend already filters by teacher, level and subject for this student.
    final url = Uri.parse(
      '$_baseUrl/accounts/quiz/student/${widget.studentId}/',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final all = jsonDecode(response.body) as List;

        // Extra client-side filter by the student's subject (case-insensitive).
        // If no subject was passed in, keep everything the backend returned.
        final mySubject = widget.studentSubject.trim().toLowerCase();
        final quizzes = mySubject.isEmpty
            ? all
            : all
                .where((q) =>
                    (q['subject'] ?? '').toString().trim().toLowerCase() ==
                    mySubject)
                .toList();

        setState(() {
          _quizzes = quizzes;
          _isLoading = false;
        });
        // fire-and-forget: check which of these the student already completed
        for (final quiz in quizzes) {
          _checkMyResult(quiz['quid']);
        }
      } else {
        debugPrint('Quiz list failed: ${response.statusCode} ${response.body}');
        setState(() {
          _error = 'Failed to load quizzes (error ${response.statusCode}). Please try again.';
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

  Future<void> _checkMyResult(int quizId) async {
    final url = Uri.parse('$_baseUrl/accounts/quiz/$quizId/results/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final results = jsonDecode(response.body) as List;
        final mine = results.firstWhere(
          (r) => r['student'] == widget.studentId,
          orElse: () => null,
        );
        if (mine != null && mounted) {
          setState(() => _myResults[quizId] = mine);
        }
      }
    } catch (_) {
      // non-critical — list still works without completion status
    }
  }

  Future<void> _openQuiz(dynamic quiz) async {
    final quizId = quiz['quid'];
    final existingResult = _myResults[quizId];

    if (existingResult != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(quiz['title'] ?? ''),
          content: Text(
            'You already completed this quiz.\n\nScore: ${existingResult['score']} / ${existingResult['total_questions']}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentQuizTakeScreen(
          quizId: quizId,
          quizTitle: quiz['title'] ?? '',
          studentId: widget.studentId,
        ),
      ),
    );
    if (result == true) {
      _checkMyResult(quizId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Text('Quizzes'),
          ],
        ),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
      ),
      body: RefreshIndicator(onRefresh: _fetchQuizzes, child: _buildBody()),
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
          Center(child: Text('No quizzes available for your level and subject yet.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _quizzes.length,
      itemBuilder: (context, index) {
        final quiz = _quizzes[index];
        final quizId = quiz['quid'];
        final questionCount = (quiz['questions'] as List?)?.length ?? 0;
        final String description = (quiz['description'] ?? '').toString();
        final String subject = (quiz['subject'] ?? '').toString();
        final completed = _myResults.containsKey(quizId);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Icon(
              completed ? Icons.check_circle : Icons.quiz,
              color: completed ? Colors.green : null,
            ),
            title: Text(quiz['title'] ?? ''),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subject.isNotEmpty)
                  Text(
                    subject,
                    style: const TextStyle(
                      color: Color(0xFF0B8081),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                Text(description.isEmpty ? 'No description' : description),
                Text('$questionCount question(s)'),
              ],
            ),
            isThreeLine: true,
            trailing: completed
                ? Text(
                    '${_myResults[quizId]['score']}/${_myResults[quizId]['total_questions']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => _openQuiz(quiz),
          ),
        );
      },
    );
  }
}