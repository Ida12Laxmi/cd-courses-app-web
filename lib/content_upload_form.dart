import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class ContentUploadForm extends StatefulWidget {
  final int teacherId;
  final String contentType;
  final String title;
  // Pass an existing item to edit it instead of creating a new one.
  final dynamic existingItem;

  const ContentUploadForm({
    super.key,
    required this.teacherId,
    required this.contentType,
    required this.title,
    this.existingItem,
  });

  @override
  State<ContentUploadForm> createState() => _ContentUploadFormState();
}

class _ContentUploadFormState extends State<ContentUploadForm> {
  static const String _baseUrl = 'http://192.168.0.196:8000';

  final TextEditingController titleController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController videoLinkController = TextEditingController();

  File? _pickedFile;
  bool _isLoading = false;
  bool _useLink = false;

  bool get _isEditing => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final item = widget.existingItem;
      titleController.text = item['title']?.toString() ?? '';
      descriptionController.text = item['description']?.toString() ?? '';

      final existingVideoLink = item['video_link']?.toString() ?? '';
      if (existingVideoLink.isNotEmpty) {
        _useLink = true;
        videoLinkController.text = existingVideoLink;
      }
    }
  }

  // Adjust this if your CourseContent primary key field is named
  // something other than 'id' (e.g. 'cid').
  dynamic get _existingId =>
      widget.existingItem?['id'] ?? widget.existingItem?['cid'];

  String? get _existingFileName {
    final file = widget.existingItem?['file'];
    if (file == null || file.toString().isEmpty) return null;
    return file.toString().split('/').last;
  }

  Future<void> _pickFile() async {
    FileType type = widget.contentType == 'video' ? FileType.video : FileType.custom;
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: type == FileType.custom ? ['pdf', 'ppt', 'pptx'] : null,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pickedFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> _submit() async {
    if (titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }
    if (descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Package is required')),
      );
      return;
    }
    if (_isEditing && _existingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing item id, cannot update')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final uri = _isEditing
        ? Uri.parse('$_baseUrl/accounts/content/update/$_existingId/')
        : Uri.parse('$_baseUrl/accounts/content/upload/');

    final request = http.MultipartRequest(_isEditing ? 'PATCH' : 'POST', uri);

    request.fields['teacher'] = widget.teacherId.toString();
    request.fields['content_type'] = widget.contentType;
    request.fields['title'] = titleController.text;
    request.fields['description'] = descriptionController.text;

    if (widget.contentType == 'video' && _useLink) {
      request.fields['video_link'] = videoLinkController.text;
    } else if (_pickedFile != null) {
      request.files.add(await http.MultipartFile.fromPath('file', _pickedFile!.path));
    }
    // If editing and no new file/link was picked, we simply don't send
    // 'file' or 'video_link' — the backend's partial update leaves the
    // existing one untouched.

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      final success = _isEditing ? response.statusCode == 200 : response.statusCode == 201;

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditing ? 'Updated successfully!' : 'Uploaded successfully!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_isEditing ? 'Update' : 'Upload'} failed: ${response.body}')),
          );
        }
      }
    } catch (e) {
      print('Submit failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isVideo = widget.contentType == 'video';

    return Scaffold(
      appBar: AppBar(title: Text('${_isEditing ? 'Edit' : 'Add'} ${widget.title}'),backgroundColor: const Color(0xFF013768),foregroundColor: Colors.white,),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            TextField(
              controller: titleController,
              
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Package', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            if (isVideo)
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool>(
                      title: const Text('YouTube Link'),
                      value: true,
                      groupValue: _useLink,
                      onChanged: (v) => setState(() => _useLink = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      title: const Text('Upload MP4'),
                      value: false,
                      groupValue: _useLink,
                      onChanged: (v) => setState(() => _useLink = v!),
                    ),
                  ),
                ],
              ),
            if (isVideo && _useLink)
              TextField(
                controller: videoLinkController,
                decoration: const InputDecoration(labelText: 'YouTube URL', border: OutlineInputBorder()),
              )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.attach_file),
                      label: Text(_pickedFile == null ? 'Choose File' : 'File selected'),
                    ),
                  ),
                  if (_pickedFile != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_pickedFile!.path.split('/').last),
                    )
                  else if (_isEditing && _existingFileName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Current file: $_existingFileName (choose a new one to replace it)',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isEditing ? 'Update' : 'Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}