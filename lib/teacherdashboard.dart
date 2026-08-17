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
  int _currentPage = 0;

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

  void _goToPage(int index) {
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

  Widget _buildHomePage(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Manage Students',
            onPressed: () => _goToPage(1),
          ),
          IconButton(
            icon: const Icon(Icons.quiz),
            tooltip: 'Manage Quizzes',
            onPressed: () => _goToPage(2),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'Payment QR Code',
            onPressed: () => _goToPage(3),
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Notifications',
            onPressed: () => _goToPage(4),
          ),
          
          IconButton(
            icon: const Icon(Icons.password),
            tooltip: 'Change Password',
            onPressed: () => _goToPage(5),
          ),
          IconButton(
  icon: const Icon(Icons.search),
  tooltip: 'Search',
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => TeacherContentSearchScreen(teacherId: widget.teacherId),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.teacherName != null && widget.teacherName!.isNotEmpty) ...[
              Text(
                'Welcome, ${widget.teacherName}',
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
                itemCount: contentTypes.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) {
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
                              builder: (_) => AttendanceScreen(teacherId: widget.teacherId),
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildHomePage(context),
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
        if (_currentPage != 0) {
          // Not on Home — swipe/jump back to Home instead of exiting.
          _goToPage(0);
        } else {
          _confirmExit(context);
        }
      },
      child: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentPage = index),
        children: pages,
      ),
    );
  }
}