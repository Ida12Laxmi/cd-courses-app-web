// TEACHER project only. Save as lib/group_room_screen.dart
// (the student project keeps the simpler group_room_screen.dart from before).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import 'config/api_config.dart';
import 'group_call_service.dart';
import 'room_stage.dart';
import 'student_register.dart'; // AddStudentForm

class GroupRoomScreen extends StatefulWidget {
  final int teacherId;
  final String role; // 'teacher'
  final int userId; // teacher tid

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
  final ValueNotifier<List<dynamic>> _roster = ValueNotifier([]); // all students of this teacher
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
    _loadRoster();
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

  Future<void> _loadRoster() async {
    try {
      final r = await http.get(Uri.parse(
          '${ApiConfig.mediaBaseUrl}/accounts/students/teacher/${widget.teacherId}/'));
      if (r.statusCode == 200) {
        _roster.value = jsonDecode(r.body) as List<dynamic>;
      }
    } catch (e) {
      debugPrint('roster load failed: $e');
    }
  }

  Future<void> _addStudent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddStudentForm(teacherId: widget.teacherId)),
    );
    if (result == true) _loadRoster(); // new student can join the room right away
  }

  @override
  void dispose() {
    _svc.leave().whenComplete(_svc.dispose);
    _roster.dispose();
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

  // ---- participants -------------------------------------------------------

  void _openParticipants() {
    _loadRoster(); // refresh each time the panel opens
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.65,
        child: ListenableBuilder(
          listenable: Listenable.merge([_svc, _roster]),
          builder: (_, _) {
            final inRoom = _svc.peers.values.toList();
            final inRoomIds = _svc.peers.keys.toSet();
            final notJoined = _roster.value
                .where((s) => !inRoomIds.contains('student_${s['sid']}'))
                .toList();

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('In the room (${inRoom.length + 1})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _addStudent();
                      },
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add student'),
                    ),
                  ],
                ),
                const ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Icon(Icons.school)),
                  title: Text('You (Teacher)'),
                ),
                for (final p in inRoom)
                  ListTile(
                    dense: true,
                    leading: const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(p.name),
                    trailing: p.sharing
                        ? const Icon(Icons.screen_share, color: Colors.green)
                        : null,
                  ),
                const Divider(height: 24),
                Text('Not joined (${notJoined.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (notJoined.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Everyone has joined.'),
                  ),
                for (final s in notJoined)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade300,
                      child: const Icon(Icons.person_outline),
                    ),
                    title: Text(s['username']?.toString() ?? ''),
                    subtitle: Text(s['level']?.toString() ?? ''),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- chat ---------------------------------------------------------------

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

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Class Room'),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        actions: [
          ListenableBuilder(
            listenable: _svc,
            builder: (_, _) => IconButton(
              tooltip: 'Participants',
              onPressed: _openParticipants,
              icon: Badge(
                label: Text('${_svc.peers.length + 1}'),
                child: const Icon(Icons.people),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add student',
            icon: const Icon(Icons.person_add),
            onPressed: _addStudent,
          ),
        ],
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
                                _ctrl(Icons.screen_share, _toggleShare,
                                    active: !_svc.sharing, highlight: _svc.sharing),
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
