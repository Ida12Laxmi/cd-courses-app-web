import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import "config/api_config.dart";
import 'app_logo.dart';

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
  static const String _baseUrl = ApiConfig.mediaBaseUrl;

  // Keep in sync with Student.LEVEL_CHOICES on the backend.
  static const List<String> _levels = ['Basic', 'Intermediate', 'Advance'];

  final TextEditingController titleController = TextEditingController();
  final TextEditingController subjectController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController videoLinkController = TextEditingController();

  String _selectedLevel = 'Basic';
  PlatformFile? _pickedFile; // works on web (bytes) and mobile (path)
  bool _isLoading = false;
  bool _useLink = false;
  String? _errorMessage; // shown inside the dialog

  bool get _isEditing => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final item = widget.existingItem;
      titleController.text = item['title']?.toString() ?? '';
      subjectController.text = item['subject']?.toString() ?? '';
      descriptionController.text = item['description']?.toString() ?? '';

      final existingLevel = item['level']?.toString();
      if (existingLevel != null && _levels.contains(existingLevel)) {
        _selectedLevel = existingLevel;
      }

      final existingVideoLink = item['video_link']?.toString() ?? '';
      if (existingVideoLink.isNotEmpty) {
        _useLink = true;
        videoLinkController.text = existingVideoLink;
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    subjectController.dispose();
    descriptionController.dispose();
    videoLinkController.dispose();
    super.dispose();
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
      allowedExtensions: type == FileType.custom ? ['pdf'] : null,
      withData: kIsWeb, // bytes are required on web (no file paths there)
    );
    if (result != null) {
      setState(() => _pickedFile = result.files.single);
    }
  }

  /// Builds the multipart file part for both web (bytes) and mobile (path).
  Future<http.MultipartFile> _buildFilePart(PlatformFile f) async {
    if (kIsWeb) {
      final bytes = f.bytes;
      if (bytes == null) {
        throw Exception('File data is missing. Please pick the file again.');
      }
      return http.MultipartFile.fromBytes('file', bytes, filename: f.name);
    }
    if (f.path == null) {
      throw Exception('File path is missing. Please pick the file again.');
    }
    return http.MultipartFile.fromPath('file', f.path!, filename: f.name);
  }

  Future<void> _submit() async {
    if (titleController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Title is required');
      return;
    }
    if (_isEditing && _existingId == null) {
      setState(() => _errorMessage = 'Missing item id, cannot update');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uri = _isEditing
        ? Uri.parse('$_baseUrl/accounts/content/update/$_existingId/')
        : Uri.parse('$_baseUrl/accounts/content/upload/');

    final request = http.MultipartRequest(_isEditing ? 'PATCH' : 'POST', uri);

    request.fields['teacher'] = widget.teacherId.toString();
    request.fields['content_type'] = widget.contentType;
    request.fields['title'] = titleController.text;
    request.fields['description'] = descriptionController.text;
    request.fields['subject'] = subjectController.text;
    request.fields['level'] = _selectedLevel;

    try {
      if (widget.contentType == 'video' && _useLink) {
        request.fields['video_link'] = videoLinkController.text;
      } else if (_pickedFile != null) {
        request.files.add(await _buildFilePart(_pickedFile!));
      }
      // If editing and no new file/link was picked, we simply don't send
      // 'file' or 'video_link' — the backend's partial update leaves the
      // existing one untouched.

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Status: ${response.statusCode}');
      debugPrint('Body: ${response.body}');

      final success = _isEditing ? response.statusCode == 200 : response.statusCode == 201;

      if (success) {
        if (mounted) {
          // Shown on the list screen once the dialog closes.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditing ? 'Updated successfully!' : 'Uploaded successfully!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          setState(() => _errorMessage =
              '${_isEditing ? 'Update' : 'Upload'} failed: ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('Submit failed: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Could not upload: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isVideo = widget.contentType == 'video';

    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const AppLogo(radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_isEditing ? 'Edit' : 'Add'} ${widget.title}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF013768),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF013768)),
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 10),

            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              initialValue: _selectedLevel,
              decoration: const InputDecoration(labelText: 'Level', border: OutlineInputBorder()),
              items: _levels
                  .map((level) => DropdownMenuItem(value: level, child: Text(level)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedLevel = value);
              },
            ),
            const SizedBox(height: 15),
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),

            if (isVideo)
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('YouTube Link', style: TextStyle(fontSize: 13)),
                      value: true,
                      groupValue: _useLink,
                      onChanged: (v) => setState(() => _useLink = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Upload MP4', style: TextStyle(fontSize: 13)),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.attach_file),
                    label: Text(_pickedFile == null ? 'Choose File' : 'File selected'),
                  ),
                  if (_pickedFile != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_pickedFile!.name),
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
            const SizedBox(height: 24),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            SizedBox(
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