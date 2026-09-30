import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'zoom_call_service.dart';
import '../config/api_config.dart'; // adjust to where your ApiConfig lives

class MeetingApi {
  Uri _u(String path) => Uri.parse('${ApiConfig.mediaBaseUrl}$path');
  static const _json = {'Content-Type': 'application/json'};

  dynamic _check(http.Response r) {
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      throw Exception(
          'Server returned ${r.statusCode} (not JSON) for ${r.request?.url}');
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    throw Exception(body is Map ? (body['detail'] ?? r.body) : r.body);
  }

  Future<List<dynamic>> students(int teacherId) async =>
      _check(await http.get(_u('/meetings/students/$teacherId/')));

  Future<List<dynamic>> teacherMeetings(int teacherId) async =>
      _check(await http.get(_u('/meetings/teacher/$teacherId/')));

  Future<List<dynamic>> studentMeetings(int studentId) async =>
      _check(await http.get(_u('/meetings/student/$studentId/')));

  Future<void> schedule(Map<String, dynamic> body) async => _check(
      await http.post(_u('/meetings/schedule/'),
          headers: _json, body: jsonEncode(body)));

  // NEW: edit a meeting
  Future<void> updateMeeting(int id, Map<String, dynamic> body) async =>
      _check(await http.put(_u('/meetings/$id/update/'),
          headers: _json, body: jsonEncode(body)));

  // NEW: delete a meeting
  Future<void> deleteMeeting(int id, int teacherId) async => _check(
      await http.delete(_u('/meetings/$id/delete/?teacher_id=$teacherId')));

  Future<String> hostUrl(int id, int teacherId) async {
    final res = _check(await http.post(_u('/meetings/$id/host/'),
        headers: _json, body: jsonEncode({'teacher_id': teacherId})));
    return res['start_url'] as String;
  }
}

String _when(BuildContext context, String iso) {
  final dt = DateTime.parse(iso).toLocal();
  final l = MaterialLocalizations.of(context);
  return '${l.formatMediumDate(dt)}  ${l.formatTimeOfDay(TimeOfDay.fromDateTime(dt))}';
}

/// Teacher home: two options, Schedule and Host
class TeacherMeetingHome extends StatelessWidget {
  const TeacherMeetingHome({super.key, required this.teacherId});
  final int teacherId;

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String sub, Widget page) => Card(
          child: ListTile(
            leading: Icon(icon, size: 32, color: const Color(0xFF0B8081)),
            title: Text(title),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => page)),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetings'),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          tile(Icons.event, 'Schedule', 'Plan a class and invite students',
              ScheduleMeetingScreen(teacherId: teacherId)),
          tile(Icons.videocam, 'Host', 'Start one of your scheduled classes',
              HostMeetingsScreen(teacherId: teacherId)),
        ],
      ),
    );
  }
}

/// Schedule Meeting form (also used for editing when [existing] is given)
class ScheduleMeetingScreen extends StatefulWidget {
  const ScheduleMeetingScreen(
      {super.key, required this.teacherId, this.existing}); // CHANGED
  final int teacherId;
  final Map? existing; // NEW: pass a meeting to edit it

  @override
  State<ScheduleMeetingScreen> createState() => _ScheduleMeetingScreenState();
}

class _ScheduleMeetingScreenState extends State<ScheduleMeetingScreen> {
  final _api = MeetingApi();
  final _topic = TextEditingController(text: 'My Meeting');
  final _desc = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  int _minutes = 40; // Zoom Basic plan limit
  bool _waitingRoom = true;
  bool _hostVideo = false;
  bool _participantVideo = false;
  final Set<int> _invited = {};
  bool _saving = false;

  bool get _isEdit => widget.existing != null; // NEW

