import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import "config/api_config.dart";
import 'app_logo.dart';

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
  PlatformFile? _screenshot; // kept as bytes so it works on web and mobile

  String? _qrUrl;
  bool _loadingQr = true;
  String? _qrError;

  bool _downloadingQr = false;

  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  @override
  void dispose() {
    _transactionController.dispose();
    super.dispose();
  }

  Future<void> _loadQr() async {
    setState(() {
      _loadingQr = true;
      _qrError = null;
    });
    final url = Uri.parse('$_apiBaseUrl/teacher/payment-qr/${widget.teacherId}/');
    try {
      final res = await http.get(url);
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _qrError = 'Could not load QR code.';
        _loadingQr = false;
      });
    }
  }

  /// Web uploads from bytes have no MIME type unless we set one, and many
  /// backends reject 'application/octet-stream' for image fields.
  MediaType _imageType(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'gif':
        return MediaType('image', 'gif');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  Future<void> _pickScreenshot() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // bytes are required on web
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() => _screenshot = result.files.single);
    }
  }

  Future<void> _downloadQr() async {
    if (_qrUrl == null) return;

    // Web has no gallery: open the QR image in a new tab so it can be saved
    // (right-click -> Save image as...).
    if (kIsWeb) {
      final ok = await launchUrl(
        Uri.parse(_qrUrl!),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the QR image.')),
        );
      }
      return;
    }

    setState(() => _downloadingQr = true);
    try {
      final res = await http.get(Uri.parse(_qrUrl!));
      if (res.statusCode != 200) {
        throw Exception('Server returned ${res.statusCode}');
      }
      final Uint8List bytes = res.bodyBytes;
      await Gal.putImageBytes(
        bytes,
        name: 'payment_qr_${widget.teacherId}_${DateTime.now().millisecondsSinceEpoch}',
        album: 'Payment QR Codes',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR code saved to your gallery.')),
        );
      }
    } on GalException catch (e) {
      if (mounted) {
        final msg = e.type == GalExceptionType.accessDenied
            ? 'Permission denied. Enable photo/storage access in app settings to save the QR.'
            : 'Could not save QR: ${e.type}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save QR: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingQr = false);
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
    if (_screenshot != null && _screenshot!.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'payment_screenshot',
          _screenshot!.bytes!,
          filename: _screenshot!.name,
          contentType: _imageType(_screenshot!.name),
        ),
      );
    }

    try {
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _submitting = false;
          _submitted = true;
        });
      } else {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: ${res.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not connect to server: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            const Expanded(child: Text("Pay Bill", overflow: TextOverflow.ellipsis)),
          ],
        ),
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
                    : Column(
                        children: [
                          Image.network(
                            _qrUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('Could not load QR image.'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: _downloadingQr ? null : _downloadQr,
                            icon: _downloadingQr
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(kIsWeb ? Icons.open_in_new : Icons.download),
                            label: Text(
                              _downloadingQr
                                  ? 'Saving...'
                                  : (kIsWeb ? 'Open QR in new tab' : 'Download QR to Gallery'),
                            ),
                          ),
                        ],
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
                : _screenshot!.name),
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
                      height: 20,
                      width: 20,
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