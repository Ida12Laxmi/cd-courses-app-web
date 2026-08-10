import 'package:flutter/material.dart';
import 'content_types.dart';
import 'secure_content_viewer_screen.dart';
import 'submission_screen.dart';
import 'chat_message.dart';
import 'attendance_report_screen.dart';
import 'services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'student_bills_list_screen.dart';

class StudentDashboardScreen extends StatelessWidget {
  final String studentName;
  final int studentId;
  final int teacherId;
  const StudentDashboardScreen({super.key, required this.studentName, required this.studentId, required this.teacherId});

  String? _chatTopicTitle(String type) {
    switch (type) {
      case 'messages':
        return 'Messages';
      case 'leave and delays':
        return 'Leave and Delays';
      case 'student councelling':
        return 'Student Counseling'; // must match teacher side's exact spelling
      default:
        return null;
    }
  }

  void _open(BuildContext context, ContentTypeItem item) {
    final chatTitle = _chatTopicTitle(item.type);

    if (item.type == 'attendance') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => StudentAttendanceReportScreen(studentId: studentId, studentName: studentName),
      ));
    } else if (item.type == 'billing') {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => StudentBillsListScreen(
      teacherId: teacherId,
      studentId: studentId,
      studentName: studentName,
    ),
  ));
} else if (submissionTypes.contains(item.type)) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => SubmissionScreen(studentId: studentId, contentType: item.type, title: item.label),
      ));
    } else if (chatTitle != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          topicTitle: chatTitle,
          currentUserType: 'student',
          teacherId: teacherId,
          studentId: studentId,
        ),
      ));
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _ContentListScreen(studentId: studentId, contentType: item.type, title: item.label),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$studentName — Dashboard')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.9,
        ),
        itemCount: contentTypes.length,
        itemBuilder: (context, i) {
          final item = contentTypes[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _open(context, item),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: 32),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(item.label, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContentListScreen extends StatefulWidget {
  final int studentId;
  final String contentType;
  final String title;
  final bool isBilling;
  const _ContentListScreen({required this.studentId, required this.contentType, required this.title, this.isBilling = false});

  @override
  State<_ContentListScreen> createState() => _ContentListScreenState();
}

class _ContentListScreenState extends State<_ContentListScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.isBilling
        ? ApiService.fetchBills(widget.studentId)
        : ApiService.fetchContent(widget.studentId, widget.contentType);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load: ${snapshot.error}'));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) return const Center(child: Text('Nothing here yet.'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = items[i];
              return ListTile(
                title: Text(item['title'] ?? ''),
                subtitle: item['level'] != null ? Text('Level: ${item['level']}') : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final hasFile = item['file'] != null;
                  final videoLink = item['video_link']?.toString();
                  final isVideo = widget.contentType == 'video';
                  final isYoutube = isVideo && videoLink != null &&
                      (videoLink.contains('youtube.com') || videoLink.contains('youtu.be'));

                  if (isYoutube) {
                    _openYoutube(context, videoLink);
                  } else if (!widget.isBilling && (hasFile || (isVideo && videoLink != null && videoLink.isNotEmpty))) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SecureContentViewerScreen(
                        contentId: item['cid'],
                        title: item['title'] ?? '',
                        contentType: widget.contentType,
                        videoLink: hasFile ? null : videoLink,
                      ),
                    ));
                  } else {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(item['title'] ?? ''),
                        content: Text(item['description'] ?? item['body_text'] ?? 'No details.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openYoutube(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the video link.')),
      );
    }
  }
}