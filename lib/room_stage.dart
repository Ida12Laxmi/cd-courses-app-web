

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'group_call_service.dart';

class RoomStage extends StatelessWidget {
  final GroupCallService svc;
  const RoomStage({super.key, required this.svc});

  @override
  Widget build(BuildContext context) {
    final remotes = svc.peers.values.toList();

    CallPeer? presenter;
    for (final p in remotes) {
      if (p.sharing) {
        presenter = p;
        break;
      }
    }

    // 1) nobody is presenting -> equal grid
    if (presenter == null && !svc.sharing) {
      final count = remotes.length + 1;
      return GridView.count(
        padding: const EdgeInsets.all(8),
        crossAxisCount: count <= 1 ? 1 : 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: count <= 1 ? 0.75 : 0.8,
        children: [
          _VideoTile(renderer: svc.localRenderer, label: 'You', mirror: true),
          for (final p in remotes) _VideoTile(renderer: p.renderer, label: p.name),
        ],
      );
    }

    // 2) someone is presenting -> big stage + thumbnail strip
    final Widget stage = presenter != null
        ? _Presentation(
            renderer: presenter.renderer,
            title: '${presenter.name} is sharing their screen',
          )
        : _SharingBanner(onStop: () => svc.stopScreenShare());

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: stage,
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            children: [
              SizedBox(
                width: 82,
                child: svc.sharing
                    ? const _MiniNote('You (sharing)')
                    : _VideoTile(renderer: svc.localRenderer, label: 'You', mirror: true),
              ),
              for (final p in remotes)
                if (p.id != presenter?.id)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 82,
                      child: _VideoTile(renderer: p.renderer, label: p.name),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _VideoTile extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final String label;
  final bool mirror;
  const _VideoTile({required this.renderer, required this.label, this.mirror = false});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black87),
          RTCVideoView(
            renderer,
            mirror: mirror,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Positioned(
            left: 6,
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniNote extends StatelessWidget {
  final String text;
  const _MiniNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}

/// Shown to the person who is sharing, instead of a preview of their own
/// screen (which would create the "mirror inside a mirror" effect).
class _SharingBanner extends StatelessWidget {
  final VoidCallback onStop;
  const _SharingBanner({required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10261A),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.screen_share, color: Colors.green, size: 56),
          const SizedBox(height: 12),
          const Text('You are sharing your screen',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Open your PDF or slides now. Your students can see everything on your screen. '
            'Come back here to stop sharing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: onStop,
            icon: const Icon(Icons.stop_screen_share),
            label: const Text('Stop sharing'),
          ),
        ],
      ),
    );
  }
}

/// The big shared screen that viewers look at.
class _Presentation extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final String title;
  const _Presentation({required this.renderer, required this.title});

  void _openFull(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FullScreenViewer(renderer: renderer, title: title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => _openFull(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            RTCVideoView(
              renderer,
              filterQuality: FilterQuality.high,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                tooltip: 'Full screen',
                icon: const Icon(Icons.fullscreen, color: Colors.white, size: 30),
                onPressed: () => _openFull(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen viewer: hides the system bars, pinch to zoom, rotate button.
class FullScreenViewer extends StatefulWidget {
  final RTCVideoRenderer renderer;
  final String title;
  const FullScreenViewer({super.key, required this.renderer, required this.title});

  @override
  State<FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<FullScreenViewer> {
  bool _landscape = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _rotate() {
    setState(() => _landscape = !_landscape);
    SystemChrome.setPreferredOrientations(
      _landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
  child: LayoutBuilder(
    builder: (context, c) => InteractiveViewer(
      minScale: 1,
      maxScale: 6,
      child: SizedBox(
        width: c.maxWidth,
        height: c.maxHeight,
        child: RTCVideoView(
          widget.renderer,
          filterQuality: FilterQuality.high,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        ),
      ),
    ),
  ),
),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      '${widget.title}  •  pinch to zoom',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rotate',
                    icon: const Icon(Icons.screen_rotation, color: Colors.white),
                    onPressed: _rotate,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
