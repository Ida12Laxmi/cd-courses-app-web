import 'package:flutter/material.dart';
import 'content_types.dart';
import 'content_list_screen.dart';
import 'login.dart';
import 'quiz_list_screen.dart';
import 'manage_students_screen.dart';
import 'student_list_screen.dart';
import 'attendance_screen.dart';

class Teacherdashboard extends StatelessWidget {
  final int teacherId;
  final String? teacherName;
  const Teacherdashboard({super.key, required this.teacherId, this.teacherName});

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
      (route) => false, // removes every previous route from the stack
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF212529),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Manage Students',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageStudentsScreen(teacherId: teacherId),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.quiz),
            tooltip: 'Manage Quizzes',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizListScreen(teacherId: teacherId),
                ),
              );
            },
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
            if (teacherName != null && teacherName!.isNotEmpty) ...[
              Text(
                'Welcome, $teacherName',
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
                        if (item.type == 'messages' || item.type == 'leave and delays' || item.type == 'student councelling') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StudentListScreen(
                                teacherId: teacherId,
                                chatTopic: item.label, // "Messages" or "Leave and Delays"
                              ),
                            ),
                          );
                        } 
                        else if (item.type == 'attendance') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AttendanceScreen(teacherId: teacherId),
                            ),
                          );
                        }
                        else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ContentListScreen(
                                teacherId: teacherId,
                                contentType: item.type,
                                title: item.label,
                              ),
                            ),
                          );
                        }
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.icon, size: 40, color: const Color(0xFF212529)),
                          const SizedBox(height: 10),
                          Text(
                            item.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
}
