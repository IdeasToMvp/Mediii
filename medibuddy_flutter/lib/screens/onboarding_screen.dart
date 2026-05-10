import 'package:flutter/material.dart';

import '../services/onboarding_prefs.dart';
import '../theme/medisathi_colors.dart';

/// Three-screen walkthrough shown after splash, before login.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  Future<void> _finish() async {
    await OnboardingPrefs.markCompleted();
    if (!mounted) return;
    widget.onFinished();
  }

  void _skip() => _finish();

  void _next() {
    if (_page < 2) {
      _pageController.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_page > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            _Page1(onSkip: _skip, onNext: _next),
            _Page2(onNext: _next, onSkip: _skip),
            _Page3(onBack: _back, onGetStarted: _finish),
          ],
        ),
      ),
    );
  }
}

/// Dots under content: blue pill + grey dots for 3 pages.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final sel = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: sel ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: sel ? MediSathiColors.brandBlue : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: MediSathiColors.brandBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward_rounded, size: 22),
          ],
        ),
      ),
    );
  }
}

class _Page1 extends StatelessWidget {
  const _Page1({required this.onSkip, required this.onNext});

  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MediSathi',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: MediSathiColors.brandBlue,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              TextButton(
                onPressed: onSkip,
                child: Text('Skip', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _HeroMedicalCard(),
                  const SizedBox(height: 28),
                  Text(
                    'Store prescriptions safely',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          letterSpacing: -0.6,
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Keep all your medical documents in one secure place.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: MediSathiColors.mutedText,
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const _PageDots(index: 0),
          const SizedBox(height: 20),
          _PrimaryButton(label: 'Next', onPressed: onNext),
        ],
      ),
    );
  }
}

class _HeroMedicalCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0F172A),
                    MediSathiColors.splashBlueDeep,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: MediSathiColors.brandBlue.withValues(alpha: 0.25),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          MediSathiColors.brandBlue.withValues(alpha: 0.45),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  Icon(Icons.healing_rounded, size: 88, color: Colors.white.withValues(alpha: 0.95)),
                  Positioned(
                    bottom: 22,
                    child: Text(
                      'MEDICAL SAFE RECORDS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white54,
                            letterSpacing: 1.8,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 18,
            right: 8,
            child: Transform.rotate(
              angle: 0.04,
              child: _FloatCard(
                icon: Icon(Icons.shield_outlined, color: Colors.teal.shade700, size: 28),
                label: 'SECURITY',
                headline: 'Encrypted',
              ),
            ),
          ),
          Positioned(
            bottom: -6,
            left: -2,
            child: Transform.rotate(
              angle: -0.05,
              child: _FloatCard(
                icon: Icon(Icons.folder_open_rounded, color: MediSathiColors.brandBlue, size: 28),
                label: 'STORAGE',
                headline: 'Unlimited',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatCard extends StatelessWidget {
  const _FloatCard({
    required this.icon,
    required this.label,
    required this.headline,
  });

  final Widget icon;
  final String label;
  final String headline;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon,
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: MediSathiColors.mutedText,
                    letterSpacing: 0.6,
                  ),
            ),
            const SizedBox(height: 4),
            Text(headline, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Page2 extends StatelessWidget {
  const _Page2({required this.onNext, required this.onSkip});

  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  _ScanIllustration(),
                  const SizedBox(height: 32),
                  Text(
                    'Scan and organize instantly',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Use AI to extract medicines and doctor details from your reports.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: MediSathiColors.mutedText,
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const _PageDots(index: 1),
          const SizedBox(height: 18),
          _PrimaryButton(label: 'Next', onPressed: onNext),
          TextButton(onPressed: onSkip, child: Text('Skip for now', style: TextStyle(color: Colors.grey.shade600))),
        ],
      ),
    );
  }
}

class _ScanIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.92,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [Colors.grey.shade200, Colors.grey.shade100],
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(36),
                          child: Icon(Icons.description_rounded, size: 96, color: Colors.grey.shade400),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          top: 0,
                          bottom: 0,
                          child: CustomPaint(painter: _ScanBeamPainter(progress: 0.55)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.smartphone_rounded, color: Colors.grey.shade700, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'AI scan',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 18,
            child: Material(
              elevation: 4,
              shape: const CircleBorder(),
              child: CircleAvatar(
                backgroundColor: Colors.green.shade500,
                child: const Icon(Icons.check_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanBeamPainter extends CustomPainter {
  _ScanBeamPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.green.withValues(alpha: 0),
          Colors.green.withValues(alpha: 0.85),
          Colors.green.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 14, size.width, 28))
      ..strokeWidth = 26
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, y - 4, size.width, 12), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Page3 extends StatelessWidget {
  const _Page3({required this.onBack, required this.onGetStarted});

  final VoidCallback onBack;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Text(
              'MediSathi',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: MediSathiColors.brandBlue,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  _FamilyCard(),
                  const SizedBox(height: 28),
                  Text(
                    'Manage family health records',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Easily track the medical history of your parents, children, and yourself.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: MediSathiColors.mutedText,
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const _PageDots(index: 2),
          const SizedBox(height: 20),
          _PrimaryButton(label: 'Get Started', onPressed: onGetStarted),
          TextButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.05,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(Icons.groups_2_rounded, size: 140, color: MediSathiColors.brandBlue.withValues(alpha: 0.85)),
            ),
            Positioned(
              bottom: 20,
              left: 20,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: MediSathiColors.brandBlue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'SYNC STATUS',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: MediSathiColors.brandBlue,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '3 Members Updated',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
