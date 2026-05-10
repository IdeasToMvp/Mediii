import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/home_shell.dart';
import '../screens/splash_screen.dart';

/// Shows [SplashScreen] when there is no cached session; otherwise opens [HomeShell].
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    _showSplash = Supabase.instance.client.auth.currentSession == null;
  }

  void _onSplashDone() {
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(onFinished: _onSplashDone);
    }
    return const HomeShell();
  }
}
