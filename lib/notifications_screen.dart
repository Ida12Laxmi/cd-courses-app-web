import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";
import 'app_logo.dart';

class NotificationsScreen extends StatefulWidget {
  final int teacherId;
  const NotificationsScreen({super.key, required this.teacherId});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const String _baseUrl = ApiConfig.baseUrl;

  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final url = Uri.parse('$_baseUrl/notifications/teacher/${widget.teacherId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _notifications = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load (${response.statusCode})';
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

  Future<void> _markRead(dynamic notif) async {
    if (notif['is_read'] == true) return;
    final url = Uri.parse('$_baseUrl/notifications/read/${notif['nid']}/');
    try {
      await http.patch(url);
      setState(() => notif['is_read'] = true);
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    final url = Uri.parse('$_baseUrl/notifications/read-all/${widget.teacherId}/');
    try {
      await http.patch(url);
      _fetchNotifications();
    } catch (_) {}
  }

  Future<void> _deleteNotification(dynamic notif) async {
    final url = Uri.parse('$_baseUrl/notifications/delete/${notif['nid']}/');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200 || response.statusCode == 204) {
        _fetchNotifications();
      }
    } catch (_) {}
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'assignment_submitted':
        return Icons.assignment_turned_in;
      case 'project_submitted':
        return Icons.folder_copy;
      case 'password_changed':
        return Icons.lock_reset;
      case 'leave_delay':
        return Icons.event_busy;
      case 'message':
        return Icons.chat_bubble;
      case 'payment_submitted':
        return Icons.payment;
      default:
        return Icons.notifications;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'assignment_submitted':
      case 'project_submitted':
        return Colors.orange;
      case 'password_changed':
        return Colors.purple;
      case 'leave_delay':
        return Colors.red;
      case 'message':
        return Colors.blue;
      case 'payment_submitted':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Text('Notifications', style: TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          if (_notifications.any((n) => n['is_read'] == false))
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _fetchNotifications, child: _buildBody()),
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
            ElevatedButton(onPressed: _fetchNotifications, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No notifications yet.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final notif = _notifications[index];
        final isRead = notif['is_read'] == true;
        final type = notif['notif_type'] ?? '';
        final studentName = notif['student_name'] ?? '';

        return Dismissible(
          key: Key(notif['nid'].toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _deleteNotification(notif),
          child: Card(
            color: isRead ? Colors.white : Colors.blue.shade50,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _colorFor(type).withAlpha(40),
                child: Icon(_iconFor(type), color: _colorFor(type)),
              ),
              title: Text(
                notif['title'] ?? '',
                style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
              ),
                 subtitle: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (studentName != null && studentName.toString().isNotEmpty)
                  Text(
                    studentName,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                if (notif['message'] != null && notif['message'].toString().isNotEmpty)
                  Text(notif['message']),
                Text(
                  _timeAgo(notif['created_at']),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            isThreeLine: true,
              trailing: isRead ? null : const CircleAvatar(radius: 5, backgroundColor: Colors.blue),
              onTap: () => _markRead(notif),
            ),
          ),
        );
      },
    );
  }
}