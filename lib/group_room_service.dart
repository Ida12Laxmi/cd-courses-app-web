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
  static const String _allKey = '__all__';

  late final GroupCallService _svc;
  final ValueNotifier<List<dynamic>> _roster = ValueNotifier([]); // all students of this teacher
  bool _ready = false;
  bool _inviteSheetShown = false; // auto-open the invite sheet only once
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
      if (mounted) {
        setState(() => _ready = true);
        // Once the teacher is in the room, ask which subject to invite.
        if (!_inviteSheetShown) {
          _inviteSheetShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openInviteSheet();
          });
        }
      }
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

  // ---- invite by subject --------------------------------------------------

  String _subjectKeyOf(dynamic student) =>
      (student['subject'] ?? '').toString().trim().toLowerCase();

  // lowercase key -> label (original spelling), sorted A-Z; blank subjects are skipped
  Map<String, String> _subjectChoices() {
    final found = <String, String>{};
    for (final s in _roster.value) {
      final raw = (s['subject'] ?? '').toString().trim();
      if (raw.isEmpty) continue;
      found.putIfAbsent(raw.toLowerCase(), () => raw);
    }
    final keys = found.keys.toList()
      ..sort((a, b) => found[a]!.toLowerCase().compareTo(found[b]!.toLowerCase()));
    return {for (final k in keys) k: found[k]!};
  }

  int _studentsIn(String key) => key == _allKey
      ? _roster.value.length
      : _roster.value.where((s) => _subjectKeyOf(s) == key).length;

  /// Sends the invitation notification. Empty [subject] = all students.
  Future<bool> _sendInvite(String subject) async {
    try {
      final r = await http.post(
        Uri.parse('${ApiConfig.mediaBaseUrl}/accounts/group-room/invite/'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'teacher': widget.teacherId, 'subject': subject}),
      );
      if (!mounted) return false;
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final msg = data['message']?.toString() ??
            'Invitation sent to ${data['invited'] ?? 0} student(s)';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return true;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send invite (${r.statusCode})')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    }
    return false;
  }

  void _openInviteSheet() {
    String? selectedKey; // null until the teacher chooses
    bool sending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder<List<dynamic>>(
            valueListenable: _roster,
            builder: (_, _, _) {
              final subjects = _subjectChoices();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invite students to this class',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose a subject. Only students of that subject get the invitation.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  if (_roster.value.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No students added yet.'),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in subjects.entries)
                          ChoiceChip(
                            label: Text('${e.value} (${_studentsIn(e.key)})'),
                            selected: selectedKey == e.key,
                            selectedColor: const Color(0xFF013768),
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: selectedKey == e.key ? Colors.white : const Color(0xFF013768),
                            ),
                            onSelected: (_) => setSheetState(() => selectedKey = e.key),
                          ),
                        ChoiceChip(
                          label: Text('All students (${_studentsIn(_allKey)})'),
                          selected: selectedKey == _allKey,
                          selectedColor: const Color(0xFF013768),
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: selectedKey == _allKey ? Colors.white : const Color(0xFF013768),
                          ),
                          onSelected: (_) => setSheetState(() => selectedKey = _allKey),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: sending ? null : () => Navigator.pop(ctx),
                          child: const Text('Skip'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (selectedKey == null || sending)
                              ? null
                              : () async {
                                  setSheetState(() => sending = true);
                                  final subject =
                                      selectedKey == _allKey ? '' : subjects[selectedKey]!;
                                  final ok = await _sendInvite(subject);
                                  if (ok) {
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  } else if (ctx.mounted) {
                                    setSheetState(() => sending = false);
                                  }
                                },
                          icon: sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send),
                          label: const Text('Send invite'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ),
    );
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
                    subtitle: Text(
                      [s['subject'], s['level']]
                          .where((e) => e != null && e.toString().trim().isNotEmpty)
                          .join(' • '),
                    ),
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
          IconButton(
            tooltip: 'Invite students by subject',
            icon: const Icon(Icons.campaign),
            onPressed: _openInviteSheet,
          ),
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