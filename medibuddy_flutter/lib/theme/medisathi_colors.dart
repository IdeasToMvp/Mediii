import 'package:flutter/material.dart';

/// Brand palette aligned with MediSathi mockups (splash + login).
abstract final class MediSathiColors {
  static const Color splashBlue = Color(0xFF1E40AF);
  static const Color splashBlueDeep = Color(0xFF172554);

  /// Primary blue from brand lockup (pairs with [brandTeal]).
  static const Color brandBlue = Color(0xFF1A5FB4);

  /// Teal accent from brand heart / “Medi” wordmark.
  static const Color brandTeal = Color(0xFF109488);
  static const Color cardBackground = Colors.white;
  static const Color pageLavender = Color(0xFFEEE9F7);
  static const Color mutedText = Color(0xFF6B7280);

  /// Futuristic accents (dashboard / glass surfaces).
  static const Color neonAccent = Color(0xFF22D3EE);
  static const Color surfaceDeep = Color(0xFF0B1224);
  static const Color glassBorder = Color(0x337C8AFF);
}
