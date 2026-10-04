import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'content_types.dart';
import 'content_list_screen.dart';
import 'login.dart';
import 'quiz_list_screen.dart';
import 'manage_students_screen.dart';
import 'student_list_screen.dart';
import 'attendance_screen.dart';
import 'change_password_screen.dart';
import 'upload_qr_screen.dart';
import 'notifications_screen.dart';
import 'teacher_content_search_screen.dart';
import 'app_logo.dart';
import 'zoom_call_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'meeting_screens.dart';
import 'group_room_service.dart';

class Teacherdashboard extends StatefulWidget {
  final int teacherId;
  final int? studentId;
  final String? studentName;
  final String? teacherName;

  const Teacherdashboard({
    super.key,
    required this.teacherId,
    this.studentId,
    this.studentName,
    this.teacherName,
  });

  @override
  State<Teacherdashboard> createState() => _TeacherdashboardState();
}

class _TeacherdashboardState extends State<Teacherdashboard> {
  late final PageController _pageController;
  int _currentIndex = 0;

  final ZoomCallService _zoom = ZoomCallService();
  final TextEditingController _meetingNumberCtrl = TextEditingController();
  final TextEditingController _passcodeCtrl = TextEditingController();
  bool _joiningZoom = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _meetingNumberCtrl.dispose();
    _passcodeCtrl.dispose();
    _zoom.dispose();
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
      _logout(context);
    }
  }

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
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
  // Zoom
  // ---------------------------------------------------------------------------

  Future<void> _showJoinClassDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join class'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _meetingNumberCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Meeting number'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passcodeCtrl,
              decoration: const InputDecoration(labelText: 'Passcode'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _joinZoom(
        meetingNumber: _meetingNumberCtrl.text.trim(),
        passcode: _passcodeCtrl.text.trim(),
      );
    }
  }

  Future<void> _joinZoom({
  required String meetingNumber,
  required String passcode,
}) async {
  if (_joiningZoom) return;
  setState(() => _joiningZoom = true);

  final name = (widget.teacherName != null && widget.teacherName!.isNotEmpty)
      ? widget.teacherName!
      : 'Teacher';

  try {
    // Ask for camera + microphone before joining
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
    if (!micGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission denied. You will not be heard in class.'),
        ),
      );
    }

    await _zoom.join(
      meetingNumber: meetingNumber,
      password: passcode,
      // "id|name" so the webhook can match attendance to this teacher
      displayName: '${widget.teacherId}|$name',
      role: 1,
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$e')),
    );
  } finally {
    if (mounted) setState(() => _joiningZoom = false);
  }
}

  // ---------------------------------------------------------------------------
  // Home tab
  // ---------------------------------------------------------------------------

  Widget _buildZoomCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _joiningZoom ? null : _showJoinClassDialog,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _joiningZoom
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Icon(
                    Icons.video_call,
                    size: 40,
                    color: Color(0xFF0B8081),
                  ),
            const SizedBox(height: 10),
            const Text(
              'Join class',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF013768),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupRoomCard() {
  return Card(
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupRoomScreen(
            teacherId: widget.teacherId,
            role: 'teacher',
            userId: widget.teacherId,
          ),
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups, size: 40, color: Color(0xFF0B8081)),
          SizedBox(height: 10),
          Text(
            'Class Room',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF013768),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildMeetingsCard() {
  return Card(
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TeacherMeetingHome(teacherId: widget.teacherId),
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_call, size: 40, color: Color(0xFF0B8081)),
          SizedBox(height: 10),
          Text(
            'Meetings',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF013768),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildHomeTab(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            if (widget.teacherName != null && widget.teacherName!.isNotEmpty)
              Expanded(
                child: Text(
                  'Welcome, ${widget.teacherName}',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        // Only one-off actions live here now — search and logout aren't
        // tab destinations, so they don't belong in the bottom bar.
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TeacherContentSearchScreen(teacherId: widget.teacherId),
              ),
            ),
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
        child: GridView.builder(
          // +2 for the extra "Join class" (Zoom) and "Group Rooms" cards at the end
          itemCount: contentTypes.length + 2,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (context, index) {
            if (index == contentTypes.length) {
              return _buildMeetingsCard();
            }
            if (index == contentTypes.length + 1) {
              return  _buildGroupRoomCard();
            }

            final item = contentTypes[index];
            return Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (item.type == 'messages' ||
                      item.type == 'leave and delays' ||
                      item.type == 'student councelling') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentListScreen(
                          teacherId: widget.teacherId,
                          chatTopic: item.label,
                        ),
                      ),
                    );
                  } else if (item.type == 'attendance') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AttendanceScreen(teacherId: widget.teacherId),
                      ),
                    );
                  } else if (item.type == 'billing') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentListScreen(
                          teacherId: widget.teacherId,
                          billingMode: true,
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContentListScreen(
                          teacherId: widget.teacherId,
                          studentId: widget.studentId ?? 0,
                          studentName: widget.studentName ?? '',
                          contentType: item.type,
                          title: item.label,
                          userRole: 'teacher',
                        ),
                      ),
                    );
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: 40, color: const Color(0xFF0B8081)),
                    const SizedBox(height: 10),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF013768),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _buildHomeTab(context),
      ManageStudentsScreen(teacherId: widget.teacherId),
      QuizListScreen(teacherId: widget.teacherId),
      UploadQrScreen(teacherId: widget.teacherId),
      NotificationsScreen(teacherId: widget.teacherId),
      ChangePasswordScreen(teacherId: widget.teacherId),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          // Not on Home — slide back to Home tab instead of exiting.
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
          showSelectedLabels: false,
          showUnselectedLabels: false,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Students'),
            BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Quizzes'),
            BottomNavigationBarItem(icon: Icon(Icons.qr_code), label: 'QR'),
            BottomNavigationBarItem(
                icon: Icon(Icons.notifications), label: 'Alerts'),
            BottomNavigationBarItem(icon: Icon(Icons.password), label: 'Password'),
          ],
        ),
      ),
    );
  }
}