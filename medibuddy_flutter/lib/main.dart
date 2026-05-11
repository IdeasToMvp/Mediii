import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme_scope.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'widgets/app_bootstrap.dart';
import 'widgets/app_update_prompt.dart';

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

/// Web (and some browsers) can briefly report negative keyboard insets during
/// resize; the Flutter web engine asserts on non-negative view insets.
MediaQueryData _nonNegativeViewInsets(MediaQueryData mq) {
  final v = mq.viewInsets;
  return mq.copyWith(
    viewInsets: EdgeInsets.fromLTRB(
      v.left.clamp(0.0, double.infinity),
      v.top.clamp(0.0, double.infinity),
      v.right.clamp(0.0, double.infinity),
      v.bottom.clamp(0.0, double.infinity),
    ),
  );
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

  await _exchangeOAuthCodeOnWeb();

  runApp(const MediBuddyApp());
}

class MediBuddyApp extends StatefulWidget {
  const MediBuddyApp({super.key});

  @override
  State<MediBuddyApp> createState() => _MediBuddyAppState();
}

class _MediBuddyAppState extends State<MediBuddyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    AppUpdatePrompt.scheduleAfterSplash(_rootNavigatorKey);
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      if (p.getBool('pref_dark_mode') == true) {
        setState(() => _themeMode = ThemeMode.dark);
      }
    });
  }

  void _setDarkMode(bool dark) {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
    SharedPreferences.getInstance().then((p) => p.setBool('pref_dark_mode', dark));
  }

  @override
  Widget build(BuildContext context) {
    final appRoot = AppThemeScope(
      darkMode: _themeMode == ThemeMode.dark,
      onDarkModeChanged: _setDarkMode,
      child: const AppBootstrap(),
    );
    return MaterialApp(
      title: 'MediSathi',
      navigatorKey: _rootNavigatorKey,
      theme: AppTheme.mobileFirst(),
      darkTheme: AppTheme.mobileFirstDark(),
      themeMode: _themeMode,
      builder: (context, child) {
        return MediaQuery(data: _nonNegativeViewInsets(MediaQuery.of(context)), child: child ?? const SizedBox.shrink());
      },
      // Web should use the full viewport like a normal site; native apps stay in a phone-width shell.
      home: kIsWeb ? appRoot : AppTheme.constrainMobileWidth(maxWidth: 640, child: appRoot),
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
      builder: (context, child) {
        return MediaQuery(data: _nonNegativeViewInsets(MediaQuery.of(context)), child: child ?? const SizedBox.shrink());
      },
      home: kIsWeb
          ? Scaffold(
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
            )
          : AppTheme.constrainMobileWidth(
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
