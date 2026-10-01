import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/zoom_call_service.dart';
import '../config/api_config.dart'; // adjust to where your ApiConfig lives
import 'app_logo.dart';

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

AppBar _meetingAppBar(String title) => AppBar(
      backgroundColor: const Color(0xFF013768),
      foregroundColor: Colors.white,
      titleSpacing: 0,
      title: Row(
        children: [
          const AppLogo(radius: 18),
          const SizedBox(width: 12),
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );

/// Result of checking "is this meeting open right now?"
enum MeetingWindow { notStarted, open, ended }

MeetingWindow _windowFor(Map m, {int earlyMinutes = 0}) {
  final start = DateTime.parse(m['start_time']).toLocal();
  final end = start.add(Duration(minutes: m['duration_minutes'] as int));
  final now = DateTime.now();
  if (now.isAfter(end)) return MeetingWindow.ended;
  if (now.isBefore(start.subtract(Duration(minutes: earlyMinutes)))) {
    return MeetingWindow.notStarted;
  }
  return MeetingWindow.open;
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

        title: Row(
    children: [
      const AppLogo(radius: 22),   // bigger than the default 18
      const SizedBox(width: 12),
      Text('Meetings'),           // your existing name
    ],
  ),
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

/// Schedule Meeting form
class ScheduleMeetingScreen extends StatefulWidget {
  const ScheduleMeetingScreen({super.key, required this.teacherId});
  final int teacherId;

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
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
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
    setState(() => _saving = true);
    try {
      await _api.schedule({
        'teacher_id': widget.teacherId,
        'topic': _topic.text.trim(),
        'description': _desc.text.trim(),
        'start_time': start.toUtc().toIso8601String(),
        'duration_minutes': _minutes,
        'waiting_room': _waitingRoom,
        'host_video': _hostVideo,
        'participant_video': _participantVideo,
        'student_ids': _invited.toList(),
      });
      if (!mounted) return;
      _snack('Meeting scheduled');
      Navigator.pop(context, true);
    } catch (e) {
      _snack('Could not schedule: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Meeting'),
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
                label: Text(_time == null ? 'Time' : l.formatTimeOfDay(_time!)),
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
                    : const Text('Save'),
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

  // Keep in sync with HOST_EARLY_MINUTES in Django (zoommeeting.py)
  static const _hostEarlyMinutes = 0;

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _host(Map m) async {
    switch (_windowFor(m, earlyMinutes: _hostEarlyMinutes)) {
      case MeetingWindow.ended:
        _msg('Time passed. This meeting has already ended.');
        return;
      case MeetingWindow.notStarted:
        _msg('Not started yet. You can host it at '
            '${_when(context, m['start_time'])}.');
        return;
      case MeetingWindow.open:
        break;
    }

    try {
      final url = await _api.hostUrl(m['id'] as int, widget.teacherId);
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok) _msg('Could not open Zoom');
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
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
        onRefresh: () async =>
            setState(() => _future = _api.teacherMeetings(widget.teacherId)),
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
                  trailing: FilledButton(
                    onPressed: () => _host(m),
                    child: const Text('Host'),
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

  // Remembers WHICH meeting is being joined.
  int? _joiningId;

  // Minutes before start that students may open the join dialog.
  // 0 = only from the exact start time.
  static const _joinEarlyMinutes = 0;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _joinWith({
    required int id,
    required String meetingNumber,
    required String passcode,
  }) async {
    if (_joiningId != null) return; // already joining something
    setState(() => _joiningId = id);
    try {
      await [Permission.camera, Permission.microphone].request();
      await _zoom.join(
        meetingNumber: meetingNumber,
        password: passcode,
        // "id|name" so the webhook can match attendance to this student
        displayName: '${widget.studentId}|${widget.studentName}',
      );
    } catch (e) {
      _msg('Could not join: $e');
    } finally {
      if (mounted) setState(() => _joiningId = null);
    }
  }

  /// Checks the time window first. Only if the class is running right now
  /// does it show the pre-filled Meeting ID / Passcode dialog.
  Future<void> _openJoinDialog(Map m) async {
    if (_joiningId != null) {
      _msg('Already joining a class...');
      return;
    }

    // ---- time window check ----
    switch (_windowFor(m, earlyMinutes: _joinEarlyMinutes)) {
      case MeetingWindow.ended:
        _msg('Time passed. This class has already ended.');
        return;
      case MeetingWindow.notStarted:
        _msg('Not started yet. Class starts at '
            '${_when(context, m['start_time'])}.');
        return;
      case MeetingWindow.open:
        break;
    }
    // ---- end check ----

    final meetingCtrl =
        TextEditingController(text: m['meeting_id'].toString());
    final passcodeCtrl =
        TextEditingController(text: (m['passcode'] ?? '').toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m['topic'].toString()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_when(context, m['start_time']),
                style: const TextStyle(color: Colors.grey)),
            Text('${m['duration_minutes']} min',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: meetingCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Meeting ID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passcodeCtrl,
              decoration: const InputDecoration(labelText: 'Passcode'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _joinWith(
        id: m['id'] as int,
        meetingNumber: meetingCtrl.text.trim(),
        passcode: passcodeCtrl.text.trim(),
      );
    }
    meetingCtrl.dispose();
    passcodeCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _meetingAppBar('My classes'),
      body: RefreshIndicator(
        onRefresh: () async =>
            setState(() => _future = _api.studentMeetings(widget.studentId)),
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
                // Only true for the row that is actually joining
                final isThisJoining = _joiningId == m['id'];
                return ListTile(
                  title: Text(m['topic'].toString()),
                  subtitle: Text(
                      '${_when(context, m['start_time'])} · ${m['duration_minutes']} min'),
                  trailing: FilledButton(
                    // Only this row's button is disabled/spinning
                    onPressed: isThisJoining ? null : () => _openJoinDialog(m),
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