import 'package:flutter/material.dart';
import 'student_register.dart';
import 'student_list_screen.dart';
import 'app_logo.dart';


class ManageStudentsScreen extends StatelessWidget {
  final int teacherId;
  const ManageStudentsScreen({super.key, required this.teacherId});

  @override
  Widget build(BuildContext context) {
    final options = [
      {'icon': Icons.person_add, 'label': 'Add Student'},
      {'icon': Icons.groups, 'label': 'View Students'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
       backgroundColor: const Color(0xFF013768),
       automaticallyImplyLeading: false,
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Text('Manage Students', style: TextStyle(color: Colors.white)),
          ],
        ),
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
                      MaterialPageRoute(builder: (_) => AddStudentForm(teacherId: teacherId)),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => StudentListScreen(teacherId: teacherId)),
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
