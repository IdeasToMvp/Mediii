import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

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

  runApp(const MediBuddyApp());
}

class MediBuddyApp extends StatelessWidget {
  const MediBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediBuddy',
      theme: AppTheme.mobileFirst(),
      home: AppTheme.constrainMobileWidth(maxWidth: 640, child: const HomeShell()),
    );
  }
}

class _MissingSupabaseConfigApp extends StatelessWidget {
  const _MissingSupabaseConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediBuddy',
      theme: AppTheme.mobileFirst(),
      home: AppTheme.constrainMobileWidth(
        maxWidth: 640,
        child: Scaffold(
          appBar: AppBar(title: const Text('MediBuddy')),
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
