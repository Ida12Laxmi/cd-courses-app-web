import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'services/api_service.dart';

/// Renders content fully in-app — PDF, an uploaded video, or a non-YouTube
/// external video link — with:
///   - Android: FLAG_SECURE set for the duration of this screen, blocking
///     screenshots and screen recording, and blacking out the recent-apps
///     preview.
///   - iOS: screenshots can't be blocked, only detected/logged.
///
/// YouTube links never reach this screen — those are launched directly in
/// the YouTube app from student_dashboard.dart. Everything else (uploaded
/// files, or a non-YouTube hosted video URL) plays through chewie here,
/// whose controls have no download button — unlike a browser tab's native
/// player, there's simply no download affordance exposed at all.
class SecureContentViewerScreen extends StatefulWidget {
  final int contentId;
  final String title;
  final String contentType; // 'notes' | 'video' | 'result' | etc.
  final String? videoLink; // set only for a non-YouTube external video URL, when there's no uploaded file

  const SecureContentViewerScreen({
    super.key,
    required this.contentId,
    required this.title,
    required this.contentType,
    this.videoLink,
  });

  @override
  State<SecureContentViewerScreen> createState() => _SecureContentViewerScreenState();
}

class _SecureContentViewerScreenState extends State<SecureContentViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  File? _tempFile;

  bool get _isExternalVideoLink =>
      widget.contentType == 'video' && widget.videoLink != null && widget.videoLink!.trim().isNotEmpty;

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
      debugPrint('Screenshot detected for content ${widget.contentId}');
    }, (bool isRecording) {
      debugPrint('Screen recording state changed: $isRecording for content ${widget.contentId}');
    });
  }

  Future<void> _load() async {
    try {
      final bytes = await ApiService.streamContentBytes(widget.contentId);
      final dir = await getTemporaryDirectory();
      final ext = widget.contentType == 'video' ? 'mp4' : 'pdf';
      final file = File('${dir.path}/_view_${widget.contentId}.$ext');
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
    if (_bytes == null || _tempFile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.contentType == 'video') {
      return _UploadedVideoPlayer(file: _tempFile!);
    }
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
