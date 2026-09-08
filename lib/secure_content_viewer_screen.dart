import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'services/api_service.dart';

/// Renders content fully in-app — PDF, image, an uploaded video, or a
/// non-YouTube external video link — with:
///   - Android: FLAG_SECURE set for the duration of this screen, blocking
///     screenshots and screen recording, and blacking out the recent-apps
///     preview.
///   - iOS: screenshots can't be blocked, only detected/logged.
///
/// Two ways to open this screen:
///   1. SecureContentViewerScreen(...) — content-library flow. Fetches
///      bytes via ApiService.streamContentBytes(contentId), type decided
///      by `contentType`. Unchanged from before.
///   2. SecureContentViewerScreen.forAttachment(...) — chat flow. Fetches
///      bytes directly from a URL via http, type decided by the file
///      extension in `fileName`. Use this for chat message attachments.
///
/// YouTube links never reach this screen — those are launched directly in
/// the YouTube app from student_dashboard.dart. Everything else (uploaded
/// files, or a non-YouTube hosted video URL, or a chat attachment) plays
/// or renders here, whose controls have no download button — unlike a
/// browser tab's native player, there's simply no download affordance
/// exposed at all.
class SecureContentViewerScreen extends StatefulWidget {
  final int? contentId;
  final String title;
  final String contentType; // 'notes' | 'video' | 'result' | 'attachment'
  final String? videoLink; // non-YouTube external video URL (library flow)
  final String? attachmentUrl; // direct file URL (chat flow)
  final String? fileName; // used to detect type in chat flow

  const SecureContentViewerScreen({
    super.key,
    required this.contentId,
    required this.title,
    required this.contentType,
    this.videoLink,
  })  : attachmentUrl = null,
        fileName = null;

  /// Use this for chat message attachments — no contentId, just a URL
  /// and a filename. Type is auto-detected from the file extension.
  const SecureContentViewerScreen.forAttachment({
    super.key,
    required String url,
    required String fileName,
    String? title,
  })  : contentId = null,
        title = title ?? fileName,
        contentType = 'attachment',
        videoLink = null,
        attachmentUrl = url,
        fileName = fileName;

  @override
  State<SecureContentViewerScreen> createState() => _SecureContentViewerScreenState();
}

enum _RenderKind { pdf, video, image, unsupported }

class _SecureContentViewerScreenState extends State<SecureContentViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  File? _tempFile;

  bool get _isAttachmentMode => widget.attachmentUrl != null;

  bool get _isExternalVideoLink =>
      !_isAttachmentMode &&
      widget.contentType == 'video' &&
      widget.videoLink != null &&
      widget.videoLink!.trim().isNotEmpty;

  /// What to render. Library flow trusts `contentType`. Attachment flow
  /// detects from the file extension since attachments can be any type.
  _RenderKind get _renderKind {
    if (_isAttachmentMode) {
      final ext = (widget.fileName ?? '').toLowerCase();
      if (ext.endsWith('.pdf')) return _RenderKind.pdf;
      if (ext.endsWith('.mp4') ||
          ext.endsWith('.mov') ||
          ext.endsWith('.m4v') ||
          ext.endsWith('.webm')) {
        return _RenderKind.video;
      }
      if (ext.endsWith('.png') ||
          ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.gif') ||
          ext.endsWith('.webp')) {
        return _RenderKind.image;
      }
      return _RenderKind.unsupported;
    }
    // Library flow: only 'video' vs everything else (PDF), as before.
    return widget.contentType == 'video' ? _RenderKind.video : _RenderKind.pdf;
  }

  @override
  void initState() {
    super.initState();
    _enableProtection();
    if (!_isExternalVideoLink) {
      _load();
    }
  }

  Future<void> _enableProtection() async {
    await ScreenProtector.preventScreenshotOn();
    ScreenProtector.addListener(() {
      debugPrint('Screenshot detected for content ${widget.contentId ?? widget.attachmentUrl}');
    }, (bool isRecording) {
      debugPrint(
          'Screen recording state changed: $isRecording for content ${widget.contentId ?? widget.attachmentUrl}');
    });
  }

  Future<void> _load() async {
    try {
      final Uint8List bytes;
      if (_isAttachmentMode) {
        final response = await http.get(Uri.parse(widget.attachmentUrl!));
        if (response.statusCode != 200) {
          throw Exception('Server returned ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      } else {
        bytes = await ApiService.streamContentBytes(widget.contentId!);
      }

      // Images are shown straight from memory — no temp file needed.
      if (_renderKind == _RenderKind.image) {
        setState(() => _bytes = bytes);
        return;
      }

      final dir = await getTemporaryDirectory();
      final ext = _renderKind == _RenderKind.video ? 'mp4' : 'pdf';
      final safeId = widget.contentId?.toString() ??
          (widget.fileName ?? 'attachment').replaceAll(RegExp(r'[^\w.\-]'), '_');
      final file = File('${dir.path}/_view_$safeId.$ext');
      await file.writeAsBytes(bytes, flush: true);
      _tempFile = file;
      setState(() => _bytes = bytes);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    ScreenProtector.preventScreenshotOff();
    ScreenProtector.removeListener();
    _tempFile?.delete().catchError((_) => _tempFile!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isExternalVideoLink) {
      return _NetworkVideoPlayer(url: widget.videoLink!);
    }
    if (_error != null) {
      return Center(child: Text('Could not load: $_error'));
    }
    if (_bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_renderKind) {
      case _RenderKind.image:
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Center(child: Image.memory(_bytes!)),
        );
      case _RenderKind.video:
        if (_tempFile == null) return const Center(child: CircularProgressIndicator());
        return _UploadedVideoPlayer(file: _tempFile!);
      case _RenderKind.pdf:
        if (_tempFile == null) return const Center(child: CircularProgressIndicator());
        return PDFView(
          filePath: _tempFile!.path,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          onError: (error) {
            setState(() => _error = error.toString());
          },
          onRender: (pages) {
            debugPrint('PDF rendered: $pages pages');
          },
        );
      case _RenderKind.unsupported:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Preview not available for this file type yet.\n(${widget.fileName ?? widget.title})',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// Plays an uploaded video file (already downloaded to the app's private
/// temp dir by the parent screen) using video_player + chewie.
class _UploadedVideoPlayer extends StatefulWidget {
  final File file;
  const _UploadedVideoPlayer({required this.file});

  @override
  State<_UploadedVideoPlayer> createState() => _UploadedVideoPlayerState();
}

class _UploadedVideoPlayerState extends State<_UploadedVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.file(widget.file);
      await controller.initialize();
      setState(() {
        _videoController = controller;
        _chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: false,
        );
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('Could not play video: $_error'));
    }
    if (_chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Chewie(controller: _chewieController!);
  }
}

/// Plays a non-YouTube external video URL directly over the network (no
/// download to disk here) using video_player + chewie. Same reasoning as
/// above: chewie's controls expose no download option.
class _NetworkVideoPlayer extends StatefulWidget {
  final String url;
  const _NetworkVideoPlayer({required this.url});

  @override
  State<_NetworkVideoPlayer> createState() => _NetworkVideoPlayerState();
}

class _NetworkVideoPlayerState extends State<_NetworkVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      setState(() {
        _videoController = controller;
        _chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: false,
        );
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('Could not play video: $_error'));
    }
    if (_chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Chewie(controller: _chewieController!);
  }
}
