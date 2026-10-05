// lib/group_room_screen.dart  (copy into BOTH the teacher and the student project)

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config/api_config.dart';
import 'group_call_service.dart';
import 'room_stage.dart';

class GroupRoomScreen extends StatefulWidget {
  final int teacherId;
  final String role; // 'teacher' or 'student'
  final int userId; // teacher tid or student sid

  const GroupRoomScreen({
    super.key,
    required this.teacherId,
    required this.role,
    required this.userId,
  });

  @override
  State<GroupRoomScreen> createState() => _GroupRoomScreenState();
}

class _GroupRoomScreenState extends State<GroupRoomScreen> {
  late final GroupCallService _svc;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // http -> ws, https -> wss
    final ws = ApiConfig.mediaBaseUrl.replaceFirst('http', 'ws');
    _svc = GroupCallService(
      '$ws/ws/group/${widget.teacherId}/?role=${widget.role}&user_id=${widget.userId}',
    );
    _start();
  }

  Future<void> _start() async {
    final st = await [Permission.camera, Permission.microphone].request();
    if (st.values.any((s) => !s.isGranted)) {
      setState(() => _error = 'Camera and microphone permission are required.');
      return;
    }
    try {
      await _svc.join();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not join: $e');
    }
  }

  @override
  void dispose() {
    _svc.leave().whenComplete(_svc.dispose);
    super.dispose();
  }

  Future<void> _toggleShare() async {
    try {
      _svc.sharing ? await _svc.stopScreenShare() : await _svc.startScreenShare();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Screen share failed: $e')),
        );
      }
    }
  }

  void _openChat() {
    final input = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: ListenableBuilder(
            listenable: _svc,
            builder: (_, _) => Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _svc.chat.length,
                    itemBuilder: (_, i) {
                      final m = _svc.chat[i];
                      final me = m.from == _svc.selfId;
                      return Align(
                        alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: me ? Colors.deepPurple.shade400 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!me)
                                Text(m.name,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              Text(m.text, style: TextStyle(color: me ? Colors.white : Colors.black87)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          decoration: const InputDecoration(
                              hintText: 'Message the class...', border: OutlineInputBorder()),
                          onSubmitted: (v) {
                            _svc.sendChat(v);
                            input.clear();
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          _svc.sendChat(input.text);
                          input.clear();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Class Room'),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: _svc,
                  builder: (context, _) {
                    return Column(
                      children: [
                        Expanded(child: RoomStage(svc: _svc)),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _ctrl(_svc.micOn ? Icons.mic : Icons.mic_off, _svc.toggleMic,
                                    active: _svc.micOn),
                                _ctrl(_svc.camOn ? Icons.videocam : Icons.videocam_off, _svc.toggleCam,
                                    active: _svc.camOn),
                                _ctrl(Icons.screen_share, _toggleShare, active: !_svc.sharing,
                                    highlight: _svc.sharing),
                                _ctrl(Icons.chat_bubble, _openChat),
                                _ctrl(Icons.call_end, () => Navigator.pop(context), danger: true),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _ctrl(IconData icon, VoidCallback onTap,
      {bool active = true, bool danger = false, bool highlight = false}) {
    final bg = danger
        ? Colors.red
        : highlight
            ? Colors.green
            : (active ? Colors.white24 : Colors.white70);
    return CircleAvatar(
      radius: 26,
      backgroundColor: bg,
      child: IconButton(
        icon: Icon(icon, color: (active || danger || highlight) ? Colors.white : Colors.black),
        onPressed: onTap,
      ),
    );
  }
}