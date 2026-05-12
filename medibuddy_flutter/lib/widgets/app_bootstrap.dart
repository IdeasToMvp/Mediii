import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/home_shell.dart';
import '../screens/onboarding_screen.dart';
import '../screens/splash_screen.dart';
import '../services/onboarding_prefs.dart';
import 'medisathi_loader.dart';

/// Cold start (signed out): native → splash → onboarding (first launch) → [HomeShell].
/// Web signed out: no splash, no onboarding → [HomeShell] (landing + sign-in funnel).
/// Signed in: [HomeShell] directly.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final bool _signedIn;
  bool _showSplash = false;
  /// `null` = still loading prefs (signed-out path only).
  bool? _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _signedIn = Supabase.instance.client.auth.currentSession != null;
    if (_signedIn) {
      return;
    }
    // Web: skip splash and onboarding; HomeShell shows marketing landing.
    _showSplash = !kIsWeb;
    if (kIsWeb) {
      _onboardingComplete = true;
    } else {
      _loadOnboardingFlag();
    }
  }

  Future<void> _loadOnboardingFlag() async {
    final done = await OnboardingPrefs.isCompleted();
    if (!mounted) return;
    setState(() => _onboardingComplete = done);
  }

  void _onSplashDone() {
    setState(() => _showSplash = false);
  }

  void _onOnboardingDone() {
    setState(() => _onboardingComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_signedIn) {
      return const HomeShell();
    }
    if (_showSplash) {
      return SplashScreen(onFinished: _onSplashDone);
    }
    if (_onboardingComplete == null) {
      return const Scaffold(
        body: Center(
          child: MediSathiLoader(
            secondaryMessage: 'Checking your MediSathi setup…',
          ),
        ),
      );
    }
    if (!_onboardingComplete!) {
      return OnboardingScreen(onFinished: _onOnboardingDone);
    }
    return const HomeShell();
  }
}
