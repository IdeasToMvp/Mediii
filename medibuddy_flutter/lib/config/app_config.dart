import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Compile-time overrides:
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbG...
///   --dart-define=API_BASE_URL=http://localhost:3200
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const String _apiDefault = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Android emulator: use `--dart-define=API_BASE_URL=http://10.0.2.2:3200`
  static String get apiBaseUrl {
    if (_apiDefault.isNotEmpty) return _apiDefault.trim();
    if (kIsWeb) return 'http://localhost:3200';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:3200';
    } catch (_) {
      /* dart:io unavailable on pure web isolate — already handled above */
    }
    return 'http://127.0.0.1:3200';
  }

  static String oauthRedirectUri() {
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return 'io.medibuddy.app://login-callback/';
  }

  static String getOAuthRedirectScheme() => 'io.medibuddy.app';
}
