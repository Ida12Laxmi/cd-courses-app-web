import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'http://192.168.0.196:8000/accounts';
  static const _storage = FlutterSecureStorage();

  static Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _storage.read(key: 'auth_token');
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Token $token',
    };
  }

  static void _checkOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('API error ${res.statusCode}: ${res.body}');
    }
  }

  // ---------- Content ----------

  static Future<List<dynamic>> fetchContent(int studentId, String type) async {
    final res = await http.get(
      Uri.parse('$baseUrl/students/$studentId/content/$type/'),
      headers: await _headers(),
    );
    _checkOk(res);
    return jsonDecode(res.body);
  }

  static Future<Uint8List> streamContentBytes(int contentId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/content/$contentId/stream/'),
      headers: await _headers(json: false),
    );
    _checkOk(res);
    return res.bodyBytes;
  }

  // ---------- Submissions ----------

  static Future<List<dynamic>> fetchAssignmentSubmissions(int studentId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/students/$studentId/assignments/'),
      headers: await _headers(),
    );
    _checkOk(res);
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> fetchProjectSubmissions(int studentId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/students/$studentId/projects/'),
      headers: await _headers(),
    );
    _checkOk(res);
    return jsonDecode(res.body);
  }

  static Future<void> submitAssignment({
    required int studentId,
    required String title,
    required String filePath,
    String description = '',
  }) async {
    await _submit('$baseUrl/students/$studentId/assignments/submit/', title, description, filePath);
  }

  static Future<void> submitProject({
    required int studentId,
    required String title,
    required String filePath,
    String description = '',
  }) async {
    await _submit('$baseUrl/students/$studentId/projects/submit/', title, description, filePath);
  }

  static Future<void> _submit(String url, String title, String description, String filePath) async {
    final token = await _storage.read(key: 'auth_token');
    final req = http.MultipartRequest('POST', Uri.parse(url));
    if (token != null) req.headers['Authorization'] = 'Token $token';
    req.fields['title'] = title;
    req.fields['description'] = description;
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    _checkOk(res);
  }

  // ---------- Student-side: edit/delete own assignment ----------

  static Future<void> updateOwnAssignment({
    required int asid,
    required int studentId,
    required String title,
    String description = '',
    String? filePath,
  }) async {
    await _updateOwn(
      url: '$baseUrl/students/assignments/update/$asid/',
      studentId: studentId,
      title: title,
      description: description,
      filePath: filePath,
    );
  }

  static Future<void> deleteOwnAssignment(int asid, int studentId) async {
    final url = Uri.parse('$baseUrl/students/assignments/delete/$asid/?student_id=$studentId');
    final res = await http.delete(url, headers: await _headers());
    _checkOk(res);
  }

  // ---------- Student-side: edit/delete own project ----------

  static Future<void> updateOwnProject({
    required int psid,
    required int studentId,
    required String title,
    String description = '',
    String? filePath,
  }) async {
    await _updateOwn(
      url: '$baseUrl/students/projects/update/$psid/',
      studentId: studentId,
      title: title,
      description: description,
      filePath: filePath,
    );
  }

  static Future<void> deleteOwnProject(int psid, int studentId) async {
    final url = Uri.parse('$baseUrl/students/projects/delete/$psid/?student_id=$studentId');
    final res = await http.delete(url, headers: await _headers());
    _checkOk(res);
  }

  static Future<void> _updateOwn({
    required String url,
    required int studentId,
    required String title,
    required String description,
    String? filePath,
  }) async {
    final token = await _storage.read(key: 'auth_token');
    final req = http.MultipartRequest('PATCH', Uri.parse(url));
    if (token != null) req.headers['Authorization'] = 'Token $token';
    req.fields['student_id'] = studentId.toString();
    req.fields['title'] = title;
    req.fields['description'] = description;
    if (filePath != null) {
      req.files.add(await http.MultipartFile.fromPath('file', filePath));
    }
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    _checkOk(res);
  }

  // ---------- Conversations / Messages ----------

  static Future<Map<String, dynamic>> getOrCreateConversation({
    required int teacherId,
    required int studentId,
    required String topic,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/conversations/get-or-create/'),
      headers: await _headers(),
      body: jsonEncode({'teacher': teacherId, 'student': studentId, 'topic': topic}),
    );
    _checkOk(res);
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> sendMessage({
    required int convId,
    required String senderType,
    required String text,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/messages/send/'),
      headers: await _headers(),
      body: jsonEncode({'convid': convId, 'sender_type': senderType, 'text': text}),
    );
    _checkOk(res);
    return jsonDecode(res.body);
  }

  // ---------- Attendance ----------

  static Future<List<dynamic>> fetchAttendanceHistory(int studentId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/attendance/student/$studentId/'),
      headers: await _headers(),
    );
    _checkOk(res);
    return jsonDecode(res.body);
  }

  // ---------- Billing ----------

  static Future<List<dynamic>> fetchBills(int studentId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/bills/student/$studentId/'),
      headers: await _headers(),
    );
    _checkOk(res);
    return jsonDecode(res.body);
  }

  static Future<void> registerDeviceToken({
    required String role,
    required int userId,
    required String token,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/devices/register-token/'),
      headers: await _headers(),
      body: jsonEncode({'role': role, 'user_id': userId, 'token': token}),
    );
    _checkOk(res);
  }

  static Future<List<dynamic>> searchContent(int studentId, String query, {String? contentType}) async {
    final uri = Uri.parse('$baseUrl/students/$studentId/search/').replace(queryParameters: {
      'q': query,
      'type': ?contentType,
    });
    final res = await http.get(uri, headers: await _headers());
    _checkOk(res);
    return jsonDecode(res.body);
  }

  static Future<Map<String,dynamic>> searchAssignmentorProject(int studentId, String contentType, String query) async {
    final uri=Uri.parse('$baseUrl/students/$studentId/$contentType/search/')
      .replace(queryParameters: {'q': query});
      final res = await http.get(uri, headers: await _headers());
  _checkOk(res);
  return jsonDecode(res.body);
  }
}
