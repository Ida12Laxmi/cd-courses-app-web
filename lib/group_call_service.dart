// lib/group_call_service.dart  (copy into BOTH the teacher and the student project)
//
// pubspec.yaml:
//   flutter_webrtc, web_socket_channel, permission_handler, flutter_background

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class CallPeer {
  final String id;
  String name;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  final List<RTCIceCandidate> pendingIce = [];
  bool remoteSet = false;
  bool sharing = false;
  CallPeer(this.id, this.name);
}

class GroupChatItem {
  final String from, name, text;
  GroupChatItem(this.from, this.name, this.text);
}

class GroupCallService extends ChangeNotifier {
  GroupCallService(this.wsUrl);

  /// e.g. ws://host/ws/group/4/?role=student&user_id=12
  final String wsUrl;

  WebSocketChannel? _ch;
  Future<void> _queue = Future.value(); // handle signaling messages one at a time

  String? selfId;
  MediaStream? localStream;
  MediaStream? _screenStream;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final Map<String, CallPeer> peers = {};
  final List<GroupChatItem> chat = [];

  bool micOn = true;
  bool camOn = true;
  bool sharing = false;
  bool connected = false;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static const Map<String, dynamic> _config = {
    'sdpSemantics': 'unified-plan',
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      // Add your own TURN server here, otherwise some students will never connect:
      // {'urls': 'turn:YOUR_HOST:3478', 'username': 'user', 'credential': 'pass'},
    ],
  };

  // ---- Android foreground service (required for screen capture) ------------

  Future<void> _startAndroidForeground() async {
    const cfg = FlutterBackgroundAndroidConfig(
      notificationTitle: 'Screen sharing',
      notificationText: 'You are sharing your screen in Class Room',
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      // Without this, initialize() returns false when the battery-optimisation
      // prompt is refused/ignored (common on Xiaomi), and no service is started.
      shouldRequestBatteryOptimizationsOff: false,
      enableWifiLock: false,
    );
    final ok = await FlutterBackground.initialize(androidConfig: cfg);
    if (!ok) {
      throw Exception('Could not prepare the background service for screen sharing');
    }
    if (!FlutterBackground.isBackgroundExecutionEnabled) {
      final started = await FlutterBackground.enableBackgroundExecution();
      if (!started) {
        throw Exception('Could not start the screen-sharing service');
      }
    }
    // The service calls startForeground() asynchronously; capture must not
    // begin before it has done so.
    await Future.delayed(const Duration(milliseconds: 800));
  }

  Future<void> _stopAndroidForeground() async {
    if (FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }
  }

  // ---- join / signaling -----------------------------------------------------

  Future<void> join() async {
    await localRenderer.initialize();
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user', 'width': 640, 'height': 480, 'frameRate': 24},
    });
    localRenderer.srcObject = localStream;

    _ch = WebSocketChannel.connect(Uri.parse(wsUrl));
    _ch!.stream.listen(
      (raw) {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        _queue = _queue.then((_) => _handle(m)).catchError((e) => debugPrint('signal error: $e'));
      },
      onDone: () {
        connected = false;
        notifyListeners();
      },
      onError: (e) => debugPrint('ws error: $e'),
    );
    connected = true;
    notifyListeners();
  }

  void _send(Map<String, dynamic> m) => _ch?.sink.add(jsonEncode(m));

  Future<void> _handle(Map<String, dynamic> m) async {
    switch (m['type']) {
      case 'welcome':
        selfId = m['self'];
        for (final h in (m['history'] as List? ?? [])) {
          chat.add(GroupChatItem(h['from'], h['name'], h['text']));
        }
        // I'm the newcomer: I send an offer to everybody already in the room.
        for (final p in (m['peers'] as List)) {
          final peer = await _createPeer(p['id'], p['name']);
          final offer = await peer.pc!.createOffer();
          await peer.pc!.setLocalDescription(offer);
          _send({'type': 'offer', 'to': peer.id, 'sdp': offer.sdp});
        }
        break;

      case 'peer-joined':
        // They will send me an offer; nothing to do yet.
        break;

      case 'offer':
        final from = m['from'] as String;
        final peer = peers[from] ?? await _createPeer(from, (m['name'] ?? from) as String);
        await peer.pc!.setRemoteDescription(RTCSessionDescription(_boostVideoBitrate(m['sdp'] as String), 'offer'));
        peer.remoteSet = true;
        await _flushIce(peer);
        final answer = await peer.pc!.createAnswer();
        await peer.pc!.setLocalDescription(answer);
        _send({'type': 'answer', 'to': from, 'sdp': answer.sdp});
        break;

      case 'answer':
        final p = peers[m['from']];
        if (p == null) break;
        await p.pc!.setRemoteDescription(RTCSessionDescription(_boostVideoBitrate(m['sdp'] as String), 'answer'));
        p.remoteSet = true;
        await _flushIce(p);
        break;

      case 'ice':
        final p = peers[m['from']];
        if (p == null) break;
        final c = m['candidate'];
        final cand = RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);
        if (p.remoteSet) {
          await p.pc!.addCandidate(cand);
        } else {
          p.pendingIce.add(cand);
        }
        break;

      case 'peer-left':
        await _removePeer(m['id']);
        break;

      case 'screen-state':
        peers[m['from']]?.sharing = m['sharing'] == true;
        break;

      case 'chat':
        chat.add(GroupChatItem(m['from'], m['name'], m['text']));
        break;
    }
    notifyListeners();
  }

  /// Adds Google's bitrate hints to every video codec of an incoming SDP.
  /// The sender reads them from the remote description, so this lifts the low
  /// default start bitrate (~300 kbps). With that default WebRTC shrinks the
  /// picture in the first seconds and a static slide then stays tiny and blocky.
  String _boostVideoBitrate(String sdp) {
    final nl = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.split(nl);
    const hints =
        'x-google-min-bitrate=800;x-google-start-bitrate=2000;x-google-max-bitrate=4000';
    final codec = RegExp(r'^a=rtpmap:(\d+) (VP8|VP9|H264|AV1)/90000');

    // pass 1: which video payload types exist, and which already have an fmtp line
    final videoPts = <String>{};
    final withFmtp = <String>{};
    var inVideo = false;
    for (final l in lines) {
      if (l.startsWith('m=')) inVideo = l.startsWith('m=video');
      if (!inVideo) continue;
      final m = codec.firstMatch(l);
      if (m != null) videoPts.add(m.group(1)!);
      if (l.startsWith('a=fmtp:')) {
        withFmtp.add(l.substring(7).split(' ').first);
      }
    }

    // pass 2: rewrite
    final out = <String>[];
    inVideo = false;
    for (final l in lines) {
      if (l.startsWith('m=')) inVideo = l.startsWith('m=video');
      if (inVideo && l.startsWith('a=fmtp:')) {
        final pt = l.substring(7).split(' ').first;
        if (videoPts.contains(pt)) {
          out.add('$l;$hints');
          continue;
        }
      }
      out.add(l);
      if (inVideo) {
        final m = codec.firstMatch(l);
        if (m != null && !withFmtp.contains(m.group(1))) {
          out.add('a=fmtp:${m.group(1)} $hints');
        }
      }
    }
    return out.join(nl);
  }

  Future<void> _flushIce(CallPeer p) async {
    for (final c in p.pendingIce) {
      await p.pc!.addCandidate(c);
    }
    p.pendingIce.clear();
  }

  Future<CallPeer> _createPeer(String id, String name) async {
    final peer = CallPeer(id, name);
    await peer.renderer.initialize();
    final pc = await createPeerConnection(_config);
    peer.pc = pc;

    for (final t in localStream!.getTracks()) {
      // someone joining while I'm sharing should get my screen, not my camera
      final track = (t.kind == 'video' && sharing) ? _screenStream!.getVideoTracks().first : t;
      await pc.addTrack(track, localStream!);
    }

    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        _send({'type': 'ice', 'to': id, 'candidate': c.toMap()});
      }
    };
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        peer.renderer.srcObject = e.streams.first;
        notifyListeners();
      }
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        pc.restartIce();
      }
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected && sharing) {
        _tunePeerVideo(peer, screen: true);
      }
    };

    peers[id] = peer;
    return peer;
  }

  Future<void> _removePeer(String id) async {
    final p = peers.remove(id);
    if (p == null) return;
    await p.pc?.close();
    p.renderer.srcObject = null;
    await p.renderer.dispose();
  }

  // ---- controls -----------------------------------------------------------

  void toggleMic() {
    micOn = !micOn;
    for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    notifyListeners();
  }

  void toggleCam() {
    camOn = !camOn;
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camOn;
    }
    notifyListeners();
  }

  /// Swaps the outgoing video track for the screen track (no renegotiation needed).
  /// On Android the media-projection foreground service must be running BEFORE
  /// getDisplayMedia, otherwise Android throws a SecurityException.
  /// iOS needs a Broadcast Upload Extension.
  Future<void> startScreenShare() async {
    if (sharing) return;

    if (_isAndroid) {
      // Android 14+: the user must grant screen-capture consent BEFORE a
      // mediaProjection foreground service is allowed to start.
      final granted = await Helper.requestCapturePermission();
      if (!granted) throw Exception('Screen capture permission was denied');
      await _startAndroidForeground();
    }

    try {
      _screenStream = await navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': false});
    } catch (e) {
      if (_isAndroid) await _stopAndroidForeground();
      rethrow;
    }

    final screenTrack = _screenStream!.getVideoTracks().first;
    screenTrack.onEnded = () => stopScreenShare(); // user pressed the system "stop sharing"

    await _replaceVideoTrack(screenTrack);
    for (final p in peers.values) {
      await _tunePeerVideo(p, screen: true);
    }
    localRenderer.srcObject = _screenStream;
    sharing = true;
    Future.delayed(const Duration(seconds: 2), () async {
      if (!sharing) return;
      for (final p in peers.values) {
        await _tunePeerVideo(p, screen: true);
      }
    });
    _send({'type': 'screen-state', 'sharing': true});
    notifyListeners();
  }

  Future<void> stopScreenShare() async {
    if (!sharing) return;
    sharing = false;
    final cam = localStream!.getVideoTracks().first;
    await _replaceVideoTrack(cam);
    for (final p in peers.values) {
      await _tunePeerVideo(p, screen: false);
    }
    localRenderer.srcObject = localStream;
    await _screenStream?.dispose();
    _screenStream = null;
    if (_isAndroid) await _stopAndroidForeground();
    _send({'type': 'screen-state', 'sharing': false});
    notifyListeners();
  }

  /// Screen content (text/slides) needs a high, steady bitrate and no
  /// down-scaling; otherwise WebRTC sends a blurry picture and, because a static
  /// slide produces few new frames, it stays blurry. Camera gets normal limits.
  Future<void> _tunePeerVideo(CallPeer p, {required bool screen}) async {
    try {
      final senders = await p.pc!.getSenders();
      for (final s in senders) {
        if (s.track?.kind != 'video') continue;
        final params = s.parameters;

        // The important one: never trade resolution away to save bandwidth/CPU
        // while sharing a screen (the default "balanced" mode shrinks the
        // picture, which is what makes text unreadable).
        params.degradationPreference = screen
            ? RTCDegradationPreference.MAINTAIN_RESOLUTION
            : RTCDegradationPreference.BALANCED;

        final encs = params.encodings;
        if (encs != null) {
          for (final e in encs) {
            if (screen) {
              e.minBitrate = 1000000; // 1 Mbps floor
              e.maxBitrate = 4000000; // 4 Mbps ceiling
              e.maxFramerate = 15; // fewer frames, sharper frames
            } else {
              e.minBitrate = 100000;
              e.maxBitrate = 1200000;
              e.maxFramerate = 30;
            }
            e.scaleResolutionDownBy = 1.0;
          }
        }
        final ok = await s.setParameters(params);
        debugPrint('tune video screen=$screen peer=${p.id} encodings=${encs?.length} applied=$ok');
      }
    } catch (e) {
      debugPrint('tune video failed: $e');
    }
  }

  Future<void> _replaceVideoTrack(MediaStreamTrack track) async {
    for (final p in peers.values) {
      final senders = await p.pc!.getSenders();
      for (final s in senders) {
        if (s.track?.kind == 'video') await s.replaceTrack(track);
      }
    }
  }

  void sendChat(String text) {
    final t = text.trim();
    if (t.isNotEmpty) _send({'type': 'chat', 'text': t});
  }

  /// Cleanup only (no notifyListeners) so it is safe to call from dispose().
  Future<void> leave() async {
    await _ch?.sink.close();
    _ch = null;
    for (final p in peers.values) {
      await p.pc?.close();
      p.renderer.srcObject = null;
      await p.renderer.dispose();
    }
    peers.clear();
    await _screenStream?.dispose();
    _screenStream = null;
    if (_isAndroid) await _stopAndroidForeground();
    localRenderer.srcObject = null;
    await localStream?.dispose();
    await localRenderer.dispose();
  }
}