import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";
import 'app_logo.dart';

class TeacherForgotPasswordScreen extends StatefulWidget {
  const TeacherForgotPasswordScreen({super.key});

  @override
  State<TeacherForgotPasswordScreen> createState() => _TeacherForgotPasswordScreenState();
}

class _TeacherForgotPasswordScreenState extends State<TeacherForgotPasswordScreen> {
  static const String _baseUrl = ApiConfig.baseUrl;

  final TextEditingController email = TextEditingController();
  final TextEditingController otp = TextEditingController();
  final TextEditingController newPassword = TextEditingController();

  bool _codeSent = false;
  bool _isLoading = false;
  bool _isObscured = true;

  Future<void> _sendCode() async {
    if (email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/forgot-password/'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'email': email.text.trim()}),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'If that email is registered, a code was sent.')),
        );
        if (response.statusCode == 200) {
          setState(() => _codeSent = true);
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

  Future<void> _resetPassword() async {
    if (otp.text.trim().isEmpty || newPassword.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the code and a new password')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/reset-password/'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'email': email.text.trim(),
          'otp': otp.text.trim(),
          'new_password': newPassword.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset — please log in with your new password.')),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Reset failed')),
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
      appBar: AppBar(
       
         title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Text('Forgot Password', style: TextStyle(color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
      ),
      body: Center(
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
                      enabled: !_codeSent,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    if (!_codeSent) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromRGBO(246, 148, 36, 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isLoading ? null : _sendCode,
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Send reset code', style: TextStyle(fontSize: 16, color: Colors.white)),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 20),
                      TextField(
                        controller: otp,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Reset code'),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: newPassword,
                        obscureText: _isObscured,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          suffixIcon: IconButton(
                            icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _isObscured = !_isObscured),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromRGBO(246, 148, 36, 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isLoading ? null : _resetPassword,
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Reset password', style: TextStyle(fontSize: 16, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _isLoading ? null : _sendCode,
                        child: const Text('Resend code'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
