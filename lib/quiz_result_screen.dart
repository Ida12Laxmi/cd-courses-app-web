import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";
import 'app_logo.dart';

class QuizResultsScreen extends StatefulWidget {
  final int quizId;
  final String quizTitle;
  const QuizResultsScreen({super.key, required this.quizId, required this.quizTitle});

  @override
  State<QuizResultsScreen> createState() => _QuizResultsScreenState();
}

class _QuizResultsScreenState extends State<QuizResultsScreen> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  List<dynamic> _results = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchResults();
  }

  Future<void> _fetchResults() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/accounts/quiz/${widget.quizId}/results/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _results = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load results: ${response.body}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
       
        //title: Text('${widget.quizTitle} — Results'),
        title: Row(
  children: [
    const AppLogo(radius: 18),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        '${widget.quizTitle} — Results',
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
      ),
      body: RefreshIndicator(onRefresh: _fetchResults, child: _buildBody()),
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
            ElevatedButton(onPressed: _fetchResults, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No submissions yet.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        final score = result['score'];
        final total = result['total_questions'];

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            // NOTE: shows the student's numeric id. If you want the name
            // shown instead, add a nested StudentSerializer to
            // QuizResultSerializer on the backend (student field).
            title:  Text(result['student_name'] ?? 'Student ID: ${result['student']}'),
            subtitle: Text('Submitted: ${result['submitted_at'] ?? ''}'),
            trailing: Text(
              '$score / $total',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        );
      },
    );
  }
}
