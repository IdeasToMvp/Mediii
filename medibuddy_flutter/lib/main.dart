import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'widgets/app_bootstrap.dart';

Future<void> _exchangeOAuthCodeOnWeb() async {
  if (!kIsWeb) return;
  final uri = Uri.base;
  if (!uri.queryParameters.containsKey('code')) return;
  if (Supabase.instance.client.auth.currentSession != null) return;
  try {
    await Supabase.instance.client.auth.getSessionFromUrl(uri);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('PKCE code exchange failed: $e\n$st');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.supabaseUrl.trim().isEmpty || AppConfig.supabaseAnonKey.trim().isEmpty) {
    runApp(const _MissingSupabaseConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl.trim(),
    anonKey: AppConfig.supabaseAnonKey.trim(),
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );

  // Flutter web: ensure PKCE `?code=` is exchanged (app_links initial href can miss it in some hosts).
  await _exchangeOAuthCodeOnWeb();

  runApp(const MediBuddyApp());
}

class MediBuddyApp extends StatelessWidget {
  const MediBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediSathi',
      theme: AppTheme.mobileFirst(),
      home: AppTheme.constrainMobileWidth(maxWidth: 640, child: const AppBootstrap()),
    );
  }
}

class _MissingSupabaseConfigApp extends StatelessWidget {
  const _MissingSupabaseConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediSathi',
      theme: AppTheme.mobileFirst(),
      home: AppTheme.constrainMobileWidth(
        maxWidth: 640,
        child: Scaffold(
          appBar: AppBar(title: const Text('MediSathi')),
          body: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Missing Supabase configuration'),
                SizedBox(height: 10),
                Text(
                  'Run the app with --dart-define=SUPABASE_URL=... '
                  '--dart-define=SUPABASE_ANON_KEY=...\n'
                  '(see README.md in the repo root)',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
