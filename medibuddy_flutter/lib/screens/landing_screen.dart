import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/medisathi_colors.dart';
import '../widgets/android_release_download_panel.dart';
import '../widgets/app_release_download_launcher.dart';
import '../widgets/landing_top_build_downloads.dart';
import '../widgets/landing_page_sections.dart';
import '../widgets/medisathi_logo.dart';
import '../services/app_release_api.dart';
import 'login_screen.dart';

/// Web-only: animated marketing landing → sign-in with smooth transitions.
class WelcomeWebFlow extends StatefulWidget {
  const WelcomeWebFlow({super.key});

  @override
  State<WelcomeWebFlow> createState() => _WelcomeWebFlowState();
}

class _WelcomeWebFlowState extends State<WelcomeWebFlow> {
  bool _showLogin = false;

  static Widget _landingToLoginFade(Widget child, Animation<double> anim) {
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.02, 0.02), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Belt-and-suspenders: native Android / iOS should never ship this funnel (see HomeShell routing).
    if (!kIsWeb) return const LoginScreen();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => _landingToLoginFade(child, anim),
      child: _showLogin
          ? KeyedSubtree(
              key: const ValueKey('login'),
              child: LoginScreen(
                onBack: () => setState(() => _showLogin = false),
              ),
            )
          : KeyedSubtree(
              key: const ValueKey('landing'),
              child: LandingScreen(
                onRequestSignIn: () => setState(() => _showLogin = true),
              ),
            ),
    );
  }
}

