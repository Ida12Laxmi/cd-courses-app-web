import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'otp_verification_screen.dart';
import 'student_dashboard.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/api_service.dart';
import 'student_forgot_screen.dart';


class StudentLogin extends StatefulWidget {
  final String? prefillEmail;
  const StudentLogin({super.key, this.prefillEmail});

  @override
  State<StudentLogin> createState() => _StudentLoginState();
}

class _StudentLoginState extends State<StudentLogin> {
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();


  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null) {
      email.text = widget.prefillEmail!;
    }
  }


  bool _isLoading = false;

  Future<void> _loginStudent() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final url = Uri.parse('http://192.168.0.196:8000/accounts/students/login/');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'email': email.text.trim(),
          'password': password.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final student = data['student'];

        final fcmToken = await FirebaseMessaging.instance.getToken();
if (fcmToken != null) {
  try {
    await ApiService.registerDeviceToken(
      role: 'student',
      userId: int.parse(student['sid'].toString()),
      token: fcmToken,
    );
  } catch (e) {
    debugPrint('Failed to register device token: $e');
  }
}

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              //builder: (_) => Placeholder(), // swap with StudentDashboard(...)
               builder: (_) => StudentDashboardScreen(
                 studentId: int.parse(student['sid'].toString()),
                 studentName: student['username'].toString(),
                 teacherId: int.parse(student['tid'].toString()),
                  studentLevel: student['level'].toString(),
              ),
            ),
          );
        }
      } else if (response.statusCode == 403 && data['needs_verification'] == true) {
        // First login, or password was just changed — OTP required
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Login failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          Container(
            color: const Color(0xFF013768),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Click-digitals Courses App',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    margin: const EdgeInsets.all(20),
                    child: Padding(
                      padding: const EdgeInsets.all(30.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: email,
                            decoration: const InputDecoration(labelText: 'Email'),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: password,
                            decoration: const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0B8081),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _isLoading ? null : _loginStudent,
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Login', style: TextStyle(fontSize: 18, color: Colors.white)),
                            ),
                          ),
                          const Divider(height: 30),
                    TextButton(
                      style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const OtpVerificationScreen()),
                        );
                      },
                      child: const Text('Not verified? Go to OTP Verification', style: TextStyle(color: Color(0xFF0B8081))),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                    style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudentForgotPasswordScreen()),
                    ),
                    child: const Text('Forgot password?', style: TextStyle(color: Color(0xFF0B8081))),
                    ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}