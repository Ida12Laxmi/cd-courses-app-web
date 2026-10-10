// Student project: paste this over lib/login.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'otp_verification_screen.dart';
import 'student_dashboard.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/api_service.dart';
import 'student_forgot_screen.dart';
import 'config/api_config.dart';

class StudentLogin extends StatefulWidget {
  final String? prefillEmail;
  const StudentLogin({super.key, this.prefillEmail});

  @override
  State<StudentLogin> createState() => _StudentLoginState();
}

class _StudentLoginState extends State<StudentLogin> {
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();

  bool _isObscured = true;
  bool _isLoading = false;
  bool _checking = true; // true while we look for a saved login

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null) {
      email.text = widget.prefillEmail!;
    }
    _autoLogin();
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  /// If the student logged in before, skip the login screen.
  Future<void> _autoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sid = prefs.getInt('student_id');
      final name = prefs.getString('student_name');
      final tid = prefs.getInt('teacher_id');
      final level = prefs.getString('student_level');

      if (sid != null && name != null && tid != null && level != null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentDashboardScreen(
              studentId: sid,
              studentName: name,
              teacherId: tid,
              studentLevel: level,
            ),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('auto login check failed: $e');
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _loginStudent() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Uses the same server address as the rest of the app (config/api_config.dart)
    final url = Uri.parse('${ApiConfig.baseUrl}/students/login/');
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

        final studentId = int.parse(student['sid'].toString());
        final studentName = student['username'].toString();
        final teacherId = int.parse(student['tid'].toString());
        final studentLevel = student['level'].toString();

        // Remember the login on this device (never the password)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('student_id', studentId);
        await prefs.setString('student_name', studentName);
        await prefs.setInt('teacher_id', teacherId);
        await prefs.setString('student_level', studentLevel);

        // Push notifications: must never block the login (can throw on web)
        try {
          final fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) {
            await ApiService.registerDeviceToken(
              role: 'student',
              userId: studentId,
              token: fcmToken,
            );
          }
        } catch (e) {
          debugPrint('Failed to register device token: $e');
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => StudentDashboardScreen(
                studentId: studentId,
                studentName: studentName,
                teacherId: teacherId,
                studentLevel: studentLevel,
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
              builder: (_) => const OtpVerificationScreen(),
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
    // Avoid flashing the login form while we check for a saved login
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          Container(
            color: const Color(0xFFFFFFFF),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10.0, top: 10.0),
                        child: Transform.scale(
                          scale: 2.25, // increase logo size
                          child: Image.asset(
                            'assets/icon/cd.png',
                            height: 160,
                            width: 220,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Card(
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
                                obscureText: _isObscured,
                                onSubmitted: (_) => _isLoading ? null : _loginStudent(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _isObscured ? Icons.visibility : Icons.visibility_off,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isObscured = !_isObscured;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 30),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color.fromRGBO(246, 148, 36, 1),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: _isLoading ? null : _loginStudent,
                                  child: _isLoading
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : const Text('Login',
                                          style: TextStyle(fontSize: 18, color: Colors.white)),
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
                                child: const Text('Not verified? Go to OTP Verification',
                                    style: TextStyle(color: Color(0xFF0B8081))),
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
                                  MaterialPageRoute(
                                      builder: (_) => const StudentForgotPasswordScreen()),
                                ),
                                child: const Text('Forgot password?',
                                    style: TextStyle(color: Color(0xFF0B8081))),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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