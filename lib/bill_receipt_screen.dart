import 'package:flutter/material.dart';
import "config/api_config.dart";
import 'app_logo.dart';

/// Read-only receipt for a bill that's already marked 'paid'. Shown when
/// tapping a paid bill in StudentBillsScreen, for either role.
class BillReceiptScreen extends StatelessWidget {
  final dynamic bill;
  final String studentName;

  const BillReceiptScreen({super.key, required this.bill, required this.studentName});

  static const String _mediaBaseUrl = ApiConfig.mediaBaseUrl;

  @override
  Widget build(BuildContext context) {
    final screenshot = bill['payment_screenshot'];
    final hasScreenshot = screenshot != null && screenshot.toString().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
         automaticallyImplyLeading: false,
        //title: const Text('Receipt'),
        title: Row(
          children: [
            const AppLogo(radius: 16),
            const SizedBox(width: 8),
            const Text('Receipt'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 56),
                  const SizedBox(height: 10),
                  const Text('Payment Confirmed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Student', studentName),
                    _row('Bill', bill['title'] ?? ''),
                    _row('Amount', 'Rs. ${bill['amount']}'),
                    if (bill['due_date'] != null) _row('Due date', '${bill['due_date']}'),
                    if (bill['paid_date'] != null) _row('Paid date', '${bill['paid_date']}'),
                    _row('Method', (bill['payment_method'] ?? '').toString().toUpperCase()),
                    if (bill['transaction_code'] != null && bill['transaction_code'].toString().isNotEmpty)
                      _row('Transaction ID', bill['transaction_code']),
                    if (bill['remarks'] != null && bill['remarks'].toString().isNotEmpty)
                      _row('Remarks', bill['remarks']),
                  ],
                ),
              ),
            ),
            if (hasScreenshot) ...[
              const SizedBox(height: 16),
              const Text('Payment Screenshot', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  '$_mediaBaseUrl$screenshot',
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 100,
                    child: Center(child: Text('Could not load screenshot')),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
