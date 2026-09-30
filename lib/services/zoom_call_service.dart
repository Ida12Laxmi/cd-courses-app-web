import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_zoom_meeting_sdk/enums/status_zoom_error.dart';
import 'package:flutter_zoom_meeting_sdk/flutter_zoom_meeting_sdk.dart';
import 'package:flutter_zoom_meeting_sdk/models/zoom_meeting_sdk_request.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';


class ZoomCallService {
  final FlutterZoomMeetingSdk _sdk = FlutterZoomMeetingSdk();
  bool _initialized = false;
  StreamSubscription? _authSub;

  /// Asks your Django backend for a signed SDK token.
  /// The SDK secret never touches the app.
  Future<String> _fetchSignature(String meetingNumber, {int role = 0}) async {
    // Use whichever path you actually mounted:
    // /accounts/zoom/sdk-token/ or /zoom/sdk-token/
    final url = Uri.parse('${ApiConfig.mediaBaseUrl}/accounts/zoom/sdk-token/');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'meeting_number': meetingNumber, 'role': role}),
    );
    if (response.statusCode != 200) {
      throw Exception('Could not get Zoom token (${response.statusCode})');
    }
    return jsonDecode(response.body)['signature'] as String;
  }

  Future<void> join({
    required String meetingNumber,
    required String password,
    required String displayName,
    int role = 0, // 0 = student/participant, 1 = teacher/host
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Zoom Meeting SDK is not available on Flutter Web');
    }

    final cleanNumber = meetingNumber.replaceAll(' ', '');
    if (cleanNumber.isEmpty) {
      throw ArgumentError('Enter a meeting number');
    }

    final signature = await _fetchSignature(cleanNumber, role: role);

    if (!_initialized) {
      await _sdk.initZoom();
      _initialized = true;
    }

    // Wait for the SDK to confirm authentication before joining.
    final authenticated = Completer<void>();
    await _authSub?.cancel();
    _authSub = _sdk.onAuthenticationReturn.listen((event) {
      if (authenticated.isCompleted) return;
      if (event.params?.statusEnum == StatusZoomError.success) {
        authenticated.complete();
      } else {
        authenticated.completeError(
          Exception('Zoom authentication failed: ${event.params?.statusEnum}'),
        );
      }
    });

    await _sdk.authZoom(jwtToken: signature);
    await authenticated.future.timeout(const Duration(seconds: 20));

    await _sdk.joinMeeting(
      ZoomMeetingSdkRequest(
        meetingNumber: cleanNumber,
        password: password,
        displayName: displayName,
      ),
    );
  }

  void dispose() {
    _authSub?.cancel();
    if (_initialized) {
      _sdk.unInitZoom();
      _initialized = false;
    }
  }
}