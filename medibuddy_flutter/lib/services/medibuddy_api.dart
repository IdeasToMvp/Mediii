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

  Future<Map<String, dynamic>> uploadPrescriptionSource(XFile file) async {
    final uri = Uri.parse('$_base/api/prescriptions/upload-source');
    final bytes = await file.readAsBytes();
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_authHeaders);
    final name = file.name.isNotEmpty ? file.name : 'document.bin';
    final mime = _guessUploadMime(name);
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
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
      throw const FormatException('Unexpected upload-source response');
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
    String? documentKind,
    Map<String, dynamic>? reportSummary,
    String? sourceStoragePath,
    String? sourceMime,
    String? sourceOriginalName,
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
    final dk = documentKind?.trim().toLowerCase();
    if (dk != null && dk.isNotEmpty) {
      payload['document_kind'] = dk;
    }
    if (reportSummary != null) {
      payload['report_summary'] = reportSummary;
    }
    final path = _emptyToNull(sourceStoragePath);
    if (path != null) {
      payload['source_storage_path'] = path;
      payload['source_mime'] = _emptyToNull(sourceMime);
      payload['source_original_name'] = _emptyToNull(sourceOriginalName);
    }
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

  Future<List<Map<String, dynamic>>> listPrescriptions({String? kind}) async {
    var uri = Uri.parse('$_base/api/prescriptions');
    if (kind != null && kind.trim().isNotEmpty) {
      uri = uri.replace(queryParameters: {'kind': kind.trim().toLowerCase()});
    }
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

  Future<Map<String, dynamic>> getPrescription(String id) async {
    final uri = Uri.parse('$_base/api/prescriptions/$id');
    final res = await http.get(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected prescription response');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> updatePrescription(String id, Map<String, dynamic> patch) async {
    final uri = Uri.parse('$_base/api/prescriptions/$id');
    final res = await http.patch(
      uri,
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected update prescription response');
    }
    return decoded;
  }

  Future<void> deletePrescription(String id) async {
    final uri = Uri.parse('$_base/api/prescriptions/$id');
    final res = await http.delete(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    final uri = Uri.parse('$_base/api/me');
    final res = await http.get(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected /api/me payload');
    }
    return decoded;
  }

  /// PATCH [display_name], [birth_year], [gender], [timezone]. Omit keys you do not want to change; send null to clear.
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> patch) async {
    final uri = Uri.parse('$_base/api/me/profile');
    final res = await http.patch(
      uri,
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected profile patch response');
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> fetchUpcomingMedicineOccurrences({int days = 3}) async {
    final uri = Uri.parse('$_base/api/medicine-schedules/upcoming').replace(queryParameters: {
      'days': '$days',
    });
    final res = await http.get(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['occurrences'] is! List) {
      throw const FormatException('Unexpected upcoming meds payload');
    }
    return (decoded['occurrences'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listMedicineSchedules() async {
    final uri = Uri.parse('$_base/api/medicine-schedules');
    final res = await http.get(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['schedules'] is! List) {
      throw const FormatException('Unexpected medicine-schedules list');
    }
    return (decoded['schedules'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createMedicineSchedule(Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base/api/medicine-schedules');
    final res = await http.post(
      uri,
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected create schedule response');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> updateMedicineSchedule(String id, Map<String, dynamic> patch) async {
    final uri = Uri.parse('$_base/api/medicine-schedules/$id');
    final res = await http.patch(
      uri,
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected update schedule response');
    }
    return decoded;
  }

  Future<void> deleteMedicineSchedule(String id) async {
    final uri = Uri.parse('$_base/api/medicine-schedules/$id');
    final res = await http.delete(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
  }

  Future<Map<String, dynamic>> listFamilyPayload() async {
    final uri = Uri.parse('$_base/api/family-members');
    final res = await http.get(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected family-members payload');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> createFamilyMember({
    required String displayName,
    String? relation,
    int? birthYear,
    String? notes,
  }) async {
    final uri = Uri.parse('$_base/api/family-members');
    final bodyMap = <String, dynamic>{
      'display_name': displayName,
    };
    final rel = relation?.trim();
    if (rel != null && rel.isNotEmpty) {
      bodyMap['relation'] = rel;
    }
    if (birthYear != null) {
      bodyMap['birth_year'] = birthYear;
    }
    final nt = notes?.trim();
    if (nt != null && nt.isNotEmpty) bodyMap['notes'] = nt;
    final res = await http.post(
      uri,
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(bodyMap),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected create member response');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> updateFamilyMember(
    String id, {
    String? displayName,
    String? relation,
    bool clearRelation = false,
    int? birthYear,
    bool clearBirthYear = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    final uri = Uri.parse('$_base/api/family-members/$id');
    final bodyMap = <String, dynamic>{};
    if (displayName != null) bodyMap['display_name'] = displayName;
    if (clearRelation) {
      bodyMap['relation'] = null;
    } else if (relation != null) {
      final rel = relation.trim();
      bodyMap['relation'] = rel.isEmpty ? null : rel;
    }
    if (clearBirthYear) {
      bodyMap['birth_year'] = null;
    } else if (birthYear != null) {
      bodyMap['birth_year'] = birthYear;
    }
    if (clearNotes) {
      bodyMap['notes'] = null;
    } else if (notes != null) {
      final n = notes.trim();
      bodyMap['notes'] = n.isEmpty ? null : n;
    }
    final res = await http.patch(
      uri,
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(bodyMap),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected update member response');
    }
    return decoded;
  }

  Future<void> deleteFamilyMember(String id) async {
    final uri = Uri.parse('$_base/api/family-members/$id');
    final res = await http.delete(uri, headers: _authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MediBuddyApiException(res.statusCode, res.body);
    }
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

  String _guessUploadMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return _guessMime(name);
  }
}

class MediBuddyApiException implements Exception {
  MediBuddyApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'MediBuddyApiException($statusCode): $body';
}
