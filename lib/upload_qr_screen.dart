import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import "config/api_config.dart";

class UploadQrScreen extends StatefulWidget {
  final int teacherId;
  const UploadQrScreen({super.key, required this.teacherId});

  @override
  State<UploadQrScreen> createState() => _UploadQrScreenState();
}

class _UploadQrScreenState extends State<UploadQrScreen> {
  static const String _baseUrl = ApiConfig.baseUrl;
  static const String _mediaBaseUrl = ApiConfig.mediaBaseUrl;

  File? _qrFile;
  String? _existingQrUrl;
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _fetchExistingQr();
  }

  Future<void> _fetchExistingQr() async {
    setState(() => _isLoading = true);
    final url = Uri.parse('$_baseUrl/teacher/payment-qr/${widget.teacherId}/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _existingQrUrl = data['payment_qr_file']);
      } else {
        setState(() => _existingQrUrl = null);
      }
    } catch (e) {
      setState(() => _existingQrUrl = null);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickQr() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => _qrFile = File(result.files.single.path!));
    }
  }

  Future<void> _uploadQr() async {
    if (_qrFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a QR image first')),
      );
      return;
    }

    setState(() => _isUploading = true);
    final url = Uri.parse('$_baseUrl/teacher/payment-qr/upload/${widget.teacherId}/');
    final request = http.MultipartRequest('POST', url);
    request.files.add(await http.MultipartFile.fromPath('payment_qr_file', _qrFile!.path));

    try {
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('QR uploaded successfully!')),
          );
          setState(() => _qrFile = null);
          await _fetchExistingQr(); // refresh to show the newly saved QR
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${response.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment QR Code'),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _existingQrUrl != null
                        ? 'Your current payment QR'
                        : 'No QR uploaded yet',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 260,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _qrFile != null
                        // A new image was just picked — preview it before uploading
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_qrFile!, fit: BoxFit.contain),
                          )
                        : (_existingQrUrl != null
                            // Show the QR already saved on the server
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  '$_mediaBaseUrl$_existingQrUrl',
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const Center(child: CircularProgressIndicator());
                                  },
                                  errorBuilder: (context, error, stack) => const Center(
                                    child: Text('Could not load QR image'),
                                  ),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.qr_code, size: 80, color: Colors.grey),
                              )),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _pickQr,
                    icon: const Icon(Icons.upload),
                    label: Text(_existingQrUrl != null ? 'Select New QR Image' : 'Select QR Image'),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (_isUploading || _qrFile == null) ? null : _uploadQr,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF212529)),
                      child: _isUploading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _existingQrUrl != null ? 'Update QR Code' : 'Save QR Code',
                              style: const TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}