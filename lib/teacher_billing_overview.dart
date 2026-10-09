import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'students_bill_screen.dart';
import 'upload_qr_screen.dart';
import "config/api_config.dart";
import 'app_logo.dart';

class TeacherBillingOverviewScreen extends StatefulWidget {
  final int teacherId;
  const TeacherBillingOverviewScreen({super.key, required this.teacherId});

  @override
  State<TeacherBillingOverviewScreen> createState() => _TeacherBillingOverviewScreenState();
}

class _TeacherBillingOverviewScreenState extends State<TeacherBillingOverviewScreen> {
  static const String _baseUrl = ApiConfig.baseUrl;

  List<dynamic> _bills = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAllBills();
  }

  Future<void> _fetchAllBills() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final url = Uri.parse('$_baseUrl/bills/teacher/${widget.teacherId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _bills = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect to server';
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.blue;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'paid':
        return 'Paid';
      case 'pending':
        return 'Pending Review';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Unpaid';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
       
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        //title: const Text('Billing Overview'),
         title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Text('Billing Overview', style: TextStyle(color: Colors.white)),
          ],
        ),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            color: Colors.white,
            tooltip: 'Manage Payment QR',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UploadQrScreen(teacherId: widget.teacherId),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _fetchAllBills, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchAllBills, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_bills.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No bills created yet.')),
        ],
      );
    }

    // Group by pending-review first, then unpaid, then paid/rejected —
    // so the teacher sees what needs attention at the top.
    final pending = _bills.where((b) => b['status'] == 'pending').toList();
    final unpaid = _bills.where((b) => b['status'] == 'unpaid').toList();
    final others = _bills.where((b) => b['status'] == 'paid' || b['status'] == 'rejected').toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (pending.isNotEmpty) ...[
          _sectionHeader('Awaiting Your Review (${pending.length})'),
          ...pending.map(_buildBillTile),
        ],
        if (unpaid.isNotEmpty) ...[
          _sectionHeader('Unpaid (${unpaid.length})'),
          ...unpaid.map(_buildBillTile),
        ],
        if (others.isNotEmpty) ...[
          _sectionHeader('Paid / Rejected (${others.length})'),
          ...others.map(_buildBillTile),
        ],
      ],
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _buildBillTile(dynamic bill) {
    final status = bill['status'] ?? 'unpaid';
    final studentName = bill['student_name'] ?? 'Student';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(status).withAlpha(40),
          child: Icon(Icons.receipt_long, color: _statusColor(status)),
        ),
        title: Text('$studentName — ${bill['title'] ?? ''}'),
        subtitle: Text('Rs. ${bill['amount']}'),
        trailing: Chip(
          label: Text(_statusLabel(status), style: const TextStyle(color: Colors.white, fontSize: 12)),
          backgroundColor: _statusColor(status),
          padding: EdgeInsets.zero,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentBillsScreen(
                teacherId: widget.teacherId,
                studentId: bill['student'],
                studentName: studentName,
                userRole: 'teacher',
              ),
            ),
          ).then((_) => _fetchAllBills());
        },
      ),
    );
  }
}