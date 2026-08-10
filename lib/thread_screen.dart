import 'package:flutter/material.dart';
import 'services/api_service.dart';

/// Student-side chat screen for a single ongoing conversation with their
/// teacher, scoped by topic ('message' | 'leave' | 'counseling').
class ThreadScreen extends StatefulWidget {
  final int studentId;
  final int teacherId;
  final String category; // used as the conversation topic
  final String title;
  const ThreadScreen({
    super.key,
    required this.studentId,
    required this.teacherId,
    required this.category,
    required this.title,
  });

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  int? _convId;
  List<dynamic> _messages = [];
  final _messageController = TextEditingController();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  Future<void> _loadConversation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getOrCreateConversation(
        teacherId: widget.teacherId,
        studentId: widget.studentId,
        topic: widget.category,
      );
      setState(() {
        _convId = data['conversation']['convid'];
        _messages = data['messages'];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    if (_messageController.text.trim().isEmpty || _convId == null) return;
    final text = _messageController.text.trim();
    _messageController.clear();
    try {
      final sent = await ApiService.sendMessage(
        convId: _convId!,
        senderType: 'student',
        text: text,
      );
      setState(() => _messages.add(sent));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load: $_error'),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadConversation, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('No messages yet. Say hello!'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final isStudent = m['sender_type'] == 'student';
                      return Align(
                        alignment: isStudent ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isStudent ? Colors.blue.shade100 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(m['text'] ?? ''),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}