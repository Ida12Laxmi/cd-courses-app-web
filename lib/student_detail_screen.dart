import 'package:flutter/material.dart';
import 'student_assignments_screen.dart';
import 'student_project_screen.dart';
import 'chat_message.dart';

class StudentDetailScreen extends StatelessWidget {
  final int studentId;
  final String studentName;
  final int teacherId;

  const StudentDetailScreen({super.key, required this.studentId, required this.studentName, required this.teacherId,});

  @override
  Widget build(BuildContext context) {
    final options = [
      {'icon': Icons.assignment, 'label': 'Assignments'},
      {'icon': Icons.folder_special, 'label': 'Project'},
      {'icon': Icons.chat_bubble, 'label': 'Chat'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        title: Text(studentName, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          itemCount: options.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (context, index) {
            final item = options[index];
            return Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
  if (index == 0) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentAssignmentsScreen(studentId: studentId, studentName: studentName),
      ),
    );
  } else if (index == 1) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentProjectsScreen(studentId: studentId, studentName: studentName),
      ),
    );
  } else {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          topicTitle: 'Messages',
          currentUserType: 'teacher',
          teacherId: teacherId,
          studentId: studentId,
        ),
      ),
    );
  }
},
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item['icon'] as IconData, size: 40, color: const Color(0xFF0B8081)),
                    const SizedBox(height: 10),
                    Text(
                      item['label'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF013768)),
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
}
