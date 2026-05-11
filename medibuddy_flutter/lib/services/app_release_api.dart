import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/app_release.dart';

class AppReleaseApiException implements Exception {
  AppReleaseApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'AppReleaseApiException($statusCode)';
}

/// Public endpoints — no Supabase session required.
class AppReleaseApi {
  String get _base => AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');

  Future<AppRelease?> fetchLatest({String channel = 'production', String platform = 'android'}) async {
    final uri = Uri.parse('$_base/api/app-releases/latest').replace(queryParameters: {
      'channel': channel,
      'platform': platform,
    });
    final res = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppReleaseApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid release JSON');
    final rel = decoded['release'];
    if (rel is! Map<String, dynamic>) throw const FormatException('Missing release');
    return AppRelease.fromJson(rel);
  }

  Future<Uri> fetchDownloadUri(String releaseId) async {
    final uri = Uri.parse('$_base/api/app-releases/$releaseId/download-url');
    final res = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppReleaseApiException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid download-url JSON');
    final url = decoded['download_url'];
    if (url is! String || url.isEmpty) throw const FormatException('Missing download_url');
    final out = Uri.tryParse(url);
    if (out == null) throw const FormatException('Invalid download_url');
    return out;
  }
}
