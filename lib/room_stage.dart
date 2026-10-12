// lib/room_stage.dart  (copy into BOTH the teacher and the student project)
//
// - nobody sharing  -> equal grid of cameras
// - someone sharing -> the shared screen fills the stage, cameras go to a thin strip
// - tap the expand icon (or double-tap the shared screen) for full screen with pinch-zoom
//
// CHANGE vs previous version: _Presentation shows "Waiting for the teacher's
// screen..." while no video frame has arrived yet (width == 0).

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
/// The icon pulses on purpose: screen capture only sends frames when the
/// screen changes, so a moving element lets late joiners get a picture.
class _SharingBanner extends StatefulWidget {
  final VoidCallback onStop;
  const _SharingBanner({required this.onStop});

  @override
  State<_SharingBanner> createState() => _SharingBannerState();
}

class _SharingBannerState extends State<_SharingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

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
          ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.15).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: const Icon(Icons.screen_share, color: Colors.green, size: 56),
          ),
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
            onPressed: widget.onStop,
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
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),
            // waiting hint: shown until a real screen frame arrives. A frame with the
            // camera size (640x480) is the old camera picture, not the shared screen.
            ValueListenableBuilder<RTCVideoValue>(
              valueListenable: renderer,
              builder: (_, v, _) {
                final isCameraFrame = (v.width == 640 && v.height == 480) ||
                    (v.width == 480 && v.height == 640);
                if (v.width != 0 && !isCameraFrame) return const SizedBox.shrink();
                return Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(24),
                  child: const Text(
                    "Waiting for the teacher's screen...\n"
                    '(ask the teacher to scroll or change the page once)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                );
              },
            ),
            Positioned(
              left: 8,
              top: 8,
              right: 56,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // second line = size of the picture that is really arriving
                  child: ValueListenableBuilder<RTCVideoValue>(
                    valueListenable: renderer,
                    builder: (_, v, _) => Text(
                      '$title\n${v.width.toInt()} x ${v.height.toInt()}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
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

  // pinch-zoom state (hand-rolled so the video always gets an exact, bounded size)
  double _scale = 1;
  double _startScale = 1;
  Offset _offset = Offset.zero;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

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
    setState(() {
      _landscape = !_landscape;
      _scale = 1;
      _offset = Offset.zero;
    });
    SystemChrome.setPreferredOrientations(
      _landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final s = (_startScale * d.scale).clamp(1.0, 6.0).toDouble();
    final maxX = size.width * (s - 1) / 2;
    final maxY = size.height * (s - 1) / 2;
    final o = _startOffset + (d.focalPoint - _startFocal);
    setState(() {
      _scale = s;
      _offset = Offset(
        o.dx.clamp(-maxX, maxX).toDouble(),
        o.dy.clamp(-maxY, maxY).toDouble(),
      );
    });
  }

  void _toggleZoom() {
    setState(() {
      _scale = _scale > 1 ? 1 : 2.5;
      _offset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          return Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: (d) => _onScaleUpdate(d, size),
                onDoubleTap: _toggleZoom,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: ClipRect(
                    child: Transform.translate(
                      offset: _offset,
                      child: Transform.scale(
                        scale: _scale,
                        child: RTCVideoView(
                          widget.renderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
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
                            '${widget.title}  |  pinch or double-tap to zoom',
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
              ),
            ],
          );
        },
      ),
    );
  }
}