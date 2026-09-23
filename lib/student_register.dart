import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";
import 'app_logo.dart';

class AddStudentForm extends StatefulWidget {
  final int teacherId;
  // Pass an existing student to edit them instead of creating a new one.
  final dynamic existingStudent;

  const AddStudentForm({super.key, required this.teacherId, this.existingStudent});

  @override
  State<AddStudentForm> createState() => _AddStudentFormState();
}

class _AddStudentFormState extends State<AddStudentForm> {
  static const String _baseUrl = ApiConfig.mediaBaseUrl;
  static const List<String> _levels = ['Basic', 'Intermediate', 'Advance'];

  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController subjectController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController password = TextEditingController();

  String _level = 'Basic';
  bool _isLoading = false;
  bool _isObscured = true;
  bool get _isEditing => widget.existingStudent != null;

  dynamic get _existingId => widget.existingStudent?['sid'];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final s = widget.existingStudent;
      usernameController.text = s['username']?.toString() ?? '';
      emailController.text = s['email']?.toString() ?? '';
      addressController.text = s['address']?.toString() ?? '';
      subjectController.text = s['subject']?.toString() ?? '';
      phoneController.text = s['phone']?.toString() ?? '';
      _level = _levels.contains(s['level']) ? s['level'] : 'Basic';
    }
  }

  Future<void> _submit() async {
    if (usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student name is required')),
      );
      return;
    }

    if (emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email is required (used as a unique identifier)')),
      );
      return;
    }

    if (!_isEditing && password.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password is required')),
      );
      return;
    }

    if (_isEditing && _existingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing student id, cannot update')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final uri = _isEditing
        ? Uri.parse('$_baseUrl/accounts/students/update/$_existingId/')
        : Uri.parse('$_baseUrl/accounts/students/');

    final Map<String, dynamic> payload = {
      'teacher': widget.teacherId,
      'username': usernameController.text.trim(),
      'email': emailController.text.trim(),
      'address': addressController.text.trim(),
      'subject': subjectController.text.trim(),
      'phone': phoneController.text.trim(),
      'level': _level,
    };
    if (!_isEditing) {
      payload['password'] = password.text.trim();
    }
    final body = jsonEncode(payload);

    try {
      final response = _isEditing
          ? await http.patch(uri, headers: {'Content-Type': 'application/json; charset=UTF-8'}, body: body)
          : await http.post(uri, headers: {'Content-Type': 'application/json; charset=UTF-8'}, body: body);

      final success = _isEditing ? response.statusCode == 200 : response.statusCode == 201;

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditing ? 'Student updated!' : 'Student added!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_isEditing ? 'Update' : 'Add'} failed: ${response.body}')),
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
      
       // title: Text(_isEditing ? 'Edit Student' : 'Add Student'),
       title: Row(
  children: [
    const AppLogo(radius: 18),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        _isEditing ? 'Edit Student' : 'Add Student',
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: 'Student Name', border: OutlineInputBorder(), fillColor: Color(0xFFF5F5F5), filled: true),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), fillColor: Color(0xFFF5F5F5), filled: true),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder(), fillColor: Color(0xFFF5F5F5), filled: true),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder(), fillColor: Color(0xFFF5F5F5), filled: true),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder(), fillColor: Color(0xFFF5F5F5), filled: true),
            ),
            const SizedBox(height: 20),
            const Text('Level', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _level,
              decoration: const InputDecoration(border: OutlineInputBorder(), fillColor: Color(0xFFF5F5F5), filled: true),
              items: _levels
                  .map((lvl) => DropdownMenuItem(value: lvl, child: Text(lvl)))
                  .toList(),
              onChanged: (v) => setState(() => _level = v ?? 'Basic'),
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 8),
              TextField(
                controller: password,
                obscureText: _isObscured,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
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
                  fillColor: const Color(0xFFF5F5F5),
                  filled: true,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'You can change this level anytime later from the student list.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(246, 148, 36, 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isEditing ? 'Update Student' : 'Add Student'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}