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
  ///
  /// **Web (hosted):** when `API_BASE_URL` is not set at build time, the app uses [Uri.base.origin]
  /// so all `/api/*` calls hit the **same host** as the Flutter web bundle (e.g. Vercel). Route
  /// `/api/*` there to your Node API (see `vercel.json` rewrites). This avoids failures in embedded
  /// browsers (WhatsApp, Instagram, etc.) that often block cross-origin fetch to another domain.
  static String get apiBaseUrl {
    final trimmed = _apiDefault.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      final local =
          host == 'localhost' || host == '127.0.0.1' || host == '[::1]' || host.endsWith('.local');
      if (local) return 'http://localhost:3200';
      return Uri.base.origin;
    }
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
