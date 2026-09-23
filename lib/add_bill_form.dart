import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";
import 'app_logo.dart';

class AddBillForm extends StatefulWidget {
  final int teacherId;
  final int studentId;
  final dynamic existingBill; // pass a bill map to edit instead of create

  const AddBillForm({
    super.key,
    required this.teacherId,
    required this.studentId,
    this.existingBill,
  });

  @override
  State<AddBillForm> createState() => _AddBillFormState();
}

class _AddBillFormState extends State<AddBillForm> {
  static const String _baseUrl = ApiConfig.baseUrl;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _dueDateController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  bool _isSubmitting = false;

  bool get _isEditing => widget.existingBill != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final bill = widget.existingBill;
      _titleController.text = bill['title']?.toString() ?? '';
      _amountController.text = bill['amount']?.toString() ?? '';
      _dueDateController.text = bill['due_date']?.toString() ?? '';
      _remarksController.text = bill['remarks']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _dueDateController.text = picked.toIso8601String().split('T')[0];
      });
    }
  }

  Future<void> _submitBill() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final payload = {
      'teacher': widget.teacherId,
      'student': widget.studentId,
      'title': _titleController.text.trim(),
      'amount': double.parse(_amountController.text.trim()),
      'due_date': _dueDateController.text.trim().isNotEmpty
          ? _dueDateController.text.trim()
          : null,
      'remarks': _remarksController.text.trim(),
      if (!_isEditing) 'status': 'unpaid',
    };

    final url = _isEditing
        ? Uri.parse('$_baseUrl/bills/update/${widget.existingBill['bid']}/')
        : Uri.parse('$_baseUrl/bills/create/');

    try {
      final response = _isEditing
          ? await http.patch(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
          : await http.post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditing ? 'Bill updated successfully!' : 'Bill created successfully!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${response.body}')),
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
       // leading: const AppLogo(radius: 18),
       title: Row(
  children: [
    const AppLogo(radius: 18),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        _isEditing ? 'Edit Bill' : 'Add New Bill',
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Bill Title',
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount (Rs.)',
                  prefixText: 'Rs. ',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Please enter amount';
                  if (double.tryParse(val) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dueDateController,
                readOnly: true,
                onTap: _selectDueDate,
                decoration: const InputDecoration(
                  labelText: 'Due Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _remarksController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Remarks / Notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitBill,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(_isEditing ? 'Update Bill' : 'Create Bill', style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}