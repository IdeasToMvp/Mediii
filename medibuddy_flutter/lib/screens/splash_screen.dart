import 'package:flutter/material.dart';

import '../theme/medisathi_colors.dart';
import '../widgets/medisathi_logo.dart';

/// Initial loading experience: gradient, mark, tagline, encryption note, progress.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..forward();

    _controller.addStatusListener(_onAnimStatus);
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      Future<void>.delayed(const Duration(milliseconds: 200)).then((_) {
        if (!mounted) return;
        widget.onFinished();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              MediSathiColors.splashBlue,
              MediSathiColors.splashBlueDeep,
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_controller.value);
              return Column(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: MediSathiLogo(height: MediaQuery.sizeOf(context).shortestSide < 380 ? 100 : 118),
                        ),
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Digital peace of mind for your family’s health records.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  height: 1.45,
                                  fontWeight: FontWeight.w400,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 36),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline, size: 14, color: Colors.white.withValues(alpha: 0.75)),
                            const SizedBox(width: 6),
                            Text(
                              'Secure Institutional Encryption',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    letterSpacing: 0.3,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: t,
                            minHeight: 4,
                            backgroundColor: Colors.black.withValues(alpha: 0.25),
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
