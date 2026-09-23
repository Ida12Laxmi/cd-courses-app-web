import 'package:flutter/material.dart';
import "config/api_config.dart";
import 'app_logo.dart';

class BillReceiptScreen extends StatelessWidget {
  final dynamic bill;
  final String studentName;

  const BillReceiptScreen({
    super.key,
    required this.bill,
    required this.studentName,
  });

  static const String _mediaBaseUrl = ApiConfig.mediaBaseUrl;

  void _viewScreenshotFullScreen(BuildContext context, String screenshotPath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.network('$_mediaBaseUrl$screenshotPath'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenshot = bill['payment_screenshot'];
    final hasScreenshot = screenshot != null && screenshot.toString().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
      
         title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Text('Payment Receipt', style: TextStyle(color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 64,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'PAYMENT RECEIVED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  _buildDetailRow('Student Name', studentName),
                  _buildDetailRow('Bill Title', bill['title'] ?? 'N/A'),
                  _buildDetailRow('Amount Paid', 'Rs. ${bill['amount']}'),
                  _buildDetailRow('Payment Method',
                      (bill['payment_method'] ?? 'cash').toString().toUpperCase()),
                  _buildDetailRow('Paid Date', bill['paid_date'] ?? 'N/A'),
                  if (bill['transaction_code'] != null &&
                      bill['transaction_code'].toString().isNotEmpty)
                    _buildDetailRow('Txn Code', bill['transaction_code']),
                  const SizedBox(height: 12),
                  const Divider(),
                  if (hasScreenshot) ...[
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Payment Screenshot',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _viewScreenshotFullScreen(context, screenshot),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          '$_mediaBaseUrl$screenshot',
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(
                              height: 220,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 220,
                            alignment: Alignment.center,
                            color: Colors.grey.shade200,
                            child: const Text('Could not load screenshot'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap to view full size',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Bills'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF212529),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
