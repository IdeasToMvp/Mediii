import 'package:flutter/material.dart';

/// Provides dark-mode toggle from deep routes (e.g. Profile) without global state packages.
class AppThemeScope extends InheritedWidget {
  const AppThemeScope({
    super.key,
    required this.darkMode,
    required this.onDarkModeChanged,
    required super.child,
  });

  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  /// Subscribe so switches rebuild when theme toggles from the same widget.
  static AppThemeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) {
    return oldWidget.darkMode != darkMode || oldWidget.onDarkModeChanged != onDarkModeChanged;
  }
}