  // NEW: pre-fill the form when editing
  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    if (m != null) {
      _topic.text = m['topic'].toString();
      _desc.text = (m['description'] ?? '').toString();
      final dt = DateTime.parse(m['start_time']).toLocal();
      _date = DateTime(dt.year, dt.month, dt.day);
      _time = TimeOfDay.fromDateTime(dt);
      final mins = m['duration_minutes'] as int;
      _minutes = const [15, 30, 40].contains(mins) ? mins : 40;
      _waitingRoom = m['waiting_room'] ?? true;
      _hostVideo = m['host_video'] ?? false;
      _participantVideo = m['participant_video'] ?? false;
      _invited.addAll((m['student_ids'] as List).map((e) => e as int));
    }
  }

  @override
  void dispose() {
    _topic.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // CHANGED: allow an existing (possibly earlier) date without crashing
    final first = (_date != null && _date!.isBefore(now)) ? _date! : now;
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: first,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context, initialTime: _time ?? TimeOfDay.now());
    if (t != null) setState(() => _time = t);
  }

  Future<void> _pickStudents() async {
    try {
      final all = await _api.students(widget.teacherId);
      if (!mounted) return;
      final chosen = {..._invited};
      await showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Invitees'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in all)
                    CheckboxListTile(
                      title: Text(s['name'].toString()),
                      value: chosen.contains(s['id']),
                      onChanged: (v) => setD(() => v == true
                          ? chosen.add(s['id'])
                          : chosen.remove(s['id'])),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  setState(() => _invited
                    ..clear()
                    ..addAll(chosen));
                  Navigator.pop(ctx);
                },
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      _snack('Could not load students: $e');
    }
  }

  Future<void> _save() async {
    if (_date == null || _time == null) {
      _snack('Pick a date and time');
      return;
    }
    final start = DateTime(
        _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
    final body = {
      'teacher_id': widget.teacherId,
      'topic': _topic.text.trim(),
      'description': _desc.text.trim(),
      'start_time': start.toUtc().toIso8601String(),
      'duration_minutes': _minutes,
      'waiting_room': _waitingRoom,
      'host_video': _hostVideo,
      'participant_video': _participantVideo,
      'student_ids': _invited.toList(),
    };
    setState(() => _saving = true);
    try {
      // CHANGED: update when editing, create otherwise
      if (_isEdit) {
        await _api.updateMeeting(widget.existing!['id'] as int, body);
      } else {
        await _api.schedule(body);
      }
      if (!mounted) return;
      _snack(_isEdit ? 'Meeting updated' : 'Meeting scheduled');
      Navigator.pop(context, true);
    } catch (e) {
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Meeting' : 'Schedule Meeting'), // CHANGED
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
              controller: _topic,
              decoration: const InputDecoration(labelText: 'Topic')),
          const SizedBox(height: 12),
          TextField(
              controller: _desc,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)')),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label:
                    Text(_date == null ? 'Date' : l.formatMediumDate(_date!)),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label:
                    Text(_time == null ? 'Time' : l.formatTimeOfDay(_time!)),
                onPressed: _pickTime,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _minutes,
            decoration: const InputDecoration(labelText: 'Duration'),
            items: const [15, 30, 40]
                .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                .toList(),
            onChanged: (v) => setState(() => _minutes = v ?? 40),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Invitees'),
            subtitle: Text(_invited.isEmpty
                ? 'No students selected'
                : '${_invited.length} student(s) selected'),
            trailing: const Icon(Icons.person_add_alt_1),
            onTap: _pickStudents,
          ),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Waiting room'),
              value: _waitingRoom,
              onChanged: (v) => setState(() => _waitingRoom = v)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Host video on'),
              value: _hostVideo,
              onChanged: (v) => setState(() => _hostVideo = v)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Participant video on'),
              value: _participantVideo,
              onChanged: (v) => setState(() => _participantVideo = v)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Update' : 'Save'), // CHANGED
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Host: teacher's scheduled meetings, tap Host to start as host
class HostMeetingsScreen extends StatefulWidget {
  const HostMeetingsScreen({super.key, required this.teacherId});
  final int teacherId;

  @override
  State<HostMeetingsScreen> createState() => _HostMeetingsScreenState();
}

class _HostMeetingsScreenState extends State<HostMeetingsScreen> {
  final _api = MeetingApi();
  late Future<List<dynamic>> _future = _api.teacherMeetings(widget.teacherId);

 /* void _refresh() =>
      setState(() => _future = _api.teacherMeetings(widget.teacherId));*/

  void _refresh() {
  setState(() {
    _future = _api.teacherMeetings(widget.teacherId);
  });
}    
  

  Future<void> _host(int id) async {
    try {
      final url = await _api.hostUrl(id, widget.teacherId);
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open Zoom')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not host: $e')));
    }
  }

  // NEW
  Future<void> _edit(Map m) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ScheduleMeetingScreen(teacherId: widget.teacherId, existing: m),
      ),
    );
    if (changed == true) _refresh();
  }

  // NEW
  Future<void> _delete(Map m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete meeting?'),
        content: Text(
            '"${m['topic']}" on ${_when(context, m['start_time'])} will be removed for you and all invited students.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.deleteMeeting(m['id'] as int, widget.teacherId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Meeting deleted')));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host a meeting'),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
       // onRefresh: () async => _refresh(),
       onRefresh: () async { _refresh();
                   await _future;
            },
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final items = snap.data!;
            if (items.isEmpty) {
              return const Center(child: Text('No scheduled meetings yet'));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = items[i] as Map;
                return ListTile(
                  title: Text(m['topic'].toString()),
                  subtitle: Text(
                      '${_when(context, m['start_time'])} · ${m['duration_minutes']} min · ${(m['student_ids'] as List).length} student(s)'),
                  // CHANGED: Host button + Edit/Delete menu
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                          onPressed: () => _host(m['id'] as int),
                          child: const Text('Host')),
                      PopupMenuButton<String>(
                        onSelected: (v) => v == 'edit' ? _edit(m) : _delete(m),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit),
                              title: Text('Edit'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete, color: Colors.red),
                              title: Text('Delete'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Student: meetings the teacher added them to, tap Join
class StudentMeetingsScreen extends StatefulWidget {
  const StudentMeetingsScreen(
      {super.key, required this.studentId, required this.studentName});
  final int studentId;
  final String studentName;

  @override
  State<StudentMeetingsScreen> createState() => _StudentMeetingsScreenState();
}

class _StudentMeetingsScreenState extends State<StudentMeetingsScreen> {
  final _api = MeetingApi();
  final _zoom = ZoomCallService();
  late Future<List<dynamic>> _future = _api.studentMeetings(widget.studentId);

  // CHANGED: was `bool _joining`. Now remembers WHICH meeting is being joined,
  // so only that row reacts (fixes "click one, both look clicked").
  int? _joiningId;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _join(Map m) async {
    if (_joiningId != null) return;
    setState(() => _joiningId = m['id'] as int); // CHANGED
    try {
      await [Permission.camera, Permission.microphone].request();
      await _zoom.join(
        meetingNumber: m['meeting_id'].toString(),
        password: m['passcode'].toString(),
        // "id|name" so the webhook can match attendance to this student
        displayName: '${widget.studentId}|${widget.studentName}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not join: $e')));
    } finally {
      if (mounted) setState(() => _joiningId = null); // CHANGED
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My classes'),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
  setState(() {
    _future = _api.studentMeetings(widget.studentId);
  });
  await _future;
},
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final items = snap.data!;
            if (items.isEmpty) {
              return const Center(child: Text('No classes yet'));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = items[i] as Map;
                // CHANGED: true only for the row that is actually joining
                final isThisJoining = _joiningId == m['id'];
                return ListTile(
                  title: Text(m['topic'].toString()),
                  subtitle: Text(
                      '${_when(context, m['start_time'])} · ${m['duration_minutes']} min'),
                  trailing: FilledButton(
                    onPressed:
                        _joiningId != null ? null : () => _join(m), // CHANGED
                    child: isThisJoining
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Join'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
