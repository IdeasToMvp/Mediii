import 'package:flutter/material.dart';

import '../theme/medisathi_colors.dart';

/// Full MediSathi lockup (icon + wordmark + tagline) from brand assets.
class MediSathiLogo extends StatelessWidget {
  const MediSathiLogo({
    super.key,
    this.height = 48,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.centerLeft,
  });

  final double height;
  final BoxFit fit;
  final Alignment alignment;

  static const String _asset = 'assets/branding/medisathi_logo_full.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      semanticLabel: 'MediSathi — Your Health, Our Companion',
      errorBuilder: (context, error, stackTrace) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [MediSathiColors.brandTeal, MediSathiColors.brandBlue],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 10),
            Text(
              'MediSathi',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1E3A5F),
                  ),
            ),
          ],
        );
      },
    );
  }
}
