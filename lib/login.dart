import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'teacherdashboard.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'teacher_forgot_screen.dart';
import 'otp_verification_screen.dart';
import "config/api_config.dart";
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget{
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const Login(),
    );
  }
}

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login>{
  
  final TextEditingController email=TextEditingController();
  final TextEditingController password=TextEditingController();
  bool _isObscured = true;

  bool _isLoading = false;
  
     Future<void> loginUser() async {
    var url = Uri.parse('${ApiConfig.baseUrl}/login/');

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        url,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'email': email.text,
          'password': password.text,
        }),
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final teacherId = data['admin']['tid'];
        final teacherName=data['admin']['username'];

        final fcmToken = await FirebaseMessaging.instance.getToken();
        if(fcmToken != null) {
           try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/devices/register-token/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'role': 'teacher', 'user_id': teacherId, 'token': fcmToken}),
      );
    } catch (e) {
      debugPrint('Failed to register device token: $e');
    }
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => Teacherdashboard(teacherId: teacherId, teacherName: teacherName),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Login failed: ${response.body}')),
          );
        }
      }
    } catch (e) {
      print('Login request failed: $e');
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
      backgroundColor: const Color(0xFFF8F9FA), // Light grey background

      body: Column(
        children: [
          Container(
            color: const Color(0xFFFFFFFF),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
            /*  children: [
                const Text(
                  'Click-digitals Courses App',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
               
              ],*/
            ),
          ),

          Expanded(
            child: Center(
            child:SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                // Keeps form centered on web
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     Padding(
    padding: const EdgeInsets.only(
      bottom: 10.0,
      top: 10.0,
    ),
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
                      color:Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      margin: const EdgeInsets.all(20),
                      child: Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller:email,
                              decoration: const InputDecoration(labelText: 'Email'),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller:password,
                              //decoration: const InputDecoration(labelText: 'Password',),
                              obscureText: _isObscured,
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
                                  backgroundColor: const Color.fromRGBO(246, 148, 36, 1), // Dark red background
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                 onPressed: () async {
                                      await loginUser();
                                 },
                                child: const Text('Login', style: TextStyle(fontSize: 18, color: Colors.white)),
                              ),
                              
                            ),
                            const SizedBox(height: 20),
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
                              GestureDetector(
                              onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const TeacherForgotPasswordScreen()),
                              ),
                              child: const Text('Forgot password?', style: TextStyle(color: Color(0xFF0B8081))),
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