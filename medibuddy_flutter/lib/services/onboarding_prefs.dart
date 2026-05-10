import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPrefs {
  OnboardingPrefs._();

  /// Bump if onboarding copy/order changes materially and users should see it again.
  static const String _key = 'onboarding_completed_mediv1';

  static Future<bool> isCompleted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
  }

  static Future<void> markCompleted() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
  }

  /// Dev / settings only — not wired in UI.
  static Future<void> resetForTesting() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
