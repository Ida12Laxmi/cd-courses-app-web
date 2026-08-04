import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const String _baseUrl = 'http://192.168.0.196:8000/accounts';
  static const String _mediaBaseUrl = 'http://192.168.0.196:8000';

  final TextEditingController _transactionIdController = TextEditingController();
  String _paymentMethod = 'esewa';
  File? _screenshot;

  String? _qrUrl;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _error;

  bool get _qrIsPdf => (_qrUrl ?? '').toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    _fetchQr();
  }

  Future<void> _fetchQr() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = Uri.parse('$_baseUrl/teacher/payment-qr/${widget.teacherId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _qrUrl = data['payment_qr_file'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'No payment QR has been set up yet. Ask your teacher to upload one first.';
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

  Future<void> _openQrPdf() async {
    if (_qrUrl == null) return;
    final uri = Uri.parse('$_mediaBaseUrl$_qrUrl');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickScreenshot() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => _screenshot = File(result.files.single.path!));
    }
  }

  Future<void> _submitProof() async {
    if (_transactionIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the transaction ID from your payment')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final url = Uri.parse('$_baseUrl/bills/submit-proof/${widget.billId}/');
    final request = http.MultipartRequest('PATCH', url);
    request.fields['transaction_code'] = _transactionIdController.text.trim();
    request.fields['payment_method'] = _paymentMethod;

    if (_screenshot != null) {
      request.files.add(await http.MultipartFile.fromPath('payment_screenshot', _screenshot!.path));
    }

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        setState(() => _submitted = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: ${response.body}')),
        );
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
      appBar: AppBar(title: const Text('Pay Bill'),backgroundColor: const Color(0xFF013768),foregroundColor: Colors.white,),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _submitted
                  ? _buildSubmittedState()
                  : _buildPaymentForm(),
    );
  }

  Widget _buildSubmittedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_top, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('Submitted for verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Your teacher will confirm your payment shortly. '
              'You\'ll see it marked as Paid once verified.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(widget.billTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Rs. ${widget.amount}', style: const TextStyle(fontSize: 24, color: Colors.green)),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Step 1 — Scan and pay', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          if (_qrUrl != null)
            _qrIsPdf
                ? GestureDetector(
                    onTap: _openQrPdf,
                    child: Container(
                      height: 220,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.picture_as_pdf, size: 48, color: Colors.red),
                          SizedBox(height: 8),
                          Text('Tap to open QR code (PDF)'),
                        ],
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.network('$_mediaBaseUrl$_qrUrl', height: 240),
                  ),
          const SizedBox(height: 28),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Step 2 — Submit proof of payment', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(labelText: 'Paid with', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'esewa', child: Text('eSewa')),
              DropdownMenuItem(value: 'khalti', child: Text('Khalti')),
              DropdownMenuItem(value: 'mobile_banking', child: Text('Mobile Banking')),
            ],
            onChanged: (v) => setState(() => _paymentMethod = v ?? 'esewa'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _transactionIdController,
            decoration: const InputDecoration(
              labelText: 'Transaction ID',
              hintText: 'From your payment confirmation',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickScreenshot,
            icon: const Icon(Icons.photo_camera),
            label: Text(_screenshot == null ? 'Attach Payment Screenshot (optional)' : 'Screenshot Attached'),
          ),
          if (_screenshot != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Image.file(_screenshot!, height: 150),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitProof,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF212529)),
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Submit for Verification', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