/// MediSathi public marketing page (web only). On native platforms the app uses [LoginScreen] instead.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key, required this.onRequestSignIn});

  final VoidCallback onRequestSignIn;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> with TickerProviderStateMixin {
  late final AnimationController _entrance;

  late final Animation<double> _heroT;
  late final Animation<double> _subT;
  late final Animation<double> _ctaT;
  late final Animation<double> _gridT;

  late final Animation<Offset> _heroSlide;

  /// One shared `/api/app-releases/latest?platform=android` load for hero strip + footer card.
  late final Future<AndroidLatestSnapshot> _androidLandingFuture;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _faqKey = GlobalKey();
  final GlobalKey _privacyKey = GlobalKey();
  final GlobalKey _aboutKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _androidLandingFuture = _fetchAndroidLandingForHero();
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _heroT = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.38, curve: Curves.easeOutCubic),
    );
    _subT = CurvedAnimation(parent: _entrance, curve: const Interval(0.12, 0.48, curve: Curves.easeOutCubic));
    _ctaT = CurvedAnimation(parent: _entrance, curve: const Interval(0.22, 0.58, curve: Curves.easeOutCubic));
    _gridT = CurvedAnimation(parent: _entrance, curve: const Interval(0.32, 0.88, curve: Curves.easeOutCubic));
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _entrance, curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic)),
    );
    _entrance.forward();
  }

  Future<AndroidLatestSnapshot> _fetchAndroidLandingForHero() async {
    if (!AndroidReleaseDownloadPanel.offerApkHere) return const AndroidLatestSnapshot();
    try {
      final release = await AppReleaseApi().fetchLatest(platform: 'android');
      return AndroidLatestSnapshot(release: release);
    } catch (e) {
      return AndroidLatestSnapshot(error: e);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const LoginScreen();

    final w = MediaQuery.sizeOf(context).width;
    // Reads like a marketing site on large desktops; still comfortable on tablets/phones.
    final maxContent = (w * 0.94).clamp(320.0, 1320.0);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF5FAFF),
              Color(0xFFE8F2FC),
              Color(0xFFF0F4FA),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: CustomPaint(
          painter: _SoftGridPainter(),
          child: SafeArea(
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContent),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cw = constraints.maxWidth;
                      final wideHero = cw >= 920;
                      final hPad = cw >= 900 ? 40.0 : (cw >= 480 ? 22.0 : 16.0);
                      final subAlign = wideHero ? TextAlign.left : TextAlign.center;

                      Widget subHeading() => FadeTransition(
                            opacity: _subT,
                            child: Text(
                              'One calm place for prescriptions, lab reports, and reminders — organised for your whole household.',
                              textAlign: subAlign,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    height: 1.45,
                                    color: MediSathiColors.mutedText,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.15,
                                  ),
                            ),
                          );

                      final heroBlock = SlideTransition(
                        position: _heroSlide,
                        child: _HeroBlock(
                          heroT: _heroT,
                          headlineTextAlign: wideHero ? TextAlign.left : TextAlign.center,
                          badgeCentered: !wideHero,
                        ),
                      );

                      final trustSub = Text(
                        'Secure sign-in · Encrypted transit · Designed for carers & patients alike',
                        textAlign: wideHero ? TextAlign.left : TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MediSathiColors.mutedText, height: 1.4),
                      );

                      final heroDownloads = FadeTransition(
                        opacity: _ctaT,
                        child: Column(
                          crossAxisAlignment: wideHero ? CrossAxisAlignment.start : CrossAxisAlignment.stretch,
                          children: [
                            if (AndroidReleaseDownloadPanel.offerApkHere) ...[
                              LandingTopBuildDownloads(
                                snapshotFuture: _androidLandingFuture,
                                wrapAlignment: wideHero ? WrapAlignment.start : WrapAlignment.center,
                              ),
                              const SizedBox(height: 14),
                            ],
                            trustSub,
                          ],
                        ),
                      );

                      return Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildNav(context, cw),
                            _buildNavLinks(context, wideHero),
                            SizedBox(height: wideHero ? 24 : (cw < 400 ? 16 : 20)),
                            if (!wideHero) ...[
                              heroBlock,
                              const SizedBox(height: 10),
                              subHeading(),
                              const SizedBox(height: 28),
                              heroDownloads,
                            ] else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 58,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        heroBlock,
                                        const SizedBox(height: 14),
                                        subHeading(),
                                        const SizedBox(height: 28),
                                        heroDownloads,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 32),
                                  Expanded(
                                    flex: 42,
                                    child: FadeTransition(
                                      opacity: _heroT,
                                      child: const _HeroAsidePanel(),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 48),
                            FadeTransition(opacity: _gridT, child: _FeatureSection()),
                            const SizedBox(height: 40),
                            FadeTransition(opacity: _gridT, child: _TrustStrip()),
                            const SizedBox(height: 40),
                            FadeTransition(opacity: _gridT, child: AndroidReleaseDownloadPanel(sharedSnapshotFuture: _androidLandingFuture)),
                            const SizedBox(height: 40),
                            FadeTransition(
                              opacity: _gridT,
                              child: _InfoSectionCard(
                                child: LandingFaqSection(key: _faqKey),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FadeTransition(
                              opacity: _gridT,
                              child: _InfoSectionCard(
                                child: LandingPrivacySection(key: _privacyKey),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FadeTransition(
                              opacity: _gridT,
                              child: _InfoSectionCard(
                                child: LandingAboutSection(key: _aboutKey),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FadeTransition(
                              opacity: _gridT,
                              child: _InfoSectionCard(
                                child: LandingContactSection(key: _contactKey),
                              ),
                            ),
                            const SizedBox(height: 32),
                            const _FooterMini(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavLinks(BuildContext context, bool wideHero) {
    final muted = MediSathiColors.mutedText.withValues(alpha: 0.82);
    Widget link(String label, GlobalKey k) {
      return TextButton(
        onPressed: () => _scrollTo(k),
        style: TextButton.styleFrom(
          foregroundColor: MediSathiColors.brandTeal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: wideHero ? WrapAlignment.start : WrapAlignment.center,
        spacing: 0,
        runSpacing: 4,
        children: [
          link('FAQ', _faqKey),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('·', style: TextStyle(color: muted, fontSize: 14, height: 1)),
          ),
          link('Privacy', _privacyKey),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('·', style: TextStyle(color: muted, fontSize: 14, height: 1)),
          ),
          link('About', _aboutKey),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('·', style: TextStyle(color: muted, fontSize: 14, height: 1)),
          ),
          link('Contact', _contactKey),
        ],
      ),
    );
  }

  Widget _buildNav(BuildContext context, double contentWidth) {
    void goSignIn() => widget.onRequestSignIn();

    /// Sign-in lives in the app bar only; hero focuses on installs + trust copy.
    final iconOnlySignIn = contentWidth < 364;

    Widget signInControl() {
      if (iconOnlySignIn) {
        return IconButton.filledTonal(
          onPressed: goSignIn,
          tooltip: 'Sign in',
          style: IconButton.styleFrom(
            foregroundColor: MediSathiColors.brandBlue,
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.login_rounded, size: 22),
        );
      }
      return OutlinedButton.icon(
        onPressed: goSignIn,
        icon: const Icon(Icons.login_rounded, size: 20),
        label: const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: MediSathiColors.brandBlue,
          side: BorderSide(color: MediSathiColors.brandBlue.withValues(alpha: 0.42)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    Widget logoRow() {
      return Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MediSathiLogo(height: iconOnlySignIn ? 34 : 42),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        logoRow(),
        const SizedBox(width: 8),
        signInControl(),
      ],
    );
  }
}

/// Soft card wrapper for FAQ / legal / contact blocks.
class _InfoSectionCard extends StatelessWidget {
  const _InfoSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      elevation: 0,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
          boxShadow: [
            BoxShadow(
              color: MediSathiColors.brandBlue.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({
    required this.heroT,
    this.headlineTextAlign = TextAlign.center,
    this.badgeCentered = true,
  });

  final Animation<double> heroT;
  final TextAlign headlineTextAlign;
  final bool badgeCentered;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFCCFBF1).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 16, color: Colors.teal.shade800),
          const SizedBox(width: 8),
          Text(
            'Built for clarity, not clutter',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF115E59),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );

    return FadeTransition(
      opacity: heroT,
      child: Column(
        crossAxisAlignment: badgeCentered ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          if (badgeCentered) Center(child: badge) else badge,
          const SizedBox(height: 22),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [MediSathiColors.brandTeal, MediSathiColors.brandBlue],
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Text(
              'Your family’s health documents,\nbeautifully organised.',
              textAlign: headlineTextAlign,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                    color: Colors.white,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marketing snapshot card for wide desktop hero layout.
class _HeroAsidePanel extends StatelessWidget {
  const _HeroAsidePanel();

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: MediSathiColors.brandBlue.withValues(alpha: 0.88)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: MediSathiColors.mutedText,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.92),
            const Color(0xFFE8F2FC).withValues(alpha: 0.95),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: MediSathiColors.brandBlue.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: MediSathiColors.brandBlue, size: 22),
              const SizedBox(width: 10),
              Text(
                'Everything in reach',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E3A5F),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          line(Icons.description_outlined, 'Prescriptions and lab PDFs in one calm vault'),
          line(Icons.photo_library_outlined, 'Keep originals when a photo is all you have'),
          line(Icons.alarm_outlined, 'Reminders grounded in what was actually prescribed'),
          const SizedBox(height: 6),
          Text(
            'Sign in keeps your household private — modern auth, encrypted in transit.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MediSathiColors.mutedText, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _FeatureSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tiles = [
      (
        Icons.folder_shared_outlined,
        'Records in one vault',
        'Prescriptions & reports stay together — with optional original photos or PDFs attached.',
      ),
      (
        Icons.notifications_active_outlined,
        'Smarter reminders',
        'Medicine schedules you can rely on — with context from what was actually prescribed.',
      ),
      (
        Icons.groups_2_outlined,
        'Household profiles',
        'Track care for partner, parents, or kids with clear limits — Free vs Pro where it matters.',
      ),
      (
        Icons.document_scanner_outlined,
        'AI-assisted uploads (Pro)',
        'Snap a script; we help classify and draft details — you always review before saving.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final mw = constraints.maxWidth;
        final cols = mw >= 1180 ? 3 : (mw > 720 ? 2 : 1);
        final gap = (cols > 1) ? 16.0 * (cols - 1) : 0.0;
        final tileW = cols == 1 ? mw : (mw - gap) / cols;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What you get',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1E3A5F),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Practical tools for real clinic paperwork — minus the spreadsheets and shoeboxes.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MediSathiColors.mutedText, height: 1.35),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.start,
              children: tiles.map((t) {
                return SizedBox(
                  width: tileW.clamp(0.0, mw),
                  child: _FeatureCard(icon: t.$1, title: t.$2, body: t.$3),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.82),
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(
              color: MediSathiColors.brandBlue.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MediSathiColors.brandBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: MediSathiColors.brandBlue, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF1E3A5F)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MediSathiColors.mutedText, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF172554).withValues(alpha: 0.92),
            const Color(0xFF1E3A5F).withValues(alpha: 0.88),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF172554).withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, color: MediSathiColors.neonAccent.withValues(alpha: 0.95), size: 22),
              const SizedBox(width: 10),
              Text(
                'Privacy-minded by design',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your data is tied to your account with modern authentication. We don’t sell health information. '
            'Always follow your clinician’s advice — MediSathi helps you organise, not diagnose.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.88), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FooterMini extends StatelessWidget {
  const _FooterMini();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(color: MediSathiColors.brandBlue.withValues(alpha: 0.12)),
        const SizedBox(height: 16),
        Text(
          'MediSathi · Care records for modern families',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: MediSathiColors.mutedText,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Visit www.medisathi.com',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MediSathiColors.mutedText.withValues(alpha: 0.85)),
        ),
      ],
    );
  }
}

/// Subtle background grid for a clinical “chart paper” feel.
class _SoftGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = MediSathiColors.brandBlue.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
