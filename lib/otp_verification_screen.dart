import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'login.dart';
import "config/api_config.dart"; // adjust if your Login widget lives in a different file
import 'app_logo.dart';

class OtpVerificationScreen extends StatefulWidget {
  // Made optional + still editable on screen — if the previous screen
  // passes an email (e.g. right after registration) it pre-fills the
  // field, but the user can still change it if needed.
  final String? email;
  const OtpVerificationScreen({super.key, this.email});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl; // adjust if your API base URL is different

  late final TextEditingController emailController;
  final TextEditingController otpController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController(text: widget.email ?? '');
  }

  @override
  void dispose() {
    emailController.dispose();
    otpController.dispose();
    super.dispose();
  }

  String get _email => emailController.text.trim();

  Future<void> _verifyOtp() async {
    if (_email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email')),
      );
      return;
    }
    if (otpController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the code')),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/accounts/verify-otp/'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'email': _email, 'otp': otpController.text.trim()}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Verified!')),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const Login()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Verification failed')),
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
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email first')),
      );
      return;
    }

    setState(() => _isResending = true);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/accounts/resend-otp/'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'email': _email}),
      );

      final data = jsonDecode(response.body);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? data['error'] ?? 'Request sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _goToLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF013768);
    const teal = Color(0xFF0F766E);
    const linkPurple = Color(0xFF5B4FCF);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: navy,
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Text('Verify Email', style: TextStyle(color: Colors.white)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
       
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
                    const Icon(Icons.mark_email_read, size: 48, color: navy),
                    const SizedBox(height: 15),
                    const Text(
                      'Enter your email and the verification\ncode sent to it',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, letterSpacing: 8),
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Enter code',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: teal,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isVerifying ? null : _verifyOtp,
                        child: _isVerifying
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Verify', style: TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextButton(
                      onPressed: _isResending ? null : _resendOtp,
                      child: Text(
                        _isResending ? 'Sending...' : "Didn't get a code? Resend",
                        style: const TextStyle(color: linkPurple),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _goToLogin,
                      child: const Text(
                        'Already verified? Go to Login',
                        style: TextStyle(color: linkPurple),
                      ),
                    ),
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