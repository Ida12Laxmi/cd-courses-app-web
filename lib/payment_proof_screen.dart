import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import "config/api_config.dart";

/// Student-side "Pay Bill" flow:
///   Step 1 — shows the teacher's payment QR code (eSewa/Khalti/mobile
///     banking — whatever they've uploaded via UploadQrScreen).
///   Step 2 — student enters which method they paid with, a transaction
///     ID, and optionally attaches a screenshot, then submits for the
///     teacher to verify. Bill status moves to 'pending' server-side.
class PaymentProofScreen extends StatefulWidget {
  final int teacherId;
  final int billId;
  final String billTitle;
  final String amount;

  const PaymentProofScreen({
    super.key,
    required this.teacherId,
    required this.billId,
    required this.billTitle,
    required this.amount,
  });

  @override
  State<PaymentProofScreen> createState() => _PaymentProofScreenState();
}

class _PaymentProofScreenState extends State<PaymentProofScreen> {
  static const String _apiBaseUrl = ApiConfig.baseUrl;
  static const String _mediaBaseUrl = ApiConfig.mediaBaseUrl;

  final _transactionController = TextEditingController();
  String _paymentMethod = 'esewa';
  File? _screenshot;

  String? _qrUrl;
  bool _loadingQr = true;
  String? _qrError;

  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    setState(() {
      _loadingQr = true;
      _qrError = null;
    });
    final url = Uri.parse('$_apiBaseUrl/teacher/payment-qr/${widget.teacherId}/');
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final path = data['payment_qr_file']?.toString();
        setState(() {
          _qrUrl = path == null
              ? null
              : (path.startsWith('http') ? path : '$_mediaBaseUrl$path');
          _loadingQr = false;
        });
      } else {
        setState(() {
          _qrError = 'Your teacher has not uploaded a payment QR yet.';
          _loadingQr = false;
        });
      }
    } catch (e) {
      setState(() {
        _qrError = 'Could not load QR code.';
        _loadingQr = false;
      });
    }
  }

  Future<void> _pickScreenshot() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => _screenshot = File(result.files.single.path!));
    }
  }

  Future<void> _submit() async {
    if (_transactionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the transaction ID before submitting.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final url = Uri.parse('$_apiBaseUrl/bills/submit-proof/${widget.billId}/');
    final request = http.MultipartRequest('PATCH', url);
    request.fields['payment_method'] = _paymentMethod;
    request.fields['transaction_code'] = _transactionController.text.trim();
    if (_screenshot != null) {
      request.files.add(await http.MultipartFile.fromPath('payment_screenshot', _screenshot!.path));
    }

    try {
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) {
        setState(() {
          _submitting = false;
          _submitted = true;
        });
      } else {
        setState(() => _submitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Submission failed: ${res.body}')),
          );
        }
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect to server: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Pay Bill'),
        backgroundColor: const Color(0xFFEDE7F6),
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _submitted ? _buildConfirmation() : _buildForm(),
    );
  }

  Widget _buildConfirmation() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 56, color: Colors.orange),
            const SizedBox(height: 20),
            const Text(
              'Submitted for verification',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Your teacher will confirm your payment shortly. You'll see it marked as Paid once verified.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.billTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Rs. ${widget.amount}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 24),
          const Text('Step 1 — Scan and pay', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _loadingQr
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _qrError != null
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_qrError!, textAlign: TextAlign.center),
                      )
                    : Image.network(
                        _qrUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('Could not load QR image.'),
                            ),
                      ),
          ),
          const SizedBox(height: 24),
          const Text('Step 2 — Submit proof of payment', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Paid with',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: const [
              DropdownMenuItem(value: 'esewa', child: Text('eSewa')),
              DropdownMenuItem(value: 'khalti', child: Text('Khalti')),
              DropdownMenuItem(value: 'mobile_banking', child: Text('Mobile Banking')),
            ],
            onChanged: (v) => setState(() => _paymentMethod = v ?? 'esewa'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _transactionController,
            decoration: const InputDecoration(
              labelText: 'Transaction ID',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickScreenshot,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_screenshot == null
                ? 'Attach Payment Screenshot (optional)'
                : _screenshot!.path.split('/').last),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit for Verification', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
