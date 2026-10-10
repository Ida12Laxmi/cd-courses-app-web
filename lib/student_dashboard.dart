import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'content_types.dart';
import 'secure_content_viewer_screen.dart';
import 'submission_screen.dart';
import 'chat_message.dart';
import 'attendance_report_screen.dart';
import 'services/api_service.dart';
import 'meeting_screen.dart'; 
import 'package:url_launcher/url_launcher.dart';
import 'student_bills_list_screen.dart';
import 'student_quiz_list_screen.dart';
import 'student_notification_screen.dart';
import 'student_content_search_screen.dart';
import 'change_password_student.dart';
import 'group_room_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login.dart';
import 'app_logo.dart';


class StudentDashboardScreen extends StatefulWidget {
  final String studentLevel;
  final String studentName;
  final int studentId;
  final int teacherId;
  const StudentDashboardScreen({
    super.key,
    required this.studentName,
    required this.studentId,
    required this.teacherId,
    required this.studentLevel,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      await _logout(context);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('student_id');
    await prefs.remove('student_name');
    await prefs.remove('teacher_id');
    await prefs.remove('student_level');

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const StudentLogin()),
      (route) => false,
    );
  }

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit App'),
        content: const Text('Are you sure you want to exit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      SystemNavigator.pop();
    }
  }

  // ---------------------------------------------------------------------------
  // Zoom — now opens the class list (topic/time/duration + confirm-before-join)
  // instead of a blank manual meeting-number/passcode dialog.
  // ---------------------------------------------------------------------------

  Widget _buildZoomCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentMeetingsScreen(
            studentId: widget.studentId,
            studentName: widget.studentName,
          ),
        ),
      ),
      child: Card(
        elevation: 3,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_call,
              size: 40,
              color: Color(0xFF0B8081),
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'My classes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF013768),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupRoomCard() {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupRoomScreen(
          teacherId: widget.teacherId,
          role: 'student',
          userId: widget.studentId,
        ),
      ),
    ),
    child: Card(
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups, size: 40, color: Color(0xFF0B8081)),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Class Room',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF013768),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

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
        builder: (_) => StudentAttendanceReportScreen(
          studentId: widget.studentId,
          studentName: widget.studentName,
        ),
      ));
    } else if (item.type == 'billing') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => StudentBillsListScreen(
          teacherId: widget.teacherId,
          studentId: widget.studentId,
          studentName: widget.studentName,
        ),
      ));
    } else if (submissionTypes.contains(item.type)) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => SubmissionScreen(
          studentId: widget.studentId,
          contentType: item.type,
          title: item.label,
        ),
      ));
    } else if (chatTitle != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          topicTitle: chatTitle,
          currentUserType: 'student',
          teacherId: widget.teacherId,
          studentId: widget.studentId,
        ),
      ));
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _ContentListScreen(
          studentId: widget.studentId,
          contentType: item.type,
          title: item.label,
        ),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Home tab
  // ---------------------------------------------------------------------------

  Widget _buildHomeTab(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            AppLogo(radius: 18),
            SizedBox(width: 10),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Notifications',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => StudentNotificationsScreen(studentId: widget.studentId),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => StudentContentSearchScreen(studentId: widget.studentId),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.studentName.isNotEmpty) ...[
              Text(
                'Welcome, ${widget.studentName}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF212529),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                // +1 for the extra "My classes" (Zoom) card at the end
                itemCount: contentTypes.length + 2,
                itemBuilder: (context, i) {
                  if (i == contentTypes.length) {
                    return _buildZoomCard();
                  }
                  if (i == contentTypes.length + 1) {
                      return _buildGroupRoomCard();
            }

                  final item = contentTypes[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _open(context, item),
                    child: Card(
                      elevation: 3,
                      shadowColor: Colors.black26,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.icon, size: 40, color: const Color(0xFF0B8081)),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(item.label, textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF013768))),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _buildHomeTab(context),
      StudentQuizListScreen(
        studentId: widget.studentId,
        teacherId: widget.teacherId,
        studentLevel: widget.studentLevel,
        onBack: () => _goToTab(0),
      ),
      ChangePasswordScreen(studentId: widget.studentId, onBack: () => _goToTab(0)),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          _goToTab(0);
        } else {
          _confirmExit(context);
        }
      },
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          // Leaving default ScrollPhysics (not NeverScrollableScrollPhysics)
          // is what enables swipe-to-change-tab, on top of tap-to-slide.
          children: tabs,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _goToTab,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF013768),
          unselectedItemColor: const Color(0xFF0B8081),
          backgroundColor: const Color(0xFFF8F9FA),
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Quizzes'),
            BottomNavigationBarItem(icon: Icon(Icons.password), label: 'Password'),
          ],
        ),
      ),
    );
  }
}

class _ContentListScreen extends StatefulWidget {
  final int studentId;
  final String contentType;
  final String title;
  final bool isBilling;
  const _ContentListScreen({required this.studentId, required this.contentType, required this.title}) : isBilling = false;

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
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const AppLogo(radius: 16),
            const SizedBox(width: 8),
            Text(widget.title),
          ],
        ),
      ),
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