// lib/group_call_service.dart  (TEACHER project)
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

  /// e.g. ws://host/ws/group/4/?role=teacher&user_id=12
  final String wsUrl;

  /// Set to false when you are done debugging.
  static const bool _debugStats = true;

  /// Total upload budget (bits/s) shared between all viewers while presenting.
  /// The call is a mesh, so every student gets its own copy of the stream.
  static const int _totalScreenBudget = 4000000;
  static const int _minScreenBitrate = 600000;
  static const int _maxScreenBitrate = 2500000;

  WebSocketChannel? _ch;
  Future<void> _queue = Future.value(); // handle signaling messages one at a time
  Timer? _statsTimer;

  String? selfId;
  MediaStream? localStream;
  MediaStream? _screenStream;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final Map<String, CallPeer> peers = {};
  final Set<String> _sharingIds = {}; // peers known to be presenting
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

  // ---- SDP boost: make the video encoder start high instead of ~300 kbps ----

  String _boostSdp(String sdp) {
    final lines = sdp.split('\r\n');
    final out = <String>[];
    bool inVideo = false;
    final fmtpDone = <String>{};

    // payload types that already have an fmtp line
    for (final l in lines) {
      final m = RegExp(r'^a=fmtp:(\d+) ').firstMatch(l);
      if (m != null) fmtpDone.add(m.group(1)!);
    }

    const extra =
        'x-google-start-bitrate=1500;x-google-min-bitrate=600;x-google-max-bitrate=2500';

    for (final l in lines) {
      if (l.startsWith('m=')) inVideo = l.startsWith('m=video');

      if (inVideo && l.startsWith('a=fmtp:') && !l.contains('apt=')) {
        out.add('$l;$extra');
        continue;
      }

      out.add(l);

      if (inVideo) {
        final r = RegExp(r'^a=rtpmap:(\d+) (VP8|VP9|H264|AV1)/').firstMatch(l);
        if (r != null && !fmtpDone.contains(r.group(1)!)) {
          out.add('a=fmtp:${r.group(1)} $extra');
        }
      }
    }
    return out.join('\r\n');
  }

  // ---- Android foreground service (required for screen capture) ------------

  Future<void> _startAndroidForeground() async {
    const cfg = FlutterBackgroundAndroidConfig(
      notificationTitle: 'Screen sharing',
      notificationText: 'You are sharing your screen in Class Room',
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
    );
    final ok = await FlutterBackground.initialize(androidConfig: cfg);
    if (ok && !FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.enableBackgroundExecution();
    }
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

    if (_debugStats) _startStats();
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
          final boosted = RTCSessionDescription(_boostSdp(offer.sdp!), offer.type);
          await peer.pc!.setLocalDescription(boosted);
          _send({'type': 'offer', 'to': peer.id, 'sdp': boosted.sdp});
        }
        break;

      case 'peer-joined':
        // They will send me an offer. If I'm presenting, tell the room again so
        // the newcomer knows right away (they missed the first announcement).
        if (sharing) _send({'type': 'screen-state', 'sharing': true});
        break;

      case 'offer':
        final from = m['from'] as String;
        final peer = peers[from] ?? await _createPeer(from, (m['name'] ?? from) as String);
        await peer.pc!.setRemoteDescription(
            RTCSessionDescription(_boostSdp(m['sdp'] as String), 'offer'));
        peer.remoteSet = true;
        await _flushIce(peer);
        final answer = await peer.pc!.createAnswer();
        final boostedAns = RTCSessionDescription(_boostSdp(answer.sdp!), answer.type);
        await peer.pc!.setLocalDescription(boostedAns);
        _send({'type': 'answer', 'to': from, 'sdp': boostedAns.sdp});
        if (sharing) {
          _send({'type': 'screen-state', 'sharing': true});
          await _tuneSafely(screen: true);
        }
        break;

      case 'answer':
        final p = peers[m['from']];
        if (p == null) break;
        await p.pc!.setRemoteDescription(
            RTCSessionDescription(_boostSdp(m['sdp'] as String), 'answer'));
        p.remoteSet = true;
        await _flushIce(p);
        // The late joiner's sender is only fully ready after the answer.
        if (sharing) await _tuneSafely(screen: true);
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
        // fewer viewers -> each remaining one can get more bitrate
        if (sharing) await _tuneSafely(screen: true);
        break;

      case 'screen-state':
        final sid = m['from'] as String;
        final on = m['sharing'] == true;
        if (on) {
          _sharingIds.add(sid);
        } else {
          _sharingIds.remove(sid);
        }
        peers[sid]?.sharing = on;
        break;

      case 'chat':
        chat.add(GroupChatItem(m['from'], m['name'], m['text']));
        break;
    }
    notifyListeners();
  }

  Future<void> _flushIce(CallPeer p) async {
    for (final c in p.pendingIce) {
      await p.pc!.addCandidate(c);
    }
    p.pendingIce.clear();
  }

  // ---- quality tuning ---------------------------------------------------------

  /// Bitrate per viewer while presenting: shared upload budget / number of viewers.
  int get _perPeerScreenBitrate {
    final n = peers.isEmpty ? 1 : peers.length;
    return (_totalScreenBudget ~/ n).clamp(_minScreenBitrate, _maxScreenBitrate);
  }

  /// Never throws: a tuning failure must not break sharing or stopping.
  Future<void> _tuneSafely({required bool screen}) async {
    try {
      await _tuneVideoSenders(screen: screen);
    } catch (e) {
      debugPrint('tune failed: $e');
    }
  }

  /// Make WebRTC favour sharp text over smooth motion.
  Future<void> _tuneVideoSenders({required bool screen}) async {
    final screenBitrate = _perPeerScreenBitrate;

    for (final p in peers.values) {
      final pc = p.pc;
      if (pc == null) continue;

      final senders = await pc.getSenders();
      for (final s in senders) {
        if (s.track?.kind != 'video') continue;
        try {
          final params = s.parameters;
          params.degradationPreference = screen
              ? RTCDegradationPreference.MAINTAIN_RESOLUTION
              : RTCDegradationPreference.BALANCED;

          final encodings = params.encodings ?? <RTCRtpEncoding>[];
          if (encodings.isEmpty) {
            debugPrint('tune: no encodings for peer ${p.id}');
          }
          for (final e in encodings) {
            e.maxBitrate = screen ? screenBitrate : 800000;
            e.minBitrate = screen ? (screenBitrate ~/ 2) : null;
            e.maxFramerate = screen ? 15 : 24;
            e.scaleResolutionDownBy = 1.0;
          }
          await s.setParameters(params);
        } catch (e) {
          debugPrint('tune sender failed for ${p.id}: $e');
        }
      }
    }
  }

  // ---- debug stats --------------------------------------------------------------

  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      for (final p in peers.values) {
        try {
          final stats = await p.pc!.getStats();
          for (final r in stats) {
            final v = r.values;
            if (r.type == 'inbound-rtp' && v['kind'] == 'video') {
              debugPrint('RX[${p.name}] ${v['frameWidth']}x${v['frameHeight']} '
                  'fps=${v['framesPerSecond']}');
            }
            if (r.type == 'outbound-rtp' && v['kind'] == 'video') {
              debugPrint('TX[${p.name}] ${v['frameWidth']}x${v['frameHeight']} '
                  'limit=${v['qualityLimitationReason']}');
            }
          }
        } catch (_) {}
      }
    });
  }

  // ---- peers --------------------------------------------------------------------

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
        _send({'type': 'screen-state', 'sharing': true});
        _tuneSafely(screen: true);
      }
    };

    peer.sharing = _sharingIds.contains(id);
    peers[id] = peer;

    // a viewer joined while I'm presenting: tune everybody (budget is shared)
    if (sharing) await _tuneSafely(screen: true);
    return peer;
  }

  Future<void> _removePeer(String id) async {
    _sharingIds.remove(id);
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
      _screenStream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'width': {'ideal': 1080},
          'height': {'ideal': 2400},
          'frameRate': 15,
        },
        'audio': false,
      });
    } catch (e) {
      if (_isAndroid) await _stopAndroidForeground();
      rethrow;
    }

    final screenTrack = _screenStream!.getVideoTracks().first;
    screenTrack.onEnded = () => stopScreenShare(); // user pressed the system "stop sharing"

    await _replaceVideoTrack(screenTrack);
    localRenderer.srcObject = _screenStream;
    sharing = true;

    // tune AFTER the screen track is on the senders; a failure must not kill the share
    await _tuneSafely(screen: true);

    _send({'type': 'screen-state', 'sharing': true});
    notifyListeners();
  }

  Future<void> stopScreenShare() async {
    if (!sharing) return;
    sharing = false;

    final cam = localStream!.getVideoTracks().first;
    await _replaceVideoTrack(cam);
    localRenderer.srcObject = localStream;
    await _tuneSafely(screen: false);

    await _screenStream?.dispose();
    _screenStream = null;
    if (_isAndroid) await _stopAndroidForeground();

    _send({'type': 'screen-state', 'sharing': false});
    notifyListeners();
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
    _statsTimer?.cancel();
    _statsTimer = null;
    await _ch?.sink.close();
    _ch = null;
    for (final p in peers.values) {
      await p.pc?.close();
      p.renderer.srcObject = null;
      await p.renderer.dispose();
    }
    peers.clear();
    _sharingIds.clear();
    await _screenStream?.dispose();
    _screenStream = null;
    if (_isAndroid) await _stopAndroidForeground();
    localRenderer.srcObject = null;
    await localStream?.dispose();
    await localRenderer.dispose();
  }
}