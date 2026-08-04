import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'add_bill_form.dart';
import 'bill_receipt_screen.dart';
import 'payment_proof_screen.dart';

class StudentBillsScreen extends StatefulWidget {
  final int teacherId;
  final int studentId;
  final String studentName;
  final String userRole; // 'teacher' or 'student'

  const StudentBillsScreen({
    super.key,
    required this.teacherId,
    required this.studentId,
    required this.studentName,
    this.userRole = 'teacher',
  });

  @override
  State<StudentBillsScreen> createState() => _StudentBillsScreenState();
}

class _StudentBillsScreenState extends State<StudentBillsScreen> {
  static const String _baseUrl = 'http://192.168.0.196:8000/accounts';
  static const String _mediaBaseUrl = 'http://192.168.0.196:8000';

  List<dynamic> _bills = [];
  bool _isLoading = true;
  String? _error;

  bool get _isTeacher => widget.userRole == 'teacher';

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

  Future<void> _payViaQr(dynamic bill) async {
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

  Future<void> _markCashPaid(dynamic bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm cash payment'),
        content: Text('Confirm you received Rs. ${bill['amount']} cash for "${bill['title']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    final url = Uri.parse('$_baseUrl/bills/cash-paid/${bill['bid']}/');
    try {
      final response = await http.patch(url);
      if (response.statusCode == 200) {
        _fetchBills();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Marked as paid (cash)!')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${response.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    }
  }

  Future<void> _showPaymentOptions(dynamic bill) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Choose payment method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code, color: Colors.green),
              title: const Text('Pay via QR (eSewa / Khalti)'),
              subtitle: const Text('Scan QR, then submit transaction proof'),
              onTap: () => Navigator.pop(ctx, 'qr'),
            ),
            ListTile(
              leading: const Icon(Icons.money, color: Colors.orange),
              title: const Text('Cash'),
              subtitle: const Text('Recorded directly by teacher'),
              onTap: () => Navigator.pop(ctx, 'cash'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == 'qr') {
      await _payViaQr(bill);
    } else if (choice == 'cash') {
      await _markCashPaid(bill);
    }
  }

  Future<void> _editBill(dynamic bill) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddBillForm(
          teacherId: widget.teacherId,
          studentId: widget.studentId,
          existingBill: bill,
        ),
      ),
    );
    if (result == true) _fetchBills();
  }

  Future<void> _confirmDelete(dynamic bill) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete bill'),
      content: const Text('Are you sure you want to delete this bill?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final url = Uri.parse('$_baseUrl/bills/delete/${bill['bid']}/');
  try {
    final response = await http.delete(url);
    if (response.statusCode == 200 || response.statusCode == 204) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill deleted successfully')),
        );
      }
      _fetchBills();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: ${response.body}')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect to server')),
      );
    }
  }
}

  Future<void> _reviewPayment(dynamic bill) async {
    final screenshot = bill['payment_screenshot'];

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Review Payment — Rs. ${bill['amount']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bill: ${bill['title'] ?? ''}'),
              const SizedBox(height: 6),
              Text('Method: ${(bill['payment_method'] ?? '').toString().toUpperCase()}'),
              Text('Txn Code: ${bill['transaction_code'] ?? '-'}'),
              const SizedBox(height: 12),
              if (screenshot != null && screenshot.toString().isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    '$_mediaBaseUrl$screenshot',
                    height: 240,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox(
                        height: 240,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stack) => const SizedBox(
                      height: 100,
                      child: Center(child: Text('Could not load screenshot')),
                    ),
                  ),
                )
              else
                const Text('No screenshot attached.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _verifyPayment(bill, 'rejected');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _verifyPayment(bill, 'paid');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyPayment(dynamic bill, String newStatus) async {
    final url = Uri.parse('$_baseUrl/bills/verify/${bill['bid']}/');
    try {
      final response = await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': newStatus}),
      );
      if (response.statusCode == 200) {
        _fetchBills();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(newStatus == 'paid' ? 'Payment approved!' : 'Payment rejected')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${response.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        title: Text('${widget.studentName} — Bills', style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(onRefresh: _fetchBills, child: _buildBody()),
      floatingActionButton: _isTeacher
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddBillForm(teacherId: widget.teacherId, studentId: widget.studentId),
                  ),
                );
                if (result == true) _fetchBills();
              },
              child: const Icon(Icons.add),
            )
          : null, // students don't create bills
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
        children: [
          const SizedBox(height: 100),
          Center(
            child: Text(_isTeacher ? 'No bills yet. Tap + to add one.' : 'No bills yet.'),
          ),
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

        Color statusColor = Colors.orange;
        String statusLabel = 'Unpaid';
        if (isPaid) {
          statusColor = Colors.green;
          statusLabel = 'Paid';
        } else if (isPending) {
          statusColor = Colors.blue;
          statusLabel = 'Pending Review';
        } else if (isRejected) {
          statusColor = Colors.red;
          statusLabel = 'Rejected';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(
                  isPaid ? Icons.check_circle : (isPending ? Icons.hourglass_top : Icons.receipt_long),
                  color: statusColor,
                ),
                title: Text(bill['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rs. ${bill['amount']}${bill['due_date'] != null ? ' • Due: ${bill['due_date']}' : ''}',
                      ),
                    ),
                    if (bill['payment_screenshot'] != null &&
                        bill['payment_screenshot'].toString().isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.photo_camera, size: 14, color: Colors.grey),
                      ),
                  ],
                ),
                trailing: Chip(
                  label: Text(statusLabel, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: statusColor,
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
                    : (isPending && _isTeacher ? () => _reviewPayment(bill) : null),
              ),

              // --- UNPAID / REJECTED actions ---
              if (status == 'unpaid' || isRejected) ...[
                const Divider(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _isTeacher
                      ? [
                          TextButton.icon(
                            onPressed: () => _editBill(bill),
                            icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                            label: const Text('Edit', style: TextStyle(color: Colors.blue)),
                          ),
                          TextButton.icon(
                            onPressed: () => _confirmDelete(bill),
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                            label: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ]
                      : [
                          TextButton.icon(
                            onPressed: () => _showPaymentOptions(bill),
                            icon: const Icon(Icons.payment, size: 18, color: Colors.green),
                            label: const Text('Pay / Mark Paid', style: TextStyle(color: Colors.green)),
                          ),
                        ],
                ),
              ]

              // --- PENDING actions ---
              else if (isPending) ...[
                const Divider(height: 1),
                if (_isTeacher)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _reviewPayment(bill),
                        icon: const Icon(Icons.fact_check, size: 18, color: Colors.blue),
                        label: const Text('Review Payment', style: TextStyle(color: Colors.blue)),
                      ),
                    ],
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      'Submitted — awaiting teacher verification.',
                      style: TextStyle(color: Colors.blueGrey, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}