import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/medisathi_colors.dart';

/// Frequently asked questions — expandable tiles.
class LandingFaqSection extends StatelessWidget {
  const LandingFaqSection({super.key});

  static final _items = <({String q, String a})>[
    (
      q: 'What is MediSathi?',
      a:
          'MediSathi is a calm place to organise prescriptions, lab PDFs, and reminders for your whole household — '
          'so paperwork stops living in random chat threads and shoeboxes.',
    ),
    (
      q: 'Is my health data safe?',
      a:
          'We use modern sign-in and encrypt data in transit. Your records stay tied to your account. '
          'MediSathi helps you organise information; it does not replace your doctor’s advice.',
    ),
    (
      q: 'Can I use MediSathi for my parents or kids?',
      a:
          'Yes. Household profiles let carers manage records for family members with clear boundaries. '
          'Features differ between Free and Pro where noted in the app.',
    ),
    (
      q: 'Does MediSathi diagnose or prescribe?',
      a:
          'No. MediSathi is not a medical device and does not provide diagnoses or treatment plans. '
          'Always follow guidance from your licensed clinician.',
    ),
    (
      q: 'How do I get the Android app?',
      a:
          'Use “Download APK” on this page when a build is published, or check back after sign-in for install links. '
          'Allow installs from your browser or file manager when Android prompts.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: const Color(0xFF1E3A5F),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.help_outline_rounded, color: MediSathiColors.brandTeal, size: 26),
            const SizedBox(width: 10),
            Text('FAQ', style: heading),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Quick answers about MediSathi. For anything else, use Contact us below.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MediSathiColors.mutedText, height: 1.35),
        ),
        const SizedBox(height: 16),
        ..._items.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white.withValues(alpha: 0.88),
              elevation: 0,
              borderRadius: BorderRadius.circular(14),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: MediSathiColors.brandBlue.withValues(alpha: 0.08)),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: MediSathiColors.brandBlue.withValues(alpha: 0.08)),
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  iconColor: MediSathiColors.brandBlue,
                  collapsedIconColor: MediSathiColors.brandBlue,
                  title: Text(e.q, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.35)),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        e.a,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: MediSathiColors.mutedText,
                              height: 1.5,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Privacy policy summary (not legal advice; user may replace with counsel-reviewed copy).
class LandingPrivacySection extends StatelessWidget {
  const LandingPrivacySection({super.key});

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: const Color(0xFF1E3A5F),
        );
    const paras = [
      'MediSathi helps you store and organise health-related documents and reminders you choose to add. '
          'Access is protected by the authentication method you use to sign in.',
      'We process information as needed to run the service (for example hosting your account data, enabling uploads, '
          'and operating AI-assisted features where you opt in). We do not sell personal health information.',
      'You can request account or data assistance by contacting us (see Contact us). '
          'Use of MediSathi is also governed by any terms presented in the app at signup or checkout.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.privacy_tip_outlined, color: MediSathiColors.brandTeal, size: 26),
            const SizedBox(width: 10),
            Text('Privacy policy', style: heading),
          ],
        ),
        const SizedBox(height: 12),
        for (final p in paras) ...[
          Text(
            p,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MediSathiColors.mutedText, height: 1.5),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// About MediSathi — mission-oriented copy.
class LandingAboutSection extends StatelessWidget {
  const LandingAboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: const Color(0xFF1E3A5F),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.favorite_outline_rounded, color: MediSathiColors.brandTeal, size: 26),
            const SizedBox(width: 10),
            Text('About us', style: heading),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'MediSathi exists so families can keep prescriptions, lab work, and care context in one trustworthy place — '
          'with reminders grounded in what was actually prescribed. We believe clarity reduces stress at home and '
          'at the clinic, without replacing professional medical judgment.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MediSathiColors.mutedText, height: 1.5),
        ),
        const SizedBox(height: 12),
        Text(
          'Tagline: Your Health, Our Companion.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: MediSathiColors.brandBlue,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
        ),
      ],
    );
  }
}

/// Contact form → opens the user’s email client with a pre-filled message.
class LandingContactSection extends StatefulWidget {
  const LandingContactSection({super.key});

  /// Update to your production inbox when DNS / mail is ready.
  static const String supportEmail = 'jaswindersingh@iitdalumni.com';

  @override
  State<LandingContactSection> createState() => _LandingContactSectionState();
}

class _LandingContactSectionState extends State<LandingContactSection> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();
  String _topic = 'General question';

  static const _topics = [
    'General question',
    'Account or sign-in',
    'Bug or crash',
    'Billing / Pro',
    'Partnership or press',
  ];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final body = _message.text.trim();
    if (name.isEmpty || email.isEmpty || body.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in your name, email, and message.')),
      );
      return;
    }

    final uri = Uri(
      scheme: 'mailto',
      path: LandingContactSection.supportEmail,
      queryParameters: <String, String>{
        'subject': 'MediSathi — $_topic',
        'body': 'Name: $name\nReply-to: $email\nTopic: $_topic\n\nWhat we should know:\n$body',
      },
    );

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening your email app… Paste send if your client asks.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open email. Write to ${LandingContactSection.supportEmail}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: const Color(0xFF1E3A5F),
        );
    final fieldBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(12));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.mail_outline_rounded, color: MediSathiColors.brandTeal, size: 26),
            const SizedBox(width: 10),
            Text('Contact us', style: heading),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Tell us your name, the best email to reach you, and what you’d like help with. '
          'We may ask follow-up questions about device type or steps to reproduce — you can add those now.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MediSathiColors.mutedText, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Name',
            border: fieldBorder,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.92),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
            border: fieldBorder,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.92),
          ),
        ),
        const SizedBox(height: 12),
        DropdownMenu<String>(
          width: double.infinity,
          initialSelection: _topics.contains(_topic) ? _topic : _topics.first,
          label: const Text('Topic'),
          dropdownMenuEntries: _topics.map((t) => DropdownMenuEntry<String>(value: t, label: t)).toList(),
          onSelected: (v) => setState(() => _topic = v ?? _topics.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _message,
          minLines: 4,
          maxLines: 10,
          decoration: InputDecoration(
            alignLabelWithHint: true,
            labelText: 'What should we know?',
            hintText:
                'e.g. device (Android/iOS/web), app version, what you tried, screenshots described in words…',
            border: fieldBorder,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.92),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded, size: 20),
          label: const Text('Open email draft'),
          style: FilledButton.styleFrom(
            backgroundColor: MediSathiColors.brandBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Direct: ${LandingContactSection.supportEmail}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MediSathiColors.mutedText),
        ),
      ],
    );
  }
}
