import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'bill_receipt_screen.dart';
import 'payment_proof_screen.dart';

class StudentBillsListScreen extends StatefulWidget {
  final int teacherId;
  final int studentId;
  final String studentName;

  const StudentBillsListScreen({
    super.key,
    required this.teacherId,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentBillsListScreen> createState() => _StudentBillsListScreenState();
}

class _StudentBillsListScreenState extends State<StudentBillsListScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000/accounts';

  List<dynamic> _bills = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchBills();
  }

  Future<void> _fetchBills() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/bills/student/${widget.studentId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _bills = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load bills (${response.statusCode})';
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

  Future<void> _payBill(dynamic bill) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentProofScreen(
          teacherId: widget.teacherId,
          billId: bill['bid'],
          billTitle: bill['title'] ?? '',
          amount: bill['amount'].toString(),
        ),
      ),
    );
    if (result == true) _fetchBills();
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
        title: const Text('Billing'),
      ),
      body: RefreshIndicator(onRefresh: _fetchBills, child: _buildBody()),
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
            ElevatedButton(onPressed: _fetchBills, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_bills.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No bills yet.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _bills.length,
      itemBuilder: (context, index) {
        final bill = _bills[index];
        final status = bill['status'] ?? 'unpaid';
        final isPaid = status == 'paid';
        final isPending = status == 'pending';
        final isRejected = status == 'rejected';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(
                  isPaid ? Icons.check_circle : (isPending ? Icons.hourglass_top : Icons.receipt_long),
                  color: _statusColor(status),
                ),
                title: Text(bill['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Rs. ${bill['amount']}${bill['due_date'] != null ? ' • Due: ${bill['due_date']}' : ''}',
                ),
                trailing: Chip(
                  label: Text(_statusLabel(status), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: _statusColor(status),
                  padding: EdgeInsets.zero,
                ),
                onTap: isPaid
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BillReceiptScreen(bill: bill, studentName: widget.studentName),
                          ),
                        );
                      }
                    : null,
              ),
              if (status == 'unpaid' || isRejected) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _payBill(bill),
                        icon: const Icon(Icons.payment, size: 18, color: Colors.green),
                        label: const Text('Pay Now', style: TextStyle(color: Colors.green)),
                      ),
                    ],
                  ),
                ),
              ] else if (isPending)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    'Submitted — awaiting teacher verification.',
                    style: TextStyle(color: Colors.blueGrey, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}