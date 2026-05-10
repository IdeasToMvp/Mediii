import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Talks to the MediBuddy Node API (OpenAI analysis + Supabase inserts with user JWT).
class MediBuddyApi {
  MediBuddyApi();

  String get _base => AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');

  String? get _token => Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _authHeaders {
    final t = _token;
    if (t == null || t.isEmpty) {
      throw StateError('Not signed in');
    }
    return {
      'Authorization': 'Bearer $t',
      'Accept': 'application/json',
    };
  }

  Future<Map<String, dynamic>> analyzeImage(XFile file) async {
    final uri = Uri.parse('$_base/api/prescriptions/analyze-image');
    final bytes = await file.readAsBytes();
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_authHeaders);
    final name = file.name.isNotEmpty ? file.name : 'prescription.jpg';
    final mime = _guessMime(name);
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: name,
        contentType: MediaType.parse(mime),
      ),
    );
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw MediBuddyApiException(streamed.statusCode, body);
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected analyze response');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> createPrescription({
    required String source,
    String? title,
    String? patientName,
    String? doctorName,
    String? prescriptionDate,
    String? diagnosis,
    String? generalInstructions,
    String? extractionNotes,
    required List<Map<String, dynamic>> medications,
    Map<String, dynamic>? rawAnalysis,
  }) async {
    final uri = Uri.parse('$_base/api/prescriptions');
    final payload = <String, dynamic>{
      'source': source,
      'title': _emptyToNull(title),
      'patient_name': _emptyToNull(patientName),
      'doctor_name': _emptyToNull(doctorName),
      'prescription_date': _emptyToNull(prescriptionDate),
      'diagnosis': _emptyToNull(diagnosis),
      'general_instructions': _emptyToNull(generalInstructions),
      'extraction_notes': _emptyToNull(extractionNotes),
      'medications': medications,
      'raw_analysis': rawAnalysis,
    };
    final res = await http.post(
      uri,
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected create response');
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> listPrescriptions() async {
    final uri = Uri.parse('$_base/api/prescriptions');
    final res = await http.get(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['prescriptions'] is! List) {
      throw const FormatException('Unexpected list response');
    }
    return (decoded['prescriptions'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String? _emptyToNull(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  String _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}

class MediBuddyApiException implements Exception {
  MediBuddyApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'MediBuddyApiException($statusCode): $body';
}
